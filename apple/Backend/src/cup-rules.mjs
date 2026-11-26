// Casual four-player cups. These results never contribute to Coachability or ranked ratings.
export const cupError = (status, message) => Object.assign(new Error(message), {status});
export const levels = ['easy', 'medium', 'hard'];
export const styles = ['baseline', 'aggressive', 'volley', 'allcourt', 'retriever'];
export const validCode = code => /^[A-HJ-NP-Z2-9]{8}$/.test(code);
export function displayName(value) {
  return String(value ?? '').normalize('NFKC').replace(/[\p{C}<>]/gu, '').trim().slice(0, 24) || 'Player';
}
export function createCup(code, user, data, now = Date.now()) {
  if (!levels.includes(data.level) || !['hard', 'clay', 'grass'].includes(data.surface)) {
    throw cupError(400, 'Choose a cup level and court surface.');
  }
  return {code, title: displayName(data.title || 'Quick Cup'), hostID: user.id, status: 'lobby',
    level: data.level, surface: data.surface, createdAt: now, expiresAt: now + 86400000,
    participants: [{id: user.id, name: displayName(data.name || user.email_mask), kind: 'human', ready: true}],
    matches: [], championID: null, version: 1};
}
export function joinCup(cup, user, data) {
  if (cup.participants.some(p => p.id === user.id)) return;
  if (cup.status !== 'lobby') throw cupError(409, 'The draw has started. Ask your friend for a new cup.');
  if (cup.participants.length === 4) throw cupError(409, 'This cup already has four players.');
  cup.participants.push({id: user.id, name: displayName(data.name || user.email_mask), kind: 'human', ready: false});
}
function match(id, players) {
  // The first human runs the native simulation. A bot is always on its far side.
  if (players[0].kind === 'bot' && players[1].kind === 'human') players.reverse();
  return {id, playerIDs: players.map(p => p.id), authorityID: players.find(p => p.kind === 'human')?.id ?? null,
    status: 'waiting', score: [0, 0], winnerID: null, reason: null, startedAt: null};
}
export function startCup(cup, userID, random = Math.random) {
  if (cup.hostID !== userID) throw cupError(403, 'Only the host can start the cup.');
  if (cup.status !== 'lobby') return; // Safe to retry a start whose response was lost.
  if (cup.participants.some(p => !p.ready)) throw cupError(409, 'Wait for your friends to tap Ready.');
  const names = ['Alex', 'Casey', 'Morgan'];
  while (cup.participants.length < 4) {
    const index = cup.participants.length - 1;
    cup.participants.push({id: `bot-${cup.code}-${index}`, name: `${names[index]} · AI`, kind: 'bot',
      ready: true, level: cup.level, style: styles[Math.floor(random() * styles.length)]});
  }
  const draw = [...cup.participants];
  for (let i = draw.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1)); [draw[i], draw[j]] = [draw[j], draw[i]];
  }
  cup.status = 'playing';
  cup.matches = [match('semi-1', draw.slice(0, 2)), match('semi-2', draw.slice(2, 4))];
  advanceCup(cup, random);
}
export function advanceCup(cup, random = Math.random) {
  for (const game of cup.matches) {
    if (game.status === 'waiting') {
      const withdrawn = game.playerIDs.filter(id => cup.participants.find(p => p.id === id)?.withdrawn);
      if (withdrawn.length === 2) { cup.status = 'cancelled'; return; }
      if (withdrawn.length === 1) {
        game.winnerID = game.playerIDs.find(id => id !== withdrawn[0]); game.status = 'complete'; game.reason = 'forfeit';
      }
    }
    if (!game.authorityID && game.status === 'waiting') {
      const winner = random() < 0.5 ? 0 : 1, loserPoints = Math.floor(random() * 7);
      game.score = loserPoints === 6 ? [8, 6] : [7, loserPoints];
      if (winner === 1) game.score.reverse();
      game.winnerID = game.playerIDs[winner]; game.status = 'complete'; game.reason = 'simulated';
    }
  }
  if (cup.matches.length === 2 && cup.matches.every(m => m.status === 'complete')) {
    cup.matches.push(match('final', cup.matches.map(m => cup.participants.find(p => p.id === m.winnerID))));
    advanceCup(cup, random);
  }
  const final = cup.matches.find(m => m.id === 'final');
  if (final?.status === 'complete') { cup.status = 'complete'; cup.championID = final.winnerID; }
}
export function completedScore(score) {
  if (!Array.isArray(score) || score.length !== 2 || !score.every(n => Number.isSafeInteger(n) && n >= 0 && n <= 1000)) return false;
  const high = Math.max(...score), low = Math.min(...score);
  return high >= 7 && (high === 7 ? low <= 5 : high - low === 2);
}
export function recordResult(cup, matchID, userID, score) {
  const game = cup.matches.find(m => m.id === matchID);
  if (!game || game.authorityID !== userID) throw cupError(403, 'Only this match can report its result.');
  if (!completedScore(score)) throw cupError(400, 'A tiebreak ends at seven points, winning by two.');
  if (game.status === 'complete') {
    if (game.reason === 'played' && JSON.stringify(game.score) === JSON.stringify(score)) return;
    throw cupError(409, 'This match already has a result.');
  }
  if (cup.status !== 'playing') throw cupError(409, 'This cup is not in progress.');
  game.score = score; game.winnerID = game.playerIDs[score[0] > score[1] ? 0 : 1];
  game.status = 'complete'; game.reason = 'played'; delete game.snapshot;
  advanceCup(cup);
}
export function forfeitMatch(cup, game, userID, reason = 'forfeit') {
  if (game.status === 'complete' || !game.playerIDs.includes(userID)) return;
  game.winnerID = game.playerIDs.find(id => id !== userID); game.status = 'complete'; game.reason = reason;
  delete game.snapshot; advanceCup(cup);
}
export function publicCup(cup) {
  return {...cup, matches: cup.matches.map(({snapshot, lastSavedAt, missingSince, ...game}) => game)};
}
