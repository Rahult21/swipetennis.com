// Four-player cups. Only played human matches contribute to ST; never Coachability.
export const cupError = (status, message) => Object.assign(new Error(message), {status});
export const levels = ['easy', 'medium', 'hard'];
export const styles = ['baseline', 'aggressive', 'volley', 'allcourt', 'retriever'];
export const validCode = code => /^[A-HJ-NP-Z2-9]{8}$/.test(code);
export function displayName(value) {
  return String(value ?? '').normalize('NFKC').replace(/[\p{C}<>]/gu, '').trim().slice(0, 24) || 'Player';
}
export function division(points) {
  return points < 4 ? 'Challenger' : points < 7 ? 'Tour' : 'Masters';
}
export function createCup(code, user, data, now = Date.now()) {
  if (!levels.includes(data.level) || !['hard', 'clay', 'grass'].includes(data.surface)) {
    throw cupError(400, 'Choose a cup level and court surface.');
  }
  const size = [2, 8].includes(data.size) ? data.size : 4;
  return {code, size, adaptive: data.adaptive === true, division: division(user.stRating?.points ?? 4),
    divisionLocked: data.divisionLocked === true, restrictedTo: data.restrictedTo, eventWeek: data.eventWeek, title: displayName(data.title || 'Quick Cup'), hostID: user.id, status: 'lobby',
    level: data.level, surface: data.surface, createdAt: now, expiresAt: now + (size === 2 && data.divisionLocked ? 300000 : 86400000),
    participants: [{id: user.id, name: displayName(data.name || user.email_mask), kind: 'human', ready: true, stRating: user.stRating}],
    matches: [], championID: null, version: 1, rankingVersion: 1};
}
export function joinCup(cup, user, data) {
  if (cup.participants.some(p => p.id === user.id)) return;
  if (cup.status !== 'lobby') throw cupError(409, 'The draw has started. Ask your friend for a new cup.');
  if (cup.divisionLocked && division(user.stRating?.points ?? 4) !== cup.division) throw cupError(403, 'Choose an event in your ST division.');
  if (cup.restrictedTo && !cup.restrictedTo.includes(user.id)) throw cupError(403, 'This rematch is reserved for its players.');
  if (cup.participants.length >= (cup.size ?? 4)) throw cupError(409, 'The draw is full.');
  cup.participants.push({id: user.id, name: displayName(data.name || user.email_mask), kind: 'human', ready: false, stRating: user.stRating});
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
  if (cup.size === 2 && cup.participants.length !== 2) throw cupError(409, 'Waiting for your opponent.');
  if (cup.participants.some(p => !p.ready)) throw cupError(409, 'Wait for your friends to tap Ready.');
  const size = cup.size ?? 4;
  const humans = [...cup.participants];
  const names = ['Alex', 'Casey', 'Morgan', 'Jules', 'Kai', 'Sam', 'Riley'];
  while (cup.participants.length < size) {
    const index = cup.participants.length - 1;
    const target = humans[index % humans.length].stRating?.points ?? 4;
    const botST = cup.adaptive ? Math.max(1, Math.min(10, Math.round((target + random() * 0.6 - 0.3) * 10) / 10)) : undefined;
    cup.participants.push({botST, id: `bot-${cup.code}-${index}`, name: `${names[index]} · AI`, kind: 'bot',
      ready: true, level: botST == null ? cup.level : botST < 4 ? 'easy' : botST < 7 ? 'medium' : 'hard', style: styles[Math.floor(random() * styles.length)]});
  }
  const draw = [...cup.participants];
  for (let i = draw.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1)); [draw[i], draw[j]] = [draw[j], draw[i]];
  }
  if (size === 2) cup.expiresAt = Date.now() + 86400000;
  cup.status = 'playing';
  cup.matches = Array.from({length: size / 2}, (_, i) =>
    match(size === 2 ? 'final' : (size === 8 ? 'quarter-' : 'semi-') + (i + 1), draw.slice(2*i, 2*i+2)));
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
      const [left,right] = game.playerIDs.map(id => cup.participants.find(p => p.id === id));
      const probability = Math.max(0.1,Math.min(0.9,0.5 + ((left.botST ?? 4) - (right.botST ?? 4))/10));
      const score = [0,0];
      do { score[random() < probability ? 0 : 1]++; } while (!completedScore(score) && Math.max(...score) < 999);
      if (!completedScore(score)) score[score[0] > score[1] ? 0 : 1]++;
      game.score = score;
      const winner = score[0] > score[1] ? 0 : 1;
      game.winnerID = game.playerIDs[winner]; game.status = 'complete'; game.reason = 'simulated';
    }
  }
  const lastRound = cup.matches.filter(m => m.id.startsWith(cup.matches.some(m => m.id.startsWith('semi-')) ? 'semi-' : 'quarter-'));
  if (!cup.matches.some(m => m.id === 'final') && lastRound.length && lastRound.every(m => m.status === 'complete')) {
    const winners = lastRound.map(m => cup.participants.find(p => p.id === m.winnerID));
    for (let i = 0; i < winners.length; i += 2) {
      cup.matches.push(match(winners.length === 2 ? 'final' : 'semi-' + (1 + i/2), winners.slice(i,i+2)));
    }
    advanceCup(cup, random);
  }
  const final = cup.matches.find(m => m.id === 'final');
  if (final?.status === 'complete') { cup.status = 'complete'; cup.finishedAt ??= Date.now(); cup.championID = final.winnerID; }
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
  const {restrictedTo, ...visible} = cup;
  return {...visible, matches: cup.matches.map(({snapshot, lastSavedAt, missingSince, ...game}) => game)};
}
