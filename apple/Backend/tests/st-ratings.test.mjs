import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync, readdirSync} from 'node:fs';
import {ratingFor, settleSTMatch} from '../src/st-ratings.mjs';

function fixture() {
  const sql = new DatabaseSync(':memory:');
  sql.exec('PRAGMA foreign_keys=ON');
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of readdirSync(migrations).sort()) sql.exec(readFileSync(new URL(file, migrations), 'utf8'));
  sql.exec("INSERT INTO users VALUES('a','apple-a','Alice',1),('b','apple-b','Bob',1),('c','apple-c','Chris',1)");
  const db = {
    prepare(query) {
      let values = [];
      const statement = {bind(...args) { values = args; return statement; },
        run() { return sql.prepare(query).run(...values); }, first() { return sql.prepare(query).get(...values); }};
      return statement;
    },
    async batch(statements) {
      sql.exec('BEGIN');
      try { const results = statements.map(s => s.run()); sql.exec('COMMIT'); return results; }
      catch (error) { sql.exec('ROLLBACK'); throw error; }
    }
  };
  const cup = {code: 'ABCDEFGH', rankingVersion: 1, participants: ['a', 'b', 'c'].map(id => ({id, kind: 'human'}))};
  const game = {id: 'semi-1', playerIDs: ['a','b'], status: 'complete', reason: 'played', score: [7,5], ratedPlayStarted: true};
  return {sql, db, cup, game};
}

test('new players start at 4t, human results update both and retries are exactly once', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    assert.deepEqual(await ratingFor(db, 'a'), {points: 4, humanMatches: 0, wins: 0, tentative: true});
    const changes = await settleSTMatch(db, cup, game);
    assert.deepEqual(changes.map(c => c.after), [4.4, 3.6]);
    await settleSTMatch(db, cup, game);
    assert.deepEqual(await ratingFor(db, 'a'), {points: 4.4, humanMatches: 1, wins: 1, tentative: true});
    assert.deepEqual(await ratingFor(db, 'b'), {points: 3.6, humanMatches: 1, wins: 0, tentative: true});
  } finally { sql.close(); }
});
test('bots, forfeits, disconnects, unfinished games, old cups and unready humans never change ST', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    for (const reason of ['forfeit','disconnect','simulated']) assert.deepEqual(await settleSTMatch(db, cup, {...game, reason}), []);
    for (const patch of [{status: 'live'}, {score: [6,5]}, {ratedPlayStarted: false}, {playerIDs: ['a','a']}]) {
      assert.deepEqual(await settleSTMatch(db, cup, {...game, ...patch}), []);
    }
    assert.deepEqual(await settleSTMatch(db, {...cup, rankingVersion: undefined}, game), []);
    assert.deepEqual(await settleSTMatch(db, {...cup, participants: [{id:'a',kind:'human'},{id:'b',kind:'bot'}]}, game), []);
    assert.equal((await ratingFor(db, 'a')).humanMatches, 0);
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM st_results').get().n, 0);
  } finally { sql.close(); }
});
test('tentative ends after five human matches, points are bounded and stronger opponents reward more', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    for (let i=0;i<5;i++) await settleSTMatch(db, {...cup,code:`CUP${i}`}, game);
    assert.equal((await ratingFor(db, 'a')).tentative, false);
    assert.equal((await ratingFor(db, 'b')).tentative, false);
    sql.exec("UPDATE st_ratings SET points=CASE user_id WHEN 'a' THEN 1 ELSE 10 END");
    const upset = await settleSTMatch(db, {...cup,code:'UPSET'}, game);
    assert(upset[0].after - upset[0].before > 0.2);
    sql.exec("UPDATE st_ratings SET points=CASE user_id WHEN 'a' THEN 10 ELSE 1 END");
    const bounded = await settleSTMatch(db, {...cup,code:'BOUND'}, game);
    assert.deepEqual(bounded.map(c=>c.after), [10,1]);
  } finally { sql.close(); }
});
test('simultaneous cups use latest ratings without lost updates and old receipt retries cannot rewind them', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    await Promise.all([settleSTMatch(db, cup, game), settleSTMatch(db, {...cup,code:'SECOND'}, {...game,playerIDs:['a','c']})]);
    const current = await ratingFor(db, 'a');
    assert.equal(current.humanMatches, 2);
    assert(current.points > 4.4);
    await settleSTMatch(db, cup, game);
    assert.deepEqual(await ratingFor(db, 'a'), current);
    sql.exec("DELETE FROM users WHERE id='a'");
    assert.equal(sql.prepare("SELECT COUNT(*) n FROM st_ratings WHERE user_id='a'").get().n, 0);
    assert.deepEqual(await settleSTMatch(db, cup, game), []);
    assert.equal((await ratingFor(db, 'b')).humanMatches, 1);
  } finally { sql.close(); }
});
