import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID, webcrypto} from 'node:crypto';
import {maskEmail, publicPlayerName, validatePoint, validateSequence, demoEntries} from '../src/rules.mjs';
import {verifyAppleToken} from '../src/apple-auth.mjs';

const point = (index = 1, changes = {}) => ({id: randomUUID(), sessionID: '160a41d6-2e93-4f19-9711-3b603621e858',
  pointIndex: index, gameIndex: 1, format: 'tennis', winner: 0, events: [],
  gameCompleted: false, setCompleted: false, ...changes});

test('Player names expose at most the first five username characters, excluding the domain', () => {
  assert.equal(maskEmail('rahul@example.com'), 'rahul');
  assert.equal(maskEmail('ab123456@privaterelay.appleid.com'), 'ab123');
  assert.equal(maskEmail('a@b'), 'a');
  assert.equal(maskEmail('ab@example.org'), 'ab');
  assert.equal(maskEmail('  élise@different.net  '), 'élise');
  assert.equal(maskEmail('invalid'), '•••');
  assert.equal(publicPlayerName('ra•••l'), 'ra');
  assert.equal(publicPlayerName('rahul'), 'rahul');
  assert.equal(publicPlayerName('•••'), 'Player');
});
test('Recovery consistency awards once per point and can stack with other rules', () => {
  const recovery = {rule: 7, opportunity: 0, success: true};
  assert.equal(validatePoint(point(1, {events: [recovery]})).cp, 2);
  assert.equal(validatePoint(point(1, {events: [{...recovery, success: false}]})).cp, -1);
  assert.equal(validatePoint(point(1, {events: [recovery, {rule: 3, opportunity: 1, success: true}]})).cp, 4);
  assert.throws(() => validatePoint(point(1, {events: [recovery, recovery]})));
  assert.throws(() => validatePoint(point(1, {events: [{...recovery, opportunity: 1}]})));
  assert.throws(() => validatePoint(point(1, {events: [{rule: 8, opportunity: 0, success: true}]})));
});
test('Scores are recomputed and multiple opportunities can stack without duplicate credit', () => {
  const events = [{rule: 1, opportunity: 3, success: true}, {rule: 6, opportunity: 3, success: true},
    {rule: 2, opportunity: 5, success: false}, {rule: 1, opportunity: 7, success: true}];
  assert.equal(validatePoint(point(1, {events, cp: 100000})).cp, 5);
  assert.throws(() => validatePoint(point(1, {events: [...events, events[0]]})));
  assert.throws(() => validatePoint(point(1, {events: [{rule: 7, opportunity: 3, success: true}]})));
  assert.throws(() => validatePoint(point(1, {events: [{rule: 1, opportunity: 3, success: 2}]})));
});
test('Only complete, correctly ordered games and sets can establish those records', () => {
  const points = Array.from({length: 24}, (_, i) => validatePoint(point(i + 1, {
    gameIndex: Math.floor(i / 4) + 1, gameCompleted: i % 4 === 3, setCompleted: i === 23})));
  assert.doesNotThrow(() => validateSequence(points));
  assert.throws(() => validateSequence([validatePoint(point(1, {gameCompleted: true}))]));
  assert.throws(() => validateSequence([points[1]]));
  assert.throws(() => validateSequence([...points, validatePoint(point(25, {gameIndex: 7}))]));
});
test('Tiebreak points never become a full-game or full-set record', () => {
  const points = Array.from({length: 7}, (_, i) => validatePoint(point(i + 1, {format: 'tiebreak'})));
  assert.doesNotThrow(() => validateSequence(points));
  assert.throws(() => validateSequence([...points, validatePoint(point(8, {format: 'tiebreak'}))]));
});
test('Demo boards contain ten labeled fixtures in the requested ranges', () => {
  for (const [metric, min, max] of [['point',1,4],['game',6,10],['set',21,31]]) {
    const rows = demoEntries(metric);
    assert.equal(rows.length, 10); assert.equal(rows[0].score, max); assert.equal(rows.at(-1).score, min);
    assert.ok(rows.every(r => r.id.startsWith('example-') && r.emailMask.length === 5));
  }
});

const pair = await webcrypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5', modulusLength:2048,
  publicExponent:new Uint8Array([1,0,1]), hash:'SHA-256'}, true, ['sign','verify']);
const jwk = {...await webcrypto.subtle.exportKey('jwk', pair.publicKey), kid:'test'};
const claims = {iss:'https://appleid.apple.com', aud:'com.swipetennis.app', sub:'fixture-apple-sub',
  iat:1000, exp:2000, nonce:'fixture-nonce', email:'fixture@example.com', email_verified:'true'};
async function token(changes = {}, headerChanges = {}) {
  const b64 = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const input = b64({alg:'RS256', kid:'test', ...headerChanges})+'.'+b64({...claims,...changes});
  const signature = await webcrypto.subtle.sign('RSASSA-PKCS1-v1_5', pair.privateKey, Buffer.from(input));
  return input+'.'+Buffer.from(signature).toString('base64url');
}
const opts = {audience:'com.swipetennis.app', nonce:'fixture-nonce', now:1100, keys:[jwk]};
test('Apple subject is accepted only with a valid signature and bound challenge', async () => {
  assert.equal((await verifyAppleToken(await token(), opts)).sub, claims.sub);
  for (const changes of [{iss:'https://attacker.example'}, {aud:'other-app'}, {nonce:'wrong'},
    {exp:1099}, {iat:2000}, {iat:1}, {email_verified:false}, {sub:''}]) {
    await assert.rejects(verifyAppleToken(await token(changes), opts));
  }
  await assert.rejects(verifyAppleToken(await token({}, {alg:'none'}), opts));
  const valid = await token();
  const parts = valid.split('.'); parts[1] = Buffer.from(JSON.stringify({...claims, sub:'forged'})).toString('base64url');
  await assert.rejects(verifyAppleToken(parts.join('.'), opts));
});
