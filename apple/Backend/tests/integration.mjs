// Exercises the real Worker and local D1. No authentication bypass is added to the API.
import assert from 'node:assert/strict';
import {randomUUID, randomBytes, createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const origin = new URL(process.env.LOCAL_WORKER_URL ?? 'http://127.0.0.1:8788/api/');
assert(['127.0.0.1', 'localhost', '[::1]'].includes(origin.hostname) && origin.protocol === 'http:',
  'Integration tests are restricted to a local HTTP Worker');
const wrapper = fileURLToPath(new URL('../wrangler.sh', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'swipetennis-api-test-'));
function sql(statement) {
  const path = join(directory, 'fixture.sql');
  writeFileSync(path, statement);
  execFileSync(wrapper, ['d1', 'execute', 'swipetennisdb', '--local', '--file', path], {stdio: 'pipe'});
}
const accounts = [0, 1].map(i => ({id: randomUUID(), token: randomBytes(32).toString('hex'), mask: `t${i}•••m` }));
async function api(path, {method = 'GET', body, token, status = 200} = {}) {
  const response = await fetch(new URL(path.replace(/^\//, ''), origin), {method,
    headers: {'Content-Type': 'application/json', ...(token ? {Authorization: `Bearer ${token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body)});
  const result = await response.json();
  assert.equal(response.status, status, `${path}: ${JSON.stringify(result)}`);
  return result;
}
function point(sessionID, index, negative = false) {
  return {id: randomUUID(), sessionID, pointIndex: index + 1, gameIndex: Math.floor(index / 4) + 1,
    winner: 0, format: 'tennis', gameCompleted: index % 4 === 3, setCompleted: index === 23,
    events: [{rule: 2, opportunity: 1, success: !negative},
      ...(!negative && index === 0 ? [{rule: 7, opportunity: 0, success: true}] : [])],
    points: 99999}; // A forged client total must be ignored.
}
try {
  assert.deepEqual(await api('/health'), {ok: true, rulesVersion: 2});
  await api('/points', {method: 'POST', body: {points: []}, status: 401});
  const challenge = await api('/auth/challenge', {method: 'POST'});
  assert.equal(challenge.nonce.length, 64);
  await api('/auth/apple', {method: 'POST', body: {challengeId: challenge.id, identityToken: 'forged'}, status: 401});
  sql(accounts.map(a => `INSERT INTO users VALUES('${a.id}','local-test-${a.id}','${a.mask}',${Date.now()});
    INSERT INTO auth_sessions VALUES('${createHash('sha256').update(a.token).digest('hex')}','${a.id}',${Date.now() + 600000});`).join('\n'));
  const token = accounts[0].token;
  assert.deepEqual(await api('/me', {token}), {userID: accounts[0].id, emailMask: accounts[0].mask});
  const session = randomUUID(), points = Array.from({length: 24}, (_, i) => point(session, i));
  const submit = records => api('/points', {method: 'POST', body: {points: records}, token});
  assert.equal((await submit(points.slice(0, 20))).accepted.length, 20);
  let board = await api('/leaderboard?metric=set');
  assert.equal(board.isDemo, false);
  assert(!board.entries.some(p => p.id === accounts[0].id), 'An unfinished set must not rank');
  assert.equal((await submit(points.slice(20))).accepted.length, 4);
  assert.equal((await submit(points)).accepted.length, 24, 'Retries must be idempotent');
  for (const [metric, expected] of [['point', 4], ['game', 10], ['set', 50]]) {
    board = await api(`/leaderboard?metric=${metric}`);
    assert.deepEqual(board.entries.find(p => p.id === accounts[0].id),
      {id: accounts[0].id, emailMask: accounts[0].mask, score: expected});
    assert(!JSON.stringify(board).includes('local-test-'), 'Apple subjects must remain private');
  }
  await api('/points', {method: 'POST', token: accounts[1].token, body: {points: [points[0]]}, status: 409});
  await api('/points', {method: 'POST', token, body: {points: [{...points[0], events: []}]}, status: 409});
  await api('/points', {method: 'POST', token, body: {points: [{...point(randomUUID(), 0), gameCompleted: true}]}, status: 409});
  await api('/points', {method: 'POST', token, body: {points: [{...point(randomUUID(), 0), events: [points[0].events[0], points[0].events[0]]}]}, status: 400});
  const lowerSession = randomUUID();
  await submit(Array.from({length: 24}, (_, i) => point(lowerSession, i, true)));
  for (const [metric, expected] of [['point', 4], ['game', 10], ['set', 50]]) {
    board = await api(`/leaderboard?metric=${metric}`);
    assert.equal(board.entries.find(p => p.id === accounts[0].id).score, expected, 'Personal best must be retained');
  }
  await api('/auth/logout', {method: 'POST', token: accounts[1].token});
  await api('/me', {token: accounts[1].token, status: 401});
  assert.deepEqual(await api('/me', {method: 'DELETE', token}), {deleted: true});
  await api('/me', {token, status: 401});
  board = await api('/leaderboard?metric=point');
  assert(!board.entries.some(p => p.id === accounts[0].id), 'Deleting the account must remove scores');
  sql(`DELETE FROM auth_challenges WHERE id='${challenge.id}';`);
  console.log('PASS: local Worker/D1 authentication rejection, nonce, privacy, tennis validation, idempotency, personal bests, account isolation, logout and cascade deletion.');
} finally {
  sql(`DELETE FROM users WHERE id IN (${accounts.map(a => `'${a.id}'`).join(',')});`);
  rmSync(directory, {recursive: true, force: true});
}
