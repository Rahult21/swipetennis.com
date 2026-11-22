export function maskEmail(email) {
  const chars = Array.from(String(email ?? '').trim());
  return chars.length >= 5 && chars.includes('@') ? chars.slice(0, 2).join('') + '•••' + chars.at(-1) : '•••';
}

export function validatePoint(value) {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!value || !uuid.test(value.id) || !uuid.test(value.sessionID)
    || !Number.isInteger(value.pointIndex) || value.pointIndex < 1 || value.pointIndex > 10000
    || !Number.isInteger(value.gameIndex) || value.gameIndex < 1 || value.gameIndex > 2500
    || ![0, 1].includes(value.winner) || !['tennis', 'tiebreak'].includes(value.format)
    || typeof value.gameCompleted !== 'boolean' || typeof value.setCompleted !== 'boolean'
    || !Array.isArray(value.events) || value.events.length > 128) throw new Error('Invalid point');
  const seen = new Set();
  const events = value.events.map(event => {
    if (!Number.isInteger(event.rule) || event.rule < 1 || event.rule > 6
      || !Number.isInteger(event.opportunity) || event.opportunity < 0 || event.opportunity > 1000000
      || typeof event.success !== 'boolean') throw new Error('Invalid coaching event');
    const id = `${event.rule}:${event.opportunity}`;
    if (seen.has(id)) throw new Error('Duplicate coaching opportunity');
    seen.add(id);
    return {rule: event.rule, opportunity: event.opportunity, success: event.success};
  }).sort((a, b) => a.opportunity - b.opportunity || a.rule - b.rule);
  return {id: value.id.toLowerCase(), sessionID: value.sessionID.toLowerCase(),
    pointIndex: value.pointIndex, gameIndex: value.gameIndex, winner: value.winner,
    format: value.format, gameCompleted: value.gameCompleted, setCompleted: value.setCompleted,
    events, cp: events.reduce((sum, event) => sum + (event.success ? 2 : -1), 0)};
}

export function validateSequence(points) {
  const score = [0, 0], games = [0, 0];
  let gameIndex = 1, complete = false;
  for (let index = 0; index < points.length; index++) {
    const p = points[index];
    if (complete || p.pointIndex !== index + 1 || p.gameIndex !== gameIndex || p.format !== points[0].format)
      throw new Error('Points must follow the match sequence');
    score[p.winner]++;
    let gameComplete = false, setComplete = false;
    if (p.format === 'tiebreak') {
      complete = score[p.winner] >= 7 && score[p.winner] - score[1 - p.winner] >= 2;
    } else if (score[p.winner] >= 4 && score[p.winner] - score[1 - p.winner] >= 2) {
      gameComplete = true; games[p.winner]++; score[0] = 0; score[1] = 0; gameIndex++;
      setComplete = games[p.winner] >= 6 && games[p.winner] - games[1 - p.winner] >= 2;
      complete = setComplete;
    }
    if (p.gameCompleted !== gameComplete || p.setCompleted !== setComplete) throw new Error('Incomplete game or set');
  }
}

export const DEMO_NAMES = ['al•••m','be•••m','ca•••m','di•••m','el•••m','fi•••m','gi•••m','ha•••m','iv•••m','jo•••m'];
export function demoEntries(metric) {
  const scores = metric === 'point' ? [4,4,3,3,3,2,2,2,1,1]
    : metric === 'game' ? [10,10,9,9,8,8,7,7,6,6] : [31,30,29,28,27,26,25,24,22,21];
  return DEMO_NAMES.map((emailMask, i) => ({id: `example-${i}`, emailMask, score: scores[i]}));
}
