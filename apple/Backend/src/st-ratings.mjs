import {completedScore} from './cup-rules.mjs';

export const tentativeMatches = 5;
export function publicRating(row) {
  return {points: row?.points ?? 4, humanMatches: row?.human_matches ?? 0,
    wins: row?.wins ?? 0, tentative: (row?.human_matches ?? 0) < tentativeMatches};
}
export async function ratingFor(db, userID) {
  await db.prepare('INSERT OR IGNORE INTO st_ratings(user_id) SELECT id FROM users WHERE id=?').bind(userID).run();
  return publicRating(await db.prepare('SELECT * FROM st_ratings WHERE user_id=?').bind(userID).first());
}
export function eligibleSTMatch(cup, game) {
  return cup.rankingVersion === 1 && game.ratedPlayStarted === true && game.status === 'complete' && game.reason === 'played'
    && completedScore(game.score) && game.playerIDs.length === 2 && game.playerIDs[0] !== game.playerIDs[1]
    && game.playerIDs.every(id => cup.participants.some(p => p.id === id && p.kind === 'human'));
}

// Opponent-weighted updates: equal players gain/lose 0.4 while tentative, then 0.2.
// Read both ratings and apply both changes inside ONE D1 transaction. No read/modify
// race between simultaneous cups; an already-applied receipt changes neither player.
export async function settleSTMatch(db, cup, game) {
  if (!eligibleSTMatch(cup, game)) return [];
  const [a, b] = game.playerIDs, id = `${cup.code}:${game.id}`, winner = game.score[0] > game.score[1] ? 0 : 1;
  const after = (me, other, won) => `ROUND(MAX(1,MIN(10,${me}.points +
    CASE WHEN ${me}.human_matches < ${tentativeMatches} THEN 0.8 ELSE 0.4 END *
    (${won} - MAX(0.1,MIN(0.9,0.5 + (${me}.points-${other}.points)/10.0))))),2)`;
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO st_ratings(user_id) SELECT id FROM users WHERE id IN (?,?)').bind(a, b),
    db.prepare(`INSERT OR IGNORE INTO st_results
      SELECT ?,a.user_id,b.user_id,?,?,?,a.points,b.points,${after('a','b',winner === 0 ? 1 : 0)},
        ${after('b','a',winner === 1 ? 1 : 0)},a.human_matches,b.human_matches,?,0
      FROM st_ratings a JOIN st_ratings b ON b.user_id=? WHERE a.user_id=?`)
      .bind(id, winner, ...game.score, Date.now(), b, a),
    ...[0, 1].map(side => db.prepare(`UPDATE st_ratings SET
      points=(SELECT after${side} FROM st_results WHERE id=?),human_matches=human_matches+1,
      wins=wins+(SELECT CASE WHEN winner=${side} THEN 1 ELSE 0 END FROM st_results WHERE id=?)
      WHERE user_id=? AND EXISTS(SELECT 1 FROM st_results WHERE id=? AND applied=0)`)
      .bind(id, id, game.playerIDs[side], id)),
    db.prepare('UPDATE st_results SET applied=1 WHERE id=?').bind(id)
  ]);
  const row = await db.prepare('SELECT * FROM st_results WHERE id=?').bind(id).first();
  return row ? [0, 1].map(side => ({userID: game.playerIDs[side], before: row[`before${side}`],
    after: row[`after${side}`], humanMatches: row[`matches${side}`] + 1,
    tentative: row[`matches${side}`] + 1 < tentativeMatches})) : [];
}
