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
    assert.deepEqual(changes.map(c => c.after), [4.07, 3.93]);
    await settleSTMatch(db, cup, game);
    assert.deepEqual(await ratingFor(db, 'a'), {points: 4.07, humanMatches: 1, wins: 1, tentative: true});
    assert.deepEqual(await ratingFor(db, 'b'), {points: 3.93, humanMatches: 1, wins: 0, tentative: true});
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
test('tentative ends after three human matches, points are bounded and stronger opponents reward more', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    for (let i=0;i<3;i++) {
      const changes = await settleSTMatch(db, {...cup,code:`CUP${i}`}, game);
      assert(changes.every(c => c.beforeTentative && c.tentative === (i < 2)));
      assert.equal((await ratingFor(db, 'a')).tentative, i < 2);
    }
    assert.equal((await ratingFor(db, 'a')).tentative, false);
    assert.equal((await ratingFor(db, 'b')).tentative, false);
    sql.exec("UPDATE st_ratings SET points=CASE user_id WHEN 'a' THEN 1 ELSE 10 END");
    const upset = await settleSTMatch(db, {...cup,code:'UPSET'}, game);
    assert(upset[0].after - upset[0].before > 0.1);
    sql.exec("UPDATE st_ratings SET points=CASE user_id WHEN 'a' THEN 10 ELSE 1 END");
    const bounded = await settleSTMatch(db, {...cup,code:'BOUND'}, {...game,score:[7,0]});
    assert.deepEqual(bounded.map(c=>c.after), [10,1]);
  } finally { sql.close(); }
});

test('point margin rewards 7–1 more than 7–5, with smaller changes after establishment', async () => {
  for (const [matches, score, expected] of [[0,[7,1],[4.30,3.70]], [0,[7,5],[4.07,3.93]],
    [3,[7,1],[4.15,3.85]], [3,[7,5],[4.03,3.97]], [0,[1,7],[3.70,4.30]]]) {
    const {sql, db, cup, game} = fixture();
    try {
      await ratingFor(db,'a'); await ratingFor(db,'b');
      sql.prepare('UPDATE st_ratings SET human_matches=?').run(matches);
      const changes = await settleSTMatch(db,cup,{...game,score});
      assert.deepEqual(changes.map(c=>c.after),expected);
      assert(changes.every(c=>c.algorithmVersion === 2));
    } finally { sql.close(); }
  }
});
test('a close loss to a stronger human can raise ST while the weaker-than-expected winner drops', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    await ratingFor(db,'a'); await ratingFor(db,'b');
    sql.exec("UPDATE st_ratings SET points=6 WHERE user_id='b'");
    const changes = await settleSTMatch(db,cup,{...game,score:[5,7]});
    assert.deepEqual(changes.map(c=>c.after),[4.09,5.91]);
    assert.equal((await ratingFor(db,'a')).wins,0);
    assert.equal((await ratingFor(db,'b')).wins,1);
  } finally { sql.close(); }
});
test('extended tiebreaks use point share rather than counting extra points as extra wins', async () => {
  const results = [];
  for (const score of [[8,6],[20,18],[7,0]]) {
    const {sql,db,cup,game} = fixture();
    try { results.push((await settleSTMatch(db,cup,{...game,score}))[0].after); }
    finally { sql.close(); }
  }
  assert.deepEqual(results,[4.06,4.02,4.4]);
});
test('existing version-1 receipts retain their changes and labels when retried under the new policy', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    await ratingFor(db,'a'); await ratingFor(db,'b');
    sql.exec("UPDATE st_ratings SET points=4.4,human_matches=4,wins=1 WHERE user_id='a'; UPDATE st_ratings SET points=3.6,human_matches=4 WHERE user_id='b'");
    sql.exec("INSERT INTO st_results(id,player0,player1,winner,score0,score1,before0,before1,after0,after1,matches0,matches1,created_at,applied) VALUES('ABCDEFGH:semi-1','a','b',0,7,5,4,4,4.4,3.6,3,3,1,1)");
    const changes = await settleSTMatch(db,cup,game);
    assert.deepEqual(changes.map(c=>c.after),[4.4,3.6]);
    assert(changes.every(c=>c.beforeTentative && c.tentative && c.algorithmVersion === 1));
    assert.deepEqual(await ratingFor(db,'a'),{points:4.4,humanMatches:4,wins:1,tentative:false});
  } finally { sql.close(); }
});
test('simultaneous cups use latest ratings without lost updates and old receipt retries cannot rewind them', async () => {
  const {sql, db, cup, game} = fixture();
  try {
    await Promise.all([settleSTMatch(db, cup, game), settleSTMatch(db, {...cup,code:'SECOND'}, {...game,playerIDs:['a','c']})]);
    const current = await ratingFor(db, 'a');
    assert.equal(current.humanMatches, 2);
    assert(current.points > 4.07);
    await settleSTMatch(db, cup, game);
    assert.deepEqual(await ratingFor(db, 'a'), current);
    sql.exec("DELETE FROM users WHERE id='a'");
    assert.equal(sql.prepare("SELECT COUNT(*) n FROM st_ratings WHERE user_id='a'").get().n, 0);
    assert.deepEqual(await settleSTMatch(db, cup, game), []);
    assert.equal((await ratingFor(db, 'b')).humanMatches, 1);
  } finally { sql.close(); }
});
