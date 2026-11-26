import test from 'node:test';
import assert from 'node:assert/strict';
import {createCup, joinCup, startCup, recordResult, forfeitMatch, advanceCup, publicCup, completedScore, validCode} from '../src/cup-rules.mjs';
import {CupRoom} from '../src/cup-room.mjs';

const host = {id: 'host', email_mask: 'Host'};
const make = () => createCup('ABCDEFGH', host, {level: 'medium', surface: 'hard'}, 100);
function fullCup() {
  const cup = make();
  for (let i = 1; i <= 3; i++) joinCup(cup, {id: `friend${i}`, email_mask: `Friend ${i}`}, {});
  cup.participants.forEach(p => p.ready = true);
  startCup(cup, host.id, () => 0.8);
  return cup;
}
test('Invites use unambiguous eight-character codes and validate cup settings', () => {
  assert(validCode('ABCDEFGH')); assert(!validCode('ABCI1234')); assert(!validCode('../abcde'));
  assert.throws(() => createCup('ABCDEFGH', host, {level: 'pro', surface: 'hard'}), {status: 400});
  assert.equal(make().expiresAt, 86400100);
});
test('Joining is idempotent, caps the draw at four, and waits for friend readiness', () => {
  const cup = make();
  for (let i = 1; i <= 3; i++) joinCup(cup, {id: `friend${i}`}, {name: `Friend ${i}`});
  joinCup(cup, {id: 'friend1'}, {});
  assert.equal(cup.participants.length, 4);
  assert.throws(() => joinCup(cup, {id: 'extra'}, {}), {status: 409});
  assert.throws(() => startCup(cup, 'friend1'), {status: 403});
  assert.throws(() => startCup(cup, 'host'), {status: 409});
});
test('Empty slots get distinct labeled bots at the fixed cup level; bot matches are simulated', () => {
  const cup = make(); startCup(cup, 'host', () => 0.3);
  assert.equal(cup.participants.length, 4);
  assert.equal(new Set(cup.participants.map(p => p.id)).size, 4);
  assert(cup.participants.filter(p => p.kind === 'bot').every(p => p.name.includes('AI') && p.level === 'medium'));
  assert.equal(cup.matches.filter(m => m.reason === 'simulated').length, 1);
  assert(cup.matches.find(m => m.authorityID === 'host').playerIDs[0] === 'host');
  const before = JSON.stringify(cup); startCup(cup, 'host'); assert.equal(JSON.stringify(cup), before);
  assert.throws(() => joinCup(cup, {id: 'late'}, {}), {status: 409});
});
test('Semifinals advance their actual winners and only the final crowns a champion', () => {
  const cup = fullCup();
  const first = cup.matches[0], second = cup.matches[1];
  recordResult(cup, first.id, first.authorityID, [7, 4]);
  assert.equal(cup.matches.length, 2); assert.equal(cup.championID, null);
  recordResult(cup, second.id, second.authorityID, [6, 8]);
  const final = cup.matches[2];
  assert.deepEqual(new Set(final.playerIDs), new Set([first.winnerID, second.winnerID]));
  recordResult(cup, 'final', final.authorityID, [9, 11]);
  assert.equal(cup.status, 'complete'); assert.equal(cup.championID, final.playerIDs[1]);
});
test('Result retries cannot alter a completed match or advance twice', () => {
  const cup = fullCup(), game = cup.matches[0];
  assert.throws(() => recordResult(cup, game.id, 'outsider', [7, 0]), {status: 403});
  recordResult(cup, game.id, game.authorityID, [7, 5]);
  const before = JSON.stringify(cup);
  recordResult(cup, game.id, game.authorityID, [7, 5]); assert.equal(JSON.stringify(cup), before);
  assert.throws(() => recordResult(cup, game.id, game.authorityID, [0, 7]), {status: 409});
});
test('Tiebreak validation rejects unfinished, impossible and malformed scores', () => {
  for (const score of [[7, 0], [7, 5], [8, 6], [12, 10], [4, 7]]) assert(completedScore(score));
  for (const score of [[7, 6], [6, 0], [8, 0], [9, 6], [7, -1], [7.5, 0], [7, 0, 0], null]) assert(!completedScore(score));
});
test('Disconnect forfeits advance once and a withdrawn semifinal winner cannot strand the final', () => {
  const cup = fullCup(), first = cup.matches[0], second = cup.matches[1];
  recordResult(cup, first.id, first.authorityID, [7, 3]);
  cup.participants.find(p => p.id === first.winnerID).withdrawn = true;
  forfeitMatch(cup, second, second.playerIDs[0], 'disconnect');
  assert.equal(cup.status, 'complete'); assert.equal(cup.championID, second.playerIDs[1]);
  assert.equal(cup.matches[2].reason, 'forfeit');
  const before = JSON.stringify(cup); forfeitMatch(cup, second, second.playerIDs[0]); assert.equal(JSON.stringify(cup), before);
});
test('Public cup responses exclude full simulation checkpoints and private timing data', () => {
  const cup = fullCup(); cup.matches[0].snapshot = {private: 'large simulation'};
  cup.matches[0].missingSince = {host: 100}; cup.matches[0].lastSavedAt = 100;
  const game = publicCup(cup).matches[0];
  assert(!('snapshot' in game)); assert(!('missingSince' in game)); assert(!('lastSavedAt' in game));
});
test('Reconnect alarm awards a missing player a loss, while two missing players cancel the cup', async () => {
  for (const bothMissing of [false, true]) {
    const cup = fullCup(), game = cup.matches[0];
    cup.expiresAt = Date.now() + 86400000;
    game.status = 'live'; game.missingSince = {[game.playerIDs[0]]: Date.now() - 61000};
    if (bothMissing) game.missingSince[game.playerIDs[1]] = Date.now() - 61000;
    const peer = {readyState: 1, deserializeAttachment: () => ({userID: game.playerIDs[1], matchID: game.id}), send() {}, close() { this.readyState = 3; }};
    const ctx = {getWebSockets: () => bothMissing ? [] : [peer],
      storage: {get: async () => cup, put: async () => {}, setAlarm: async () => {}},
      blockConcurrencyWhile(fn) { this.pending = fn(); return this.pending; }};
    const room = new CupRoom(ctx, {}); await ctx.pending;
    await room.alarm();
    if (bothMissing) assert.equal(cup.status, 'cancelled');
    else { assert.equal(game.winnerID, game.playerIDs[1]); assert.equal(game.reason, 'disconnect'); }
  }
});
