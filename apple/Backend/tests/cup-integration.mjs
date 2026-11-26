// Real local Worker + Durable Objects + D1 + WebSockets. Never writes to production.
import assert from 'node:assert/strict';
import {randomUUID, randomBytes, createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import WebSocket from 'ws';

const origin = new URL(process.env.LOCAL_WORKER_URL ?? 'http://127.0.0.1:8788/api/');
assert(['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname) && origin.protocol === 'http:', 'Local tests only');
const wrapper = fileURLToPath(new URL('../wrangler.sh', import.meta.url));
const directory = mkdtempSync(join(tmpdir(), 'swipetennis-cup-test-'));
const accounts = Array.from({length: 5}, (_, i) => ({id: randomUUID(), token: randomBytes(32).toString('hex'), name: `Cup test ${i}`}));
const sockets = [];
function sql(statement) {
  const path = join(directory, 'fixture.sql'); writeFileSync(path, statement);
  execFileSync(wrapper, ['d1', 'execute', 'swipetennisdb', '--local', '--file', path], {stdio: 'pipe', env: {...process.env, WRANGLER_SEND_METRICS: 'false'}});
}
async function api(path, account = accounts[0], body, status = 200, method = body === undefined ? 'GET' : 'POST') {
  const response = await fetch(new URL(path, origin), {method, headers: {'Content-Type': 'application/json', ...(account ? {Authorization: `Bearer ${account.token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body)});
  const result = await response.json(); assert.equal(response.status, status, JSON.stringify(result)); return result;
}
async function connect(cup, match, account) {
  const url = new URL(`cups/${cup.code}/matches/${match.id}/socket`, origin); url.protocol = 'ws:';
  const ws = new WebSocket(url, {headers: {Authorization: `Bearer ${account.token}`}});
  const queue = [], waiting = [];
  ws.on('message', data => {
    const value = JSON.parse(data.toString());
    const i = waiting.findIndex(w => w.test(value));
    if (i >= 0) { const [waiter] = waiting.splice(i, 1); clearTimeout(waiter.timer); waiter.resolve(value); }
    else queue.push(value);
  });
  const receive = (type, predicate = () => true) => new Promise((resolve, reject) => {
    const test = value => value.type === type && predicate(value), index = queue.findIndex(test);
    if (index >= 0) { resolve(queue.splice(index, 1)[0]); return; }
    const waiter = {test, resolve, timer: setTimeout(() => reject(new Error(`Timed out waiting for ${type}: ${JSON.stringify(queue)}`)), 8000)};
    waiting.push(waiter);
  });
  await new Promise((resolve, reject) => { ws.once('open', resolve); ws.once('error', reject); ws.once('unexpected-response', (_, response) => reject(new Error(`Upgrade rejected: ${response.statusCode}`))); });
  const client = {ws, receive, send: value => ws.send(JSON.stringify(value)), account}; sockets.push(client);
  client.welcome = await receive('welcome'); return client;
}
function state(score, local, phase = 'point') {
  return {players: [{pos: {x: 4, y: 24}}, {pos: {x: 4, y: 0}}], settings: {tournament: true, local},
    scoring: {format: 'Tiebreak', points: score}, phase};
}
async function play(cup, match) {
  const players = match.playerIDs.map(id => accounts.find(a => a.id === id)).filter(Boolean);
  const clients = [];
  for (const account of players) clients.push(await connect(cup, match, account));
  for (const client of clients) await client.receive('presence', value => value.ready);
  const host = clients.find(c => c.account.id === match.authorityID), guest = clients.find(c => c !== host);
  host.send({type: 'snapshot', snapshot: state([0, 0], clients.length === 2, 'ready')});
  if (guest) {
    await guest.receive('snapshot');
    guest.send({type: 'snapshot', snapshot: state([7, 0], true, 'finished')});
    assert.match((await guest.receive('error')).message, /host/);
    guest.send({type: 'input', side: 0, input: {kind: 'tap', point: {x: 4, y: 0}}});
    const input = await host.receive('input'); assert.equal(input.side, 1); assert.equal(input.input.kind, 'tap');
  }
  for (const client of clients) client.send({type: 'next', point: 0});
  for (const client of clients) await client.receive('advance');
  for (let score = 1; score <= 7; score++) {
    host.send({type: 'snapshot', snapshot: state([score, 0], clients.length === 2, score === 7 ? 'finished' : 'point')});
    if (guest) await guest.receive('snapshot', message => message.snapshot.scoring.points[0] === score);
    // Every point is checkpointed, including the one used for reconnection.
    if (score === 3 && guest) {
      guest.ws.close();
      const presence = await host.receive('presence', value => !value.ready);
      assert(presence.deadline > Date.now());
      const replacement = await connect(cup, match, guest.account);
      assert.deepEqual(replacement.welcome.snapshot.scoring.points, [3, 0]);
      await host.receive('presence', value => value.ready);
      guest.ws = replacement.ws; guest.receive = replacement.receive; guest.send = replacement.send;
    }
  }
  const result = (await host.receive('cup', value => value.cup.matches.find(m => m.id === match.id)?.status === 'complete')).cup;
  for (const client of clients) client.ws.close();
  return result;
}

try {
  sql(accounts.map(a => `INSERT INTO users VALUES('${a.id}','cup-test-${a.id}','${a.name}',${Date.now()});
    INSERT INTO auth_sessions VALUES('${createHash('sha256').update(a.token).digest('hex')}','${a.id}',${Date.now() + 600000});`).join('\n'));
  await api('cups', null, undefined, 401);
  const requestID = randomUUID();
  let cup = await api('cups', accounts[0], {requestID, title: 'Local Cup', level: 'medium', surface: 'hard'});
  assert.equal((await api('cups', accounts[0], {requestID, level: 'medium', surface: 'hard'})).code, cup.code, 'Create retries reuse the cup');
  await api(`cups/${cup.code}`, accounts[1], undefined, 403);
  await api(`cups/${cup.code}/delete-account`, accounts[0], undefined, 404);
  for (const account of accounts.slice(1, 4)) await api(`cups/${cup.code}/join`, account, {name: account.name});
  await api(`cups/${cup.code}/join`, accounts[4], {}, 409);
  await api(`cups/${cup.code}/start`, accounts[1], {}, 403);
  await api(`cups/${cup.code}/start`, accounts[0], {}, 409);
  for (const account of accounts.slice(1, 4)) await api(`cups/${cup.code}/ready`, account, {ready: true});
  cup = await api(`cups/${cup.code}/start`, accounts[0], {});
  assert.equal(cup.matches.length, 2); assert.equal(cup.participants.filter(p => p.kind === 'bot').length, 0);
  for (const match of [...cup.matches]) cup = await play(cup, match);
  assert.equal(cup.matches.length, 3);
  cup = await play(cup, cup.matches[2]); assert.equal(cup.status, 'complete'); assert(cup.championID);
  assert((await api('cups')).cups.some(item => item.code === cup.code));
  assert.equal((await api('cups', accounts[4])).cups.length, 0);
  let solo = await api('cups', accounts[0], {requestID: randomUUID(), title: 'Bot Cup', level: 'hard', surface: 'clay'});
  solo = await api(`cups/${solo.code}/start`, accounts[0], {});
  assert.equal(solo.participants.filter(p => p.kind === 'bot' && p.level === 'hard').length, 3);
  solo = await play(solo, solo.matches.find(m => m.authorityID === accounts[0].id));
  solo = await play(solo, solo.matches.find(m => m.id === 'final'));
  assert.equal(solo.championID, accounts[0].id);
  await api('me', accounts[0], undefined, 200, 'DELETE');
  const anonymized = await api(`cups/${cup.code}`, accounts[1]);
  assert.equal(anonymized.participants.find(p => p.id === accounts[0].id).name, 'Deleted player');
  console.log('PASS: local four-human and mixed cups, invite authorization, readiness, capacity, fixed bot level, live input relay, snapshot ownership, reconnect checkpoints, semifinals/finals, result persistence and account deletion.');
} finally {
  for (const client of sockets) client.ws.terminate();
  for (const account of accounts.slice(1)) await api('me', account, undefined, 200, 'DELETE').catch(() => {});
  sql(`DELETE FROM users WHERE id IN (${accounts.map(a => `'${a.id}'`).join(',')});`);
  rmSync(directory, {recursive: true, force: true});
}
