import {completedScore} from './cup-rules.mjs';

export const tentativeMatches = 3;
export const ratingAlgorithm = 'score-share-v2';
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

// UTR-inspired performance scoring, not the official UTR formula: use the share
// of tiebreak POINTS won (not tennis games) against the expected share. A close
// loss to a stronger player can improve ST; an underperforming win can lower it.
// Read both ratings and apply both changes inside ONE D1 transaction. No read/modify
// race between simultaneous cups; an already-applied receipt changes neither player.
export async function settleSTMatch(db, cup, game) {
  if (!eligibleSTMatch(cup, game)) return [];
  const [a, b] = game.playerIDs, id = `${cup.code}:${game.id}`, winner = game.score[0] > game.score[1] ? 0 : 1;
  const total = game.score[0] + game.score[1];
  const shares = game.score.map(points => points / total);
  const after = (me, other, share) => `ROUND(MAX(1,MIN(10,${me}.points +
    CASE WHEN ${me}.human_matches < ${tentativeMatches} THEN 0.8 ELSE 0.4 END *
    (${share} - MAX(0.1,MIN(0.9,0.5 + (${me}.points-${other}.points)/10.0))))),2)`;
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO st_ratings(user_id) SELECT id FROM users WHERE id IN (?,?)').bind(a, b),
    db.prepare(`INSERT OR IGNORE INTO st_results
      (id,player0,player1,winner,score0,score1,before0,before1,after0,after1,matches0,matches1,created_at,applied,algorithm_version)
      SELECT ?,a.user_id,b.user_id,?,?,?,a.points,b.points,${after('a','b',shares[0])},
        ${after('b','a',shares[1])},a.human_matches,b.human_matches,?,0,2
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
  const threshold = row?.algorithm_version === 1 ? 5 : tentativeMatches;
  return row ? [0, 1].map(side => ({userID: game.playerIDs[side], before: row[`before${side}`],
    after: row[`after${side}`], humanMatches: row[`matches${side}`] + 1,
    beforeTentative: row[`matches${side}`] < threshold,
    tentative: row[`matches${side}`] + 1 < threshold, algorithmVersion: row.algorithm_version})) : [];
}
