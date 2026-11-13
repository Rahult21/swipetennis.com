import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { classifyFinalShot, classifyServe, courtSide, selectServeLanding } from "./tennis-rules";
import PracticeCourt from "./PracticeCourt";
type PlayerIndex = 0 | 1;
type TennisMode = "manual" | "swipe";
type ShotPosition = "Behind baseline" | "On baseline" | "Inside baseline" | "At net";
type CourtPoint = { x: number; y: number };
type TennisPlayer = { name: string; utr: string };
type TennisPoint = { id: string; winner: PlayerIndex; server: PlayerIndex; serve: 1 | 2; outcome: string; position: ShotPosition; mode: TennisMode; createdAt: string; path?: CourtPoint[]; landings?: CourtPoint[]; callout?: string; event?: string };
type TennisMatch = {
  id: string;
  mode: TennisMode;
  players: [TennisPlayer, TennisPlayer];
  setsToPlay: 2 | 3;
  gamesPerSet: 4 | 6;
  firstServer: PlayerIndex;
  currentServer: PlayerIndex;
  serveAttempt: 1 | 2;
  points: [number, number];
  games: [number, number];
  completedSets: Array<[number, number]>;
  setWins: [number, number];
  tiebreak: null | { kind: "set" | "match"; points: [number, number]; firstServer: PlayerIndex };
  winner: PlayerIndex | null;
  log: TennisPoint[];
};
type TennisHistoryEntry = { id: string; title: string; playedAt: string; completedAt: string; score: string; report: string; match: TennisMatch };

const makeId = () => crypto.randomUUID();
function normalizeTennis(value: unknown): TennisMatch | null {
  if (!value || typeof value !== "object") return null;
  const match = value as Partial<TennisMatch>;
  if (!match.id || !Array.isArray(match.players) || match.players.length !== 2) return null;
  return {
    id: match.id,
    mode: match.mode === "swipe" ? "swipe" : "manual",
    players: match.players as TennisMatch["players"],
    setsToPlay: match.setsToPlay === 2 ? 2 : 3,
    gamesPerSet: match.gamesPerSet === 4 ? 4 : 6,
    firstServer: match.firstServer === 1 ? 1 : 0,
    currentServer: match.currentServer === 1 ? 1 : 0,
    serveAttempt: match.serveAttempt === 2 ? 2 : 1,
    points: Array.isArray(match.points) ? match.points as [number, number] : [0, 0],
    games: Array.isArray(match.games) ? match.games as [number, number] : [0, 0],
    completedSets: Array.isArray(match.completedSets) ? match.completedSets : [],
    setWins: Array.isArray(match.setWins) ? match.setWins as [number, number] : [0, 0],
    tiebreak: match.tiebreak || null,
    winner: match.winner === 0 || match.winner === 1 ? match.winner : null,
    log: Array.isArray(match.log) ? match.log : [],
  };
}

function normalizeTennisHistory(value: unknown): TennisHistoryEntry[] {
  if (!Array.isArray(value)) return [];
  return value.map((item) => {
    if (!item || typeof item !== "object") return null;
    const entry = item as Partial<TennisHistoryEntry>;
    const match = normalizeTennis(entry.match);
    if (!match || !entry.completedAt) return null;
    return { id: entry.id || match.id, title: entry.title || `${match.players[0].name} vs ${match.players[1].name}`, playedAt: entry.playedAt || entry.completedAt, completedAt: entry.completedAt, score: entry.score || formatMatchScore(match), report: entry.report || buildMatchReport(match), match };
  }).filter(Boolean).sort((a, b) => Date.parse((b as TennisHistoryEntry).completedAt) - Date.parse((a as TennisHistoryEntry).completedAt)) as TennisHistoryEntry[];
}

function normalizeTennisPlayer(value: unknown): TennisPlayer | null {
  if (!value || typeof value !== "object") return null;
  const player = value as Partial<TennisPlayer>;
  if (!player.name?.trim()) return null;
  return { name: player.name.trim(), utr: typeof player.utr === "string" ? player.utr : "" };
}

const otherPlayer = (player: PlayerIndex): PlayerIndex => player === 0 ? 1 : 0;

function pointDisplay(points: [number, number], player: PlayerIndex) {
  const opponent = otherPlayer(player);
  if (points[player] >= 3 && points[opponent] >= 3) {
    if (points[player] === points[opponent]) return "40";
    return points[player] > points[opponent] ? "AD" : "–";
  }
  return ["0", "15", "30", "40"][Math.min(points[player], 3)];
}

function upcomingTiebreakServer(firstServer: PlayerIndex, pointsPlayed: number): PlayerIndex {
  if (pointsPlayed === 0) return firstServer;
  return Math.floor((pointsPlayed - 1) / 2) % 2 === 0 ? otherPlayer(firstServer) : firstServer;
}

function finishTennisSet(match: TennisMatch, score: [number, number], winner: PlayerIndex, nextServer: PlayerIndex): TennisMatch {
  const completedSets = [...match.completedSets, score];
  const setWins = [...match.setWins] as [number, number];
  setWins[winner] += 1;
  const base = { ...match, completedSets, setWins, points: [0, 0] as [number, number], games: [0, 0] as [number, number], serveAttempt: 1 as const, currentServer: nextServer, tiebreak: null };
  if (match.setsToPlay === 3) return setWins[winner] >= 2 ? { ...base, winner } : base;
  if (completedSets.length < 2) return base;
  if (setWins[winner] === 2) return { ...base, winner };
  return { ...base, tiebreak: { kind: "match", points: [0, 0], firstServer: nextServer }, currentServer: nextServer };
}

function advanceTennisScore(match: TennisMatch, winner: PlayerIndex): TennisMatch {
  if (match.winner !== null) return match;
  if (match.tiebreak) {
    const tiebreakPoints = [...match.tiebreak.points] as [number, number];
    tiebreakPoints[winner] += 1;
    const target = match.tiebreak.kind === "match" ? 10 : 7;
    if (tiebreakPoints[winner] >= target && tiebreakPoints[winner] - tiebreakPoints[otherPlayer(winner)] >= 2) {
      if (match.tiebreak.kind === "match") return { ...match, tiebreak: { ...match.tiebreak, points: tiebreakPoints }, winner, serveAttempt: 1 };
      const score = [...match.games] as [number, number];
      score[winner] += 1;
      return finishTennisSet(match, score, winner, otherPlayer(match.tiebreak.firstServer));
    }
    const pointsPlayed = tiebreakPoints[0] + tiebreakPoints[1];
    return { ...match, tiebreak: { ...match.tiebreak, points: tiebreakPoints }, currentServer: upcomingTiebreakServer(match.tiebreak.firstServer, pointsPlayed), serveAttempt: 1 };
  }

  const points = [...match.points] as [number, number];
  points[winner] += 1;
  if (points[winner] < 4 || points[winner] - points[otherPlayer(winner)] < 2) return { ...match, points, serveAttempt: 1 };

  const games = [...match.games] as [number, number];
  games[winner] += 1;
  const nextServer = otherPlayer(match.currentServer);
  if (games[winner] >= match.gamesPerSet && games[winner] - games[otherPlayer(winner)] >= 2) return finishTennisSet(match, games, winner, nextServer);
  if (games[0] === match.gamesPerSet && games[1] === match.gamesPerSet) return { ...match, games, points: [0, 0], serveAttempt: 1, currentServer: nextServer, tiebreak: { kind: "set", points: [0, 0], firstServer: nextServer } };
  return { ...match, games, points: [0, 0], serveAttempt: 1, currentServer: nextServer };
}

function tennisPointSituation(match: TennisMatch) {
  if (match.winner !== null) return "Match complete";
  const moments: string[] = [];
  for (const player of [0, 1] as PlayerIndex[]) {
    const next = advanceTennisScore(match, player);
    let label = "";
    if (next.winner === player) label = "MATCH POINT";
    else if (next.completedSets.length > match.completedSets.length) label = "SET POINT";
    else if (next.games[player] > match.games[player]) label = player === match.currentServer ? "GAME POINT" : "BREAK POINT";
    if (label) moments.push(`${match.players[player].name} · ${label}`);
  }
  return moments.join("  |  ");
}

function tennisTransition(before: TennisMatch, after: TennisMatch) {
  if (after.winner !== null) return "MATCH";
  if (after.completedSets.length > before.completedSets.length) {
    const completed = after.completedSets.at(-1)!;
    return (completed[0] + completed[1]) % 2 === 1 ? "SET · CHANGEOVER" : "SET";
  }
  if (after.games[0] + after.games[1] > before.games[0] + before.games[1]) return (after.games[0] + after.games[1]) % 2 === 1 ? "CHANGEOVER" : "GAME";
  return "";
}

function formatMatchScore(match: TennisMatch) {
  const sets = match.completedSets.map((set) => `${set[0]}–${set[1]}`);
  if (match.tiebreak?.kind === "match") sets.push(`[${match.tiebreak.points[0]}–${match.tiebreak.points[1]}]`);
  return sets.join("  ") || `${match.games[0]}–${match.games[1]}`;
}

function formatScorePopup(match: TennisMatch, event = "") {
  if (event === "MATCH" || event.startsWith("SET")) return formatMatchScore(match);
  if (event === "GAME" || event === "CHANGEOVER") return `${match.games[0]}–${match.games[1]} games`;
  if (match.tiebreak) return `${match.tiebreak.points[0]}–${match.tiebreak.points[1]}`;
  return `${pointDisplay(match.points, 0)}–${pointDisplay(match.points, 1)}`;
}

function matchStats(match: TennisMatch) {
  return ([0, 1] as PlayerIndex[]).map((player) => {
    const won = match.log.filter((point) => point.winner === player);
    const errors = match.log.filter((point) => {
      const outcome = point.outcome.toLowerCase();
      if (!outcome.includes("error") && !outcome.includes("fault")) return false;
      if (outcome.startsWith("server") || outcome === "double fault") return point.server === player;
      if (outcome.startsWith("return")) return otherPlayer(point.server) === player;
      return outcome.includes(match.players[player].name.toLowerCase()) || point.winner !== player;
    });
    return { points: won.length, aces: won.filter((point) => point.outcome.toLowerCase() === "ace").length, winners: won.filter((point) => point.outcome.toLowerCase().includes("winner")).length, firstServe: won.filter((point) => point.serve === 1).length, secondServe: won.filter((point) => point.serve === 2).length, forcedErrors: errors.filter((point) => point.outcome.toLowerCase().includes("forced error") && !point.outcome.toLowerCase().includes("unforced")).length, unforcedErrors: errors.filter((point) => point.outcome.toLowerCase().includes("unforced error")).length, doubleFaults: errors.filter((point) => point.outcome.toLowerCase() === "double fault").length };
  });
}

function buildMatchReport(match: TennisMatch) {
  const stats = matchStats(match);
  return `Tennis match: ${match.players[0].name} vs ${match.players[1].name}\nDate: ${new Date(match.log.at(-1)?.createdAt || Date.now()).toLocaleDateString()}\nScore: ${formatMatchScore(match)}\nWinner: ${match.winner === null ? "—" : match.players[match.winner].name}\n\n${match.players.map((player, index) => `${player.name}: ${stats[index].points} points won, ${stats[index].aces} aces, ${stats[index].winners} winners, ${stats[index].unforcedErrors} unforced errors, ${stats[index].forcedErrors} forced errors, ${stats[index].doubleFaults} double faults`).join("\n")}`;
}

function createHistoryEntry(match: TennisMatch): TennisHistoryEntry {
  const completedAt = new Date().toISOString();
  return { id: match.id, title: `${match.players[0].name} vs ${match.players[1].name}`, playedAt: match.log.at(-1)?.createdAt || completedAt, completedAt, score: formatMatchScore(match), report: buildMatchReport(match), match };
}

function recordTennisPoint(match: TennisMatch, winner: PlayerIndex, outcome: string, position: ShotPosition, mode: TennisMode, path?: CourtPoint[], landings?: CourtPoint[], serve: 1 | 2 = match.serveAttempt) {
  const pathStep = path?.length ? Math.max(1, Math.ceil(path.length / 24)) : 1;
  const sampledPath = path?.filter((_, index) => index % pathStep === 0).slice(0, 24) || [];
  const pathEnd = path?.at(-1);
  if (pathEnd && sampledPath.at(-1) !== pathEnd) sampledPath.push(pathEnd);
  const savedPath = sampledPath.map((point) => ({ x: Math.round(point.x * 100) / 100, y: Math.round(point.y * 100) / 100 }));
  const scored = advanceTennisScore(match, winner);
  const savedLandings = landings?.slice(-8).map((point) => ({ x: Math.round(point.x * 100) / 100, y: Math.round(point.y * 100) / 100 }));
  const point: TennisPoint = { id: makeId(), winner, server: match.currentServer, serve, outcome, position, mode, createdAt: new Date().toISOString(), callout: tennisPointSituation(match), event: tennisTransition(match, scored), ...(savedPath?.length ? { path: savedPath } : {}), ...(savedLandings?.length ? { landings: savedLandings } : {}) };
  return { ...scored, log: [point, ...match.log].slice(0, 500) };
}

function revertLastTennisPoint(match: TennisMatch) {
  if (!match.log.length) return match;
  const remaining = match.log.slice(1);
  let rebuilt: TennisMatch = {
    ...match,
    currentServer: match.firstServer,
    serveAttempt: 1,
    points: [0, 0],
    games: [0, 0],
    completedSets: [],
    setWins: [0, 0],
    tiebreak: null,
    winner: null,
    log: [],
  };
  for (const point of [...remaining].reverse()) {
    rebuilt = advanceTennisScore(rebuilt, point.winner);
    rebuilt = { ...rebuilt, log: [point, ...rebuilt.log] };
  }
  return rebuilt;
}

function TennisApp({ match, history, defaultPlayer, onDefaultPlayerChange, onChange, onCancel }: { match: TennisMatch | null; history: TennisHistoryEntry[]; defaultPlayer: TennisPlayer | null; onDefaultPlayerChange: (player: TennisPlayer | null) => void; onChange: (match: TennisMatch | null) => void; onCancel: () => void }) {
  const [mode, setMode] = useState<TennisMode>("swipe");
  const [playerOne, setPlayerOne] = useState(defaultPlayer?.name || "");
  const [playerTwo, setPlayerTwo] = useState("");
  const [utrOne, setUtrOne] = useState(defaultPlayer?.utr || "");
  const [utrTwo, setUtrTwo] = useState("");
  const [useAsDefault, setUseAsDefault] = useState(Boolean(defaultPlayer));
  const [setsToPlay, setSetsToPlay] = useState<2 | 3>(2);
  const [gamesPerSet, setGamesPerSet] = useState<4 | 6>(6);
  const [firstServer, setFirstServer] = useState<PlayerIndex>(0);
  const [showHistory, setShowHistory] = useState(false);
  const [reportEntry, setReportEntry] = useState<TennisHistoryEntry | null>(null);
  const [replayEntry, setReplayEntry] = useState<TennisHistoryEntry | null>(null);
  const [scoreFlash, setScoreFlash] = useState("");
  const lastFlashedPoint = useRef(match?.log[0]?.id);

  useEffect(() => {
    if (match || !defaultPlayer) return;
    const timer = window.setTimeout(() => {
      setPlayerOne(defaultPlayer.name);
      setUtrOne(defaultPlayer.utr);
      setUseAsDefault(true);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [defaultPlayer, match]);

  useEffect(() => {
    const latestPoint = match?.log[0];
    if (!match || !latestPoint || latestPoint.id === lastFlashedPoint.current) return;
    lastFlashedPoint.current = latestPoint.id;
    setScoreFlash(formatScorePopup(match, latestPoint.event));
    const timer = window.setTimeout(() => setScoreFlash(""), 1000);
    return () => window.clearTimeout(timer);
  }, [match]);

  function startMatch() {
    if (!playerOne.trim() || !playerTwo.trim()) return;
    if (useAsDefault) onDefaultPlayerChange({ name: playerOne.trim(), utr: utrOne.trim() });
    onChange({ id: makeId(), mode, players: [{ name: playerOne.trim(), utr: utrOne.trim() }, { name: playerTwo.trim(), utr: utrTwo.trim() }], setsToPlay, gamesPerSet, firstServer, currentServer: firstServer, serveAttempt: 1, points: [0, 0], games: [0, 0], completedSets: [], setWins: [0, 0], tiebreak: null, winner: null, log: [] });
  }

  const playerHistory = defaultPlayer ? history.filter((entry) => entry.match.players.some((player) => player.name.trim().toLocaleLowerCase() === defaultPlayer.name.toLocaleLowerCase())) : history;
  const saveDefaultPlayer = () => { if (useAsDefault && playerOne.trim()) onDefaultPlayerChange({ name: playerOne.trim(), utr: utrOne.trim() }); };
  const overlays = <>{scoreFlash && <div className="score-flash" role="status">{scoreFlash}</div>}{showHistory && <MatchHistoryPanel history={playerHistory} defaultPlayer={defaultPlayer} onClose={() => setShowHistory(false)} onReport={(entry) => { setShowHistory(false); setReportEntry(entry); }} onReplay={(entry) => { setShowHistory(false); setReplayEntry(entry); }} />}{reportEntry && <MatchReportModal entry={reportEntry} onClose={() => setReportEntry(null)} />}{replayEntry && <MatchReplay entry={replayEntry} onClose={() => setReplayEntry(null)} />}</>;

  if (!match) return <><section className="tool-surface tennis-setup"><div className="tennis-history-bar"><div className="tennis-kicker">YOUR NEXT MATCH</div><button onClick={() => setShowHistory(true)}>Match history <b>{playerHistory.length}</b></button></div><div className="tennis-setup-head"><div><p className="tool-intro">Let’s take the court.</p><p>Choose manual controls or trace rallies directly on the court.</p></div><div className="tennis-mode-switch" aria-label="Scoring mode">{(["manual", "swipe"] as TennisMode[]).map((value) => <button className={mode === value ? "active" : ""} onClick={() => setMode(value)} key={value}>{value === "manual" ? "Manual mode" : "Swipe mode"}</button>)}</div></div><div className="tennis-setup-grid"><fieldset className="player-one-field"><legend>Player one</legend><label>Name<input value={playerOne} onChange={(event) => setPlayerOne(event.target.value)} onBlur={saveDefaultPlayer} placeholder="Player name" /></label><label>UTR<input type="number" min="1" max="16.5" step="0.01" value={utrOne} onChange={(event) => setUtrOne(event.target.value)} onBlur={saveDefaultPlayer} placeholder="UTR" /></label><label className={`default-player-flag ${useAsDefault ? "selected" : ""}`}><input type="checkbox" checked={useAsDefault} onChange={(event) => { const selected = event.target.checked; setUseAsDefault(selected); if (selected && playerOne.trim()) onDefaultPlayerChange({ name: playerOne.trim(), utr: utrOne.trim() }); else if (!selected) onDefaultPlayerChange(null); }} /><span aria-hidden="true">★</span><b>{useAsDefault ? "Default player" : "Make default"}</b></label></fieldset><fieldset><legend>Player two</legend><label>Name<input value={playerTwo} onChange={(event) => setPlayerTwo(event.target.value)} placeholder="Player name" /></label><label>UTR<input type="number" min="1" max="16.5" step="0.01" value={utrTwo} onChange={(event) => setUtrTwo(event.target.value)} placeholder="UTR" /></label></fieldset><fieldset className="match-format"><legend>Match format</legend><label>Sets<select value={setsToPlay} onChange={(event) => setSetsToPlay(Number(event.target.value) as 2 | 3)}><option value="2">2 sets + 10-point match tiebreak</option><option value="3">Best of 3 sets</option></select></label><label>Games per set<select value={gamesPerSet} onChange={(event) => setGamesPerSet(Number(event.target.value) as 4 | 6)}><option value="4">4 games</option><option value="6">6 games</option></select></label><label>Serves first<select value={firstServer} onChange={(event) => setFirstServer(Number(event.target.value) as PlayerIndex)}><option value="0">{playerOne || "Player one"}</option><option value="1">{playerTwo || "Player two"}</option></select></label></fieldset></div><button className="start-match" onClick={startMatch} disabled={!playerOne.trim() || !playerTwo.trim()}>Start match</button></section>{overlays}</>;

  return <><section className="tennis-app"><TennisScoreboard match={match} /><div className="tennis-live-toolbar"><div className="tennis-mode-switch">{(["manual", "swipe"] as TennisMode[]).map((value) => <button className={match.mode === value ? "active" : ""} onClick={() => onChange({ ...match, mode: value })} key={value}>{value === "manual" ? "Manual" : "Swipe court"}</button>)}<button className="revert-point" disabled={!match.log.length} onClick={() => onChange(revertLastTennisPoint(match))}>↶ Revert point</button></div><div className="match-actions"><button className="history-match" onClick={() => setShowHistory(true)}>Match history <b>{playerHistory.length}</b></button><button className="cancel-match" onClick={() => { if (confirm("Cancel this match? All captured scores will be discarded.")) onCancel(); }}>Cancel</button><button className="new-match" onClick={() => { if (confirm("Start a new match? The current score will be replaced.")) onChange(null); }}>New match</button></div></div>{match.winner !== null ? <><div className="match-winner"><span>Match complete · saved to history</span><strong>{match.players[match.winner].name} wins · {formatMatchScore(match)}</strong></div><TennisStatsReport match={match} /></> : match.mode === "manual" ? <ManualTennisScorer match={match} onChange={onChange} /> : <SwipeTennisScorer match={match} onChange={onChange} />}<TennisPointLog match={match} /></section>{overlays}</>;
}

function TennisScoreboard({ match }: { match: TennisMatch }) {
  const showCurrentSet = match.winner === null && match.tiebreak?.kind !== "match";
  const columns = [...match.completedSets.map((_, index) => `S${index + 1}`), ...(showCurrentSet ? [`S${match.completedSets.length + 1}`] : []), ...(match.tiebreak?.kind === "match" ? ["MTB"] : [])];
  const situation = tennisPointSituation(match);
  const lastEvent = match.log[0]?.event;
  return <section className="tennis-scoreboard"><div className="scoreboard-title"><div><span>LIVE SCORE</span><strong>{match.tiebreak?.kind === "match" ? "Match tiebreak · first to 10" : match.tiebreak?.kind === "set" ? "Set tiebreak · first to 7" : `Set ${match.completedSets.length + 1}`}</strong></div><small>{match.gamesPerSet}-game sets · {match.setsToPlay === 2 ? "match tiebreak format" : "best of three"} · {columns.join(" / ")} / point</small></div>{(situation || lastEvent) && <div className={`tennis-moment ${situation.includes("MATCH POINT") ? "match-point" : situation.includes("SET POINT") ? "set-point" : ""}`}><span>{situation || lastEvent}</span>{lastEvent?.includes("CHANGEOVER") && <small>Players change ends</small>}</div>}<div className="score-grid"><div className="score-head">Player</div>{columns.map((column) => <div className="score-head" key={column}>{column}</div>)}<div className="score-head">Point</div>{([0, 1] as PlayerIndex[]).map((player) => <div className="score-row" key={player}><div className="score-player">{match.winner === null && match.currentServer === player && <i title="Serving" />}<span><strong>{match.players[player].name}</strong><small>UTR {match.players[player].utr || "—"}</small></span></div>{match.completedSets.map((set, index) => <b key={index}>{set[player]}</b>)}{showCurrentSet && <b>{match.games[player]}</b>}{match.tiebreak?.kind === "match" && <b>{match.tiebreak.points[player]}</b>}<em>{match.winner !== null ? match.winner === player ? "WIN" : "—" : match.tiebreak?.kind === "match" ? "TB" : match.tiebreak ? match.tiebreak.points[player] : pointDisplay(match.points, player)}</em></div>)}</div></section>;
}

function ShotPositionPicker({ value, onChange }: { value: ShotPosition; onChange: (value: ShotPosition) => void }) {
  const positions: ShotPosition[] = ["Behind baseline", "On baseline", "Inside baseline", "At net"];
  return <div className="shot-position"><span>Point winner’s last-shot position</span><div>{positions.map((position) => <button className={value === position ? "active" : ""} onClick={() => onChange(position)} key={position}>{position}</button>)}</div></div>;
}

function ManualTennisScorer({ match, onChange }: { match: TennisMatch; onChange: (match: TennisMatch) => void }) {
  const [position, setPosition] = useState<ShotPosition>("Behind baseline");
  const server = match.currentServer;
  const returner = otherPlayer(server);
  const win = (winner: PlayerIndex, outcome: string) => onChange(recordTennisPoint(match, winner, outcome, position, "manual"));
  function serveFault() {
    if (match.serveAttempt === 1) onChange({ ...match, serveAttempt: 2 });
    else win(returner, "Double fault");
  }
  return <div className="manual-scorer"><ShotPositionPicker value={position} onChange={setPosition} /><div className="scoring-panels"><section className="scoring-panel server-panel"><header><span>SERVER · {match.serveAttempt === 1 ? "FIRST SERVE" : "SECOND SERVE"}</span><strong>{match.players[server].name}</strong></header><div className="point-buttons"><button className="fault" onClick={serveFault}>{match.serveAttempt === 1 ? "Serve fault → second serve" : "Serve fault → double fault"}</button><button onClick={() => win(server, "Ace")}>Ace</button><button onClick={() => win(server, "Winner")}>Winner</button><button onClick={() => win(returner, "Server unforced error")}>Unforced error</button><button onClick={() => win(returner, "Server forced error")}>Forced error</button></div></section><section className="scoring-panel return-panel"><header><span>RETURNER</span><strong>{match.players[returner].name}</strong></header><div className="point-buttons"><button className="fault" onClick={() => win(server, "Return error")}>Return error</button><button onClick={() => win(returner, "Return winner")}>Winner</button><button onClick={() => win(server, "Returner unforced error")}>Unforced error</button><button onClick={() => win(server, "Returner forced error")}>Forced error</button></div></section></div></div>;
}

function normalizeLandingSpots(spots: LiveCourtPoint[]) {
  const normalized: LiveCourtPoint[] = [];
  for (const spot of spots) {
    const previous = normalized.at(-1);
    // A second pause on the same side is treated as hand jitter/double-bounce input.
    if (previous && courtSide(previous) === courtSide(spot)) continue;
    normalized.push(spot);
  }
  return normalized;
}

function wasForcedByPreviousShot(landings: LiveCourtPoint[], finalIndex: number) {
  const received = landings[finalIndex - 1];
  if (!received) return false;
  const nearSideline = received.x <= 22 || received.x >= 78;
  const deep = courtSide(received) === "top" ? received.y <= 18 : received.y >= 142;
  const prior = landings[finalIndex - 2];
  const changedDirectionSharply = Boolean(prior && Math.abs(received.x - prior.x) >= 42);
  return nearSideline || deep || changedDirectionSharply;
}

function inferShotPosition(path: CourtPoint[], winnerIsBottom: boolean): ShotPosition {
  const visits: CourtPoint[][] = [];
  for (const point of path) {
    const isBottom = point.y >= 80;
    const current = visits.at(-1);
    if (!current || (current[0].y >= 80) !== isBottom) visits.push([point]);
    else current.push(point);
  }
  const visit = visits.filter((points) => (points[0].y >= 80) === winnerIsBottom).at(-1);
  const start = visit?.[0];
  const end = visit?.at(-1);
  const contact = start && end ? (winnerIsBottom ? start.y >= end.y ? start : end : start.y <= end.y ? start : end) : { x: 50, y: winnerIsBottom ? 145 : 15 };
  const depth = winnerIsBottom ? contact.y : 160 - contact.y;
  if (depth >= 152) return "Behind baseline";
  if (depth >= 132) return "On baseline";
  if (depth >= 96) return "Inside baseline";
  return "At net";
}

function lastTwoShotPath(path: LiveCourtPoint[], landings: LiveCourtPoint[]) {
  if (landings.length <= 2) return path;
  const cutoff = landings[landings.length - 3].at;
  const start = path.findIndex((point) => point.at >= cutoff);
  return start < 0 ? path : path.slice(start);
}

type LiveCourtPoint = CourtPoint & { at: number };
type PendingSwipePoint = { winner: PlayerIndex; outcome: string; serve: 1 | 2; position: ShotPosition; path: LiveCourtPoint[]; landings: LiveCourtPoint[] };
type SwipeAnalysis =
  | { kind: "retry"; message: string }
  | { kind: "fault"; message: string }
  | { kind: "point"; point: PendingSwipePoint; message: string };

function analyzeSwipePoint(match: TennisMatch, rawLandings: LiveCourtPoint[], path: LiveCourtPoint[], serveFromRight: boolean): SwipeAnalysis {
  const server = match.currentServer;
  const returner = otherPlayer(server);
  let landings = normalizeLandingSpots(rawLandings);
  const end = path.at(-1);
  const start = path[0];
  if (!start || courtSide(start) !== "bottom" || start.y < 125) {
    return { kind: "retry", message: "Begin the trace from the server’s baseline position." };
  }
  if (!end || !landings.length) {
    return { kind: "retry", message: "Lift your finger where the final ball lands to finish the point." };
  }

  // When the gesture ends in the service area, finger-up is the authoritative
  // serve landing. This prevents a brief slowdown earlier in the flight from
  // turning a legal serve into a fault.
  const serve = selectServeLanding(landings[0], end, landings.length);
  if (serve === end) landings = [{ ...end }];
  const serveResult = classifyServe(match.serveAttempt, serve, serveFromRight);
  if (serveResult.kind !== "legal") {
    const reason = serveResult.reason === "wrong-box" ? "wrong service box" : serveResult.reason;
    return { kind: "fault", message: match.serveAttempt === 1 ? `First serve fault (${reason}). Trace the second serve.` : `Double fault (${reason}). Review the journal entry.` };
  }

  if (landings.length === 1) {
    return { kind: "point", point: { winner: server, outcome: "Ace", serve: match.serveAttempt, position: inferShotPosition(path, true), path, landings }, message: "No return crossed the net. Review the inferred ace journal entry." };
  }

  const finalLanding = landings.at(-1)!;
  const finalIndex = landings.length - 1;
  const lastHitter = finalIndex % 2 === 0 ? server : returner;
  const finalShot = classifyFinalShot(finalIndex, finalLanding, wasForcedByPreviousShot(landings, finalIndex));
  const winner = finalShot.winner === "hitter" ? lastHitter : otherPlayer(lastHitter);
  const outcome = finalShot.outcome.endsWith("error") && finalIndex > 1 ? `${match.players[lastHitter].name} ${finalShot.outcome}` : finalShot.outcome;

  return {
    kind: "point",
    point: { winner, outcome, serve: match.serveAttempt, position: inferShotPosition(path, winner === server), path, landings },
    message: `Review ${match.players[winner].name}’s inferred point entry.`,
  };
}

function CourtGirl({ x, y, direction }: { x: number; y: number; direction: 0 | 180 }) {
  return <g className="girl-player court-player" style={{ transform: `translate(${x}px, ${y}px) rotate(${direction}deg)` }}><circle cx="0" cy="-7" r="2.4" /><path d="M-3 -4 L3 -4 L6 4 L-6 4 Z" /><line x1="-3" y1="-2" x2="-8" y2="2" /><line x1="3" y1="-2" x2="8" y2="2" /><line x1="-2" y1="4" x2="-4" y2="9" /><line x1="2" y1="4" x2="4" y2="9" /></g>;
}

function SwipePointConfirmation({ match, point, onChange, onRetry, onConfirm }: { match: TennisMatch; point: PendingSwipePoint; onChange: (point: PendingSwipePoint) => void; onRetry: () => void; onConfirm: () => void }) {
  const server = match.currentServer;
  const returner = otherPlayer(server);
  const outcomes = Array.from(new Set(["Ace", "Winner", "Return winner", "Return error", "Double fault", `${match.players[server].name} forced error`, `${match.players[server].name} unforced error`, `${match.players[returner].name} forced error`, `${match.players[returner].name} unforced error`, point.outcome]));
  return <div className="point-confirm-backdrop" role="dialog" aria-modal="true" aria-labelledby="point-confirm-title"><section className="point-confirm"><span>POINT JOURNAL REVIEW</span><h2 id="point-confirm-title">Confirm or correct the point before it changes the score.</h2><div className="point-confirm-summary"><label><small>Winner</small><select value={point.winner} onChange={(event) => onChange({ ...point, winner: Number(event.target.value) as PlayerIndex })}>{match.players.map((player, index) => <option value={index} key={player.name}>{player.name}</option>)}</select></label><label><small>Outcome</small><select value={point.outcome} onChange={(event) => onChange({ ...point, outcome: event.target.value })}>{outcomes.map((outcome) => <option value={outcome} key={outcome}>{outcome}</option>)}</select></label><label><small>Serve</small><select value={point.serve} onChange={(event) => onChange({ ...point, serve: Number(event.target.value) as 1 | 2 })}><option value="1">First serve</option><option value="2">Second serve</option></select></label></div><div className="point-position-review"><small>Winning player’s last-shot position</small><div>{(["Behind baseline", "On baseline", "Inside baseline", "At net"] as ShotPosition[]).map((position) => <button className={point.position === position ? "active" : ""} onClick={() => onChange({ ...point, position })} key={position}>{position}</button>)}</div></div><p>Winner, outcome, serve, and court position can all be corrected before saving.</p><footer><button className="retry-point" onClick={onRetry}>↻ Retry trace</button><button className="confirm-point" onClick={onConfirm}>✓ Confirm point</button></footer></section></div>;
}

function SwipeTennisScorer({ match, onChange }: { match: TennisMatch; onChange: (match: TennisMatch) => void }) {
  const [path, setPath] = useState<LiveCourtPoint[]>([]);
  const [landings, setLandings] = useState<LiveCourtPoint[]>([]);
  const [drawing, setDrawing] = useState(false);
  const [showDemo, setShowDemo] = useState(false);
  const [showOngoingReplay, setShowOngoingReplay] = useState(false);
  const [pendingPoint, setPendingPoint] = useState<PendingSwipePoint | null>(null);
  const [clock, setClock] = useState(0);
  const [message, setMessage] = useState("Touch the server side, then trace the ball through the point.");
  const pathRef = useRef<LiveCourtPoint[]>([]);
  const landingRef = useRef<LiveCourtPoint[]>([]);
  const currentPointRef = useRef<LiveCourtPoint | null>(null);
  const lastMotionAtRef = useRef(0);
  const distanceSinceLandingRef = useRef(0);
  const pauseCapturedRef = useRef(false);
  const courtRef = useRef<SVGSVGElement>(null);
  const server = match.currentServer;
  const returner = otherPlayer(server);
  const pointOrdinal = match.tiebreak ? match.tiebreak.points[0] + match.tiebreak.points[1] : match.points[0] + match.points[1];
  const serveFromRight = pointOrdinal % 2 === 0;

  useEffect(() => {
    if (!drawing) return;
    const timer = window.setInterval(() => {
      const now = Date.now();
      setClock(now);
      const current = currentPointRef.current;
      if (!current || pauseCapturedRef.current || distanceSinceLandingRef.current < 8 || now - lastMotionAtRef.current < 250) return;
      const landing = { ...current, at: now };
      landingRef.current = [...landingRef.current, landing];
      setLandings(normalizeLandingSpots(landingRef.current));
      distanceSinceLandingRef.current = 0;
      pauseCapturedRef.current = true;
    }, 100);
    return () => window.clearInterval(timer);
  }, [drawing]);

  function courtPoint(event: ReactPointerEvent<SVGSVGElement>): LiveCourtPoint {
    const rectangle = courtRef.current!.getBoundingClientRect();
    return { x: Math.max(0, Math.min(100, (event.clientX - rectangle.left) / rectangle.width * 100)), y: Math.max(0, Math.min(160, (event.clientY - rectangle.top) / rectangle.height * 160)), at: Date.now() };
  }

  function pointerDown(event: ReactPointerEvent<SVGSVGElement>) {
    if (pendingPoint) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    const first = courtPoint(event);
    pathRef.current = [first];
    landingRef.current = [];
    currentPointRef.current = first;
    lastMotionAtRef.current = first.at;
    distanceSinceLandingRef.current = 0;
    pauseCapturedRef.current = true;
    setPath([first]);
    setLandings([]);
    setClock(first.at);
    setDrawing(true);
    setMessage("Trace the rally and lift where the point ends.");
  }

  function pointerMove(event: ReactPointerEvent<SVGSVGElement>) {
    if (!drawing) return;
    const next = courtPoint(event);
    const previous = pathRef.current.at(-1)!;
    currentPointRef.current = next;
    const distance = Math.hypot(next.x - previous.x, next.y - previous.y);
    if (distance < 0.75) return;
    const updated = [...pathRef.current, next];
    pathRef.current = updated;
    distanceSinceLandingRef.current += distance;
    lastMotionAtRef.current = next.at;
    pauseCapturedRef.current = false;
    setPath(updated);
    setClock(next.at);
  }

  function pointerUp() {
    if (!drawing) return;
    setDrawing(false);
    const traced = pathRef.current;
    pathRef.current = [];
    currentPointRef.current = null;
    const distanceTraced = traced.slice(1).reduce((total, point, index) => total + Math.hypot(point.x - traced[index].x, point.y - traced[index].y), 0);
    if (traced.length < 2 || distanceTraced < 8) { setMessage("Trace the ball across the net before lifting your finger."); return; }
    const end = traced.at(-1)!;
    let capturedLandings = normalizeLandingSpots(landingRef.current);
    const lastLanding = capturedLandings.at(-1);
    if (!lastLanding) capturedLandings = [{ ...end, at: Date.now() }];
    else if (courtSide(lastLanding) !== courtSide(end)) capturedLandings = [...capturedLandings, { ...end, at: Date.now() }];
    setLandings(capturedLandings);
    const analysis = analyzeSwipePoint(match, capturedLandings, traced, serveFromRight);
    if (analysis.kind === "retry") { setMessage(analysis.message); return; }
    if (analysis.kind === "fault") {
      if (match.serveAttempt === 1) onChange({ ...match, serveAttempt: 2 });
      else setPendingPoint({ winner: returner, outcome: "Double fault", serve: 2, position: "On baseline", path: traced, landings: capturedLandings });
      setMessage(analysis.message);
      return;
    }
    setPendingPoint(analysis.point);
    setMessage(analysis.message);
  }

  function confirmPendingPoint() {
    if (!pendingPoint) return;
    onChange(recordTennisPoint(match, pendingPoint.winner, pendingPoint.outcome, pendingPoint.position, "swipe", pendingPoint.path, pendingPoint.landings, pendingPoint.serve));
    setMessage(`${match.players[pendingPoint.winner].name}’s point was confirmed.`);
    setPendingPoint(null);
    setPath([]);
    setLandings([]);
    landingRef.current = [];
  }

  function retryPendingPoint() {
    setPendingPoint(null);
    setPath([]);
    pathRef.current = [];
    landingRef.current = [];
    currentPointRef.current = null;
    setLandings([]);
    setMessage("Point discarded. Trace it again from the server baseline.");
  }

  const visiblePath = lastTwoShotPath(path, landings).filter((point) => pendingPoint || clock - point.at <= 2000);
  const line = visiblePath.map((point) => `${point.x},${point.y}`).join(" ");
  const ball = drawing ? path.at(-1) : undefined;
  const bottomPlayer = { x: serveFromRight ? 70 : 30, y: 145 };
  const topPlayer = { x: serveFromRight ? 30 : 70, y: 15 };
  const replayEntry: TennisHistoryEntry = { id: `${match.id}-ongoing`, title: `${match.players[0].name} vs ${match.players[1].name}`, playedAt: match.log.at(-1)?.createdAt || new Date().toISOString(), completedAt: new Date().toISOString(), score: formatMatchScore(match), report: buildMatchReport(match), match };
  return <><div className="swipe-demo-launch"><span>Learn the latest swipe flow or replay this match so far.</span><div><button onClick={() => setShowDemo((current) => !current)}>{showDemo ? "Hide demo" : "Watch 2-point demo"}</button><button className="ongoing-replay-button" disabled={!match.log.length} onClick={() => setShowOngoingReplay(true)}>▶ Replay match so far</button></div></div>{showDemo && <SwipeDemoVideo players={[match.players[server].name, match.players[returner].name]} />}{showOngoingReplay && <MatchReplay entry={replayEntry} onClose={() => setShowOngoingReplay(false)} ongoing />}<div className="swipe-scorer"><div className="swipe-instructions"><strong>{match.serveAttempt === 1 ? "First serve" : "Second serve"} · {match.players[server].name} serving</strong><span>{message}</span><small>Pause for a quarter second at each bounce; lift your finger to finish the point and open its journal.</small></div><div className="court-frame"><div className="court-name top">{match.players[returner].name}<small>RETURNER</small></div><div className="court-name bottom">{match.players[server].name}<small>SERVER</small></div><svg ref={courtRef} className="tennis-court" viewBox="0 0 100 160" preserveAspectRatio="none" onPointerDown={pointerDown} onPointerMove={pointerMove} onPointerUp={pointerUp} onPointerCancel={() => { setDrawing(false); pathRef.current = []; currentPointRef.current = null; setPath([]); setLandings([]); }}><rect className="court-grass" x="0" y="0" width="100" height="160" rx="2" /><g className="court-lines"><rect x="12" y="8" width="76" height="144" /><line x1="4" y1="8" x2="96" y2="8" /><line x1="4" y1="152" x2="96" y2="152" /><line x1="12" y1="45" x2="88" y2="45" /><line x1="12" y1="115" x2="88" y2="115" /><line x1="50" y1="45" x2="50" y2="115" /><line className="net" x1="3" y1="80" x2="97" y2="80" /></g><CourtGirl x={topPlayer.x} y={topPlayer.y} direction={180} /><CourtGirl x={bottomPlayer.x} y={bottomPlayer.y} direction={0} />{line && <polyline className="ball-trace" points={line} />}{landings.slice(-2).map((point, index) => <circle className="court-bounce" cx={point.x} cy={point.y} r="3" key={`${index}-${point.x}-${point.y}`} />)}{ball && <circle className="court-ball" cx={ball.x} cy={ball.y} r="1.8" />}</svg></div><div className="swipe-legend"><span><i className="inside" /> Serve must land diagonally in the correct service box</span><span><i className="wide" /> Return and rally endings use singles-court boundaries</span><span><i className="bounce" /> Only the latest two shots and pause-marked landings remain visible</span></div></div>{pendingPoint && <SwipePointConfirmation match={match} point={pendingPoint} onChange={setPendingPoint} onRetry={retryPendingPoint} onConfirm={confirmPendingPoint} />}</>;
}

function SwipeDemoVideo({ players }: { players: [string, string] }) {
  const [phase, setPhase] = useState(0);
  const [run, setRun] = useState(1);
  useEffect(() => {
    let step = 0;
    const timer = window.setInterval(() => {
      step += 1;
      setPhase(step);
      if (step >= 13) window.clearInterval(timer);
    }, 1050);
    return () => window.clearInterval(timer);
  }, [run]);

  const messages = ["Point 1 · Start at the server baseline.", "Pause for at least 0.25 seconds where the serve lands in the diagonal service box.", "Lift after a legal serve with no return line: it is inferred as an Ace for the server.", "The point journal opens before the score changes.", "Winner, Outcome and Serve are editable lists; correct them if needed, then confirm.", "The point-only score appears as 15–0 for one second.", "Point 2 · Players switch deuce/ad positions but remain at their baselines.", "A wide first serve is a fault; trace again for the second serve.", "On serve two, cross the net and pause at each bounce.", "Only the latest two shot traces and landing spots remain on court.", "Lift to finish; review Winner, Outcome, Serve and court position in the journal.", "Confirming shows the point-only score: 15–15.", "At game end the popup shows games only; at set end it shows the complete set score.", "Demo complete · replay it or trace the next live point."];
  const pointOne = phase >= 1 && phase <= 4 ? "70,145 63,112 55,82 43,60" : "";
  const faultPath = phase === 7 ? "30,145 24,112 13,80 4,57" : "";
  const pointTwo = phase < 8 ? "" : phase === 8 ? "30,145 37,112 46,82 59,60" : phase === 9 ? "59,60 67,35 70,15 61,44 52,82 35,132" : "52,82 35,132 42,111 54,82 72,42";
  const activePath = phase < 6 ? pointOne : pointTwo || faultPath;
  const activePoints = activePath.split(" ").filter(Boolean);
  const finger = activePoints.at(-1)?.split(",").map(Number) || [70, 145];
  const secondPoint = phase >= 6;
  const score = phase >= 11 ? "15–15" : phase >= 5 ? "15–0" : "0–0";
  const showJournal = phase === 3 || phase === 4 || phase === 10;
  const showScore = phase === 5 || phase === 11;

  return <section className="swipe-demo-video"><header><div><span>UPDATED 2-POINT SWIPE DEMO</span><strong>{score}</strong></div><button onClick={() => { setPhase(0); setRun((current) => current + 1); }}>↻ Replay</button></header><div className="demo-stage"><svg viewBox="0 0 100 160" preserveAspectRatio="none" aria-label="Animated two-point swipe demonstration"><rect className="court-grass" width="100" height="160" rx="2" /><g className="court-lines"><rect x="12" y="8" width="76" height="144" /><line x1="4" y1="8" x2="96" y2="8" /><line x1="4" y1="152" x2="96" y2="152" /><line x1="12" y1="45" x2="88" y2="45" /><line x1="12" y1="115" x2="88" y2="115" /><line x1="50" y1="45" x2="50" y2="115" /><line className="net" x1="3" y1="80" x2="97" y2="80" /></g><CourtGirl x={secondPoint ? 70 : 30} y={15} direction={180} /><CourtGirl x={secondPoint ? 30 : 70} y={145} direction={0} />{pointOne && <polyline className="demo-trace" points={pointOne} key={`one-${phase}`} />}{faultPath && <polyline className="demo-trace fault" points={faultPath} key={`fault-${phase}`} />}{pointTwo && <polyline className="demo-trace" points={pointTwo} key={`two-${phase}`} />}<circle className="demo-hit" cx={finger[0]} cy={finger[1]} r="3" /></svg>{activePath && <span className="demo-finger" style={{ left: `${finger[0]}%`, top: `${finger[1] / 1.6}%` }}>☝</span>}<div className="demo-player-label top">{players[1]}</div><div className="demo-player-label bottom">{players[0]}</div>{showJournal && <div className="demo-journal"><b>POINT JOURNAL</b><span>Winner ▾</span><span>Outcome ▾</span><span>Serve ▾</span><strong>✓ Confirm point</strong></div>}{showScore && <div className="demo-score-flash">{score}</div>}</div><p>{messages[Math.min(phase, messages.length - 1)]}</p><div className="demo-scenarios"><span>0.25s landing pause</span><span>Unreturned serve = Ace</span><span>Editable journal</span><span>Point-only popup</span><span>Last 2 shots</span><span>Replay speeds</span></div></section>;
}

function TennisStatsReport({ match }: { match: TennisMatch }) {
  const [shareStatus, setShareStatus] = useState("Share report");
  const stats = matchStats(match);
  const sets = formatMatchScore(match);
  const report = buildMatchReport(match);

  async function shareReport() {
    try {
      if (navigator.share) await navigator.share({ title: "Tennis match stats", text: report });
      else await navigator.clipboard.writeText(report);
      setShareStatus(typeof navigator.share === "function" ? "Shared" : "Copied");
    } catch { setShareStatus("Share report"); }
  }

  const rows: Array<[string, keyof typeof stats[number]]> = [["Points won", "points"], ["Aces", "aces"], ["Winners", "winners"], ["1st-serve points won", "firstServe"], ["2nd-serve points won", "secondServe"], ["Forced errors", "forcedErrors"], ["Unforced errors", "unforcedErrors"], ["Double faults", "doubleFaults"]];
  return <section className="tennis-stats"><header><div><span>MATCH REPORT</span><strong>{sets || "Match complete"}</strong></div><button onClick={shareReport}>{shareStatus}</button></header><div className="stats-table"><div className="stats-head">Statistic</div>{match.players.map((player) => <div className="stats-head" key={player.name}>{player.name}</div>)}{rows.map(([label, key]) => <div className="stats-row" key={key}><span>{label}</span><b>{stats[0][key]}</b><b>{stats[1][key]}</b></div>)}</div></section>;
}

function TennisPointLog({ match }: { match: TennisMatch }) {
  return <section className="point-log"><header><div><span>POINT JOURNAL</span><strong>{match.log.length} captured</strong></div></header>{match.log.length ? <div>{match.log.slice(0, 12).map((point, index) => <article key={point.id}><span>{String(match.log.length - index).padStart(2, "0")}</span><div><strong>{match.players[point.winner].name}</strong><small>{point.outcome} · {point.position} · {point.serve === 1 ? "1st serve" : "2nd serve"}</small></div><em>{point.mode}</em></article>)}</div> : <p>No points captured yet.</p>}</section>;
}

function MatchHistoryPanel({ history, defaultPlayer, onClose, onReport, onReplay }: { history: TennisHistoryEntry[]; defaultPlayer: TennisPlayer | null; onClose: () => void; onReport: (entry: TennisHistoryEntry) => void; onReplay: (entry: TennisHistoryEntry) => void }) {
  return <div className="tennis-modal-backdrop" role="dialog" aria-modal="true" aria-label="Match history"><section className="match-history"><header><div><span>TENNIS LIFE</span><h2>Match history</h2>{defaultPlayer && <small>{defaultPlayer.name} · UTR {defaultPlayer.utr || "—"}</small>}</div><button onClick={onClose} aria-label="Close match history">×</button></header>{history.length ? <div className="history-grid"><div className="history-head">Match</div><div className="history-head">Played</div><div className="history-head">Score</div><div className="history-head">Actions</div>{history.map((entry) => <div className="history-row" key={entry.id}><div><strong>{entry.title}</strong><small>{entry.match.winner === null ? "Completed" : `${entry.match.players[entry.match.winner].name} won`}</small></div><time dateTime={entry.completedAt}>{new Date(entry.completedAt).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })}</time><b>{entry.score}</b><div className="history-actions"><button onClick={() => onReport(entry)} title="Open match report" aria-label={`Open report for ${entry.title}`}>▤</button><button className="history-play" onClick={() => onReplay(entry)} title="Replay match journal" aria-label={`Replay ${entry.title}`}>▶</button></div></div>)}</div> : <p className="history-empty">{defaultPlayer ? `Completed matches for ${defaultPlayer.name} will appear here automatically.` : "Your completed matches will appear here automatically."}</p>}</section></div>;
}

function MatchReportModal({ entry, onClose }: { entry: TennisHistoryEntry; onClose: () => void }) {
  return <div className="tennis-modal-backdrop" role="dialog" aria-modal="true" aria-label={`${entry.title} report`}><section className="match-report-modal"><header><div><span>MATCH REPORT</span><h2>{entry.title}</h2><small>{new Date(entry.completedAt).toLocaleDateString()} · {entry.score}</small></div><button onClick={onClose} aria-label="Close report">×</button></header><pre>{entry.report}</pre></section></div>;
}

type ReplayFrame = { point: TennisPoint; score: string; callout: string; event: string };

function buildReplayFrames(match: TennisMatch): ReplayFrame[] {
  let replay: TennisMatch = { ...match, currentServer: match.firstServer, serveAttempt: 1, points: [0, 0], games: [0, 0], completedSets: [], setWins: [0, 0], tiebreak: null, winner: null, log: [] };
  return [...match.log].reverse().map((point) => {
    const callout = point.callout || tennisPointSituation(replay);
    const next = advanceTennisScore(replay, point.winner);
    const event = point.event || tennisTransition(replay, next);
    replay = { ...next, log: [point, ...replay.log] };
    return { point, score: formatScorePopup(replay, event), callout, event };
  });
}

function MatchReplay({ entry, onClose, ongoing = false }: { entry: TennisHistoryEntry; onClose: () => void; ongoing?: boolean }) {
  const frames = buildReplayFrames(entry.match);
  const [index, setIndex] = useState(0);
  const [phase, setPhase] = useState<"trace" | "score">("trace");
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState<1 | 2 | 3>(1);
  const frame = frames[index];

  useEffect(() => {
    if (!playing || !frame) return;
    const timer = window.setTimeout(() => {
      if (phase === "trace") setPhase("score");
      else if (index < frames.length - 1) { setIndex((current) => current + 1); setPhase("trace"); }
      else setPlaying(false);
    }, (phase === "trace" ? 1500 : 1000) / speed);
    return () => window.clearTimeout(timer);
  }, [frame, frames.length, index, phase, playing, speed]);

  if (!frame) return <div className="tennis-modal-backdrop"><section className="match-replay"><header><h2>{entry.title}</h2><button onClick={onClose}>×</button></header><p>No journal points were saved for this match.</p></section></div>;
  const path = frame.point.path || [];
  const landings = frame.point.landings?.length ? frame.point.landings : path.length ? [path.at(-1)!] : [];
  const server = frame.point.server;
  const returner = otherPlayer(server);
  const start = path[0];
  const bottomX = start?.x ?? 70;
  const topX = bottomX > 50 ? 30 : 70;
  return <div className="tennis-modal-backdrop" role="dialog" aria-modal="true" aria-label={`Replay ${entry.title}`}><section className="match-replay"><header><div><span>{ongoing ? "ONGOING MATCH REPLAY" : "MATCH REPLAY"} · POINT {index + 1}/{frames.length}</span><h2>{entry.title}</h2></div><button onClick={onClose} aria-label="Close replay">×</button></header><div className="replay-meta"><strong>{frame.callout || `${frame.point.serve === 1 ? "First" : "Second"} serve`}</strong><span>{entry.match.players[frame.point.winner].name} · {frame.point.outcome}</span></div><div className="replay-court-wrap"><svg className="tennis-court replay-court" viewBox="0 0 100 160" preserveAspectRatio="none"><rect className="court-grass" width="100" height="160" rx="2" /><g className="court-lines"><rect x="12" y="8" width="76" height="144" /><line x1="4" y1="8" x2="96" y2="8" /><line x1="4" y1="152" x2="96" y2="152" /><line x1="12" y1="45" x2="88" y2="45" /><line x1="12" y1="115" x2="88" y2="115" /><line x1="50" y1="45" x2="50" y2="115" /><line className="net" x1="3" y1="80" x2="97" y2="80" /></g><CourtGirl x={topX} y={15} direction={180} /><CourtGirl x={bottomX} y={145} direction={0} />{path.length > 1 && <polyline className="replay-trace" style={{ animationDuration: `${1.25 / speed}s` }} points={path.map((point) => `${point.x},${point.y}`).join(" ")} key={`${frame.point.id}-${speed}`} />}{landings.map((point, landingIndex) => <g key={`${frame.point.id}-${landingIndex}`}><circle className="replay-bounce" cx={point.x} cy={point.y} r="2.3" /><circle className="court-bounce" cx={point.x} cy={point.y} r="3" /></g>)}</svg><div className="replay-name top">{entry.match.players[returner].name}</div><div className="replay-name bottom">{entry.match.players[server].name}</div>{!path.length && <div className="manual-replay-card"><strong>Manual point</strong><span>{frame.point.outcome}</span></div>}{phase === "score" && <div className="replay-score-pop" style={{ animationDuration: `${1 / speed}s` }}><strong>{frame.score}</strong></div>}</div><footer><div className="replay-speed" role="group" aria-label="Replay speed">{([1, 2, 3] as const).map((value) => <button className={speed === value ? "active" : ""} onClick={() => setSpeed(value)} aria-pressed={speed === value} key={value}>{value}×</button>)}</div><button onClick={() => { setIndex(0); setPhase("trace"); setPlaying(true); }}>↻ Replay all</button><button onClick={() => setPlaying((current) => !current)}>{playing ? "Pause" : "Play"}</button></footer></section></div>;
}



type SavedState = { match: TennisMatch | null; history: TennisHistoryEntry[]; player: TennisPlayer | null };
const storageKey = "swipetennis.v1";
function loadSaved(): SavedState {
  try {
    const saved = JSON.parse(localStorage.getItem(storageKey) || "{}");
    return { match: normalizeTennis(saved.match), history: normalizeTennisHistory(saved.history), player: normalizeTennisPlayer(saved.player) };
  } catch { return { match: null, history: [], player: null }; }
}
export default function App() {
  const [view, setView] = useState<"scorer" | "practice">("scorer");
  const [saved, setSaved] = useState(loadSaved);
  const [saveError, setSaveError] = useState(false);
  useEffect(() => {
    try { localStorage.setItem(storageKey, JSON.stringify(saved)); setSaveError(false); }
    catch { setSaveError(true); }
  }, [saved]);
  function changeMatch(match: TennisMatch | null) {
    setSaved(current => {
      let history = current.history;
      if (match) {
        history = history.filter(entry => entry.id !== match.id);
        if (match.winner !== null) history = [createHistoryEntry(match), ...history];
      }
      return { ...current, match, history };
    });
  }
  return <div className="site-shell">
    <header className="site-header"><a className="wordmark" href="/" aria-label="SwipeTennis home"><span className="brand-ball" aria-hidden="true"/>swipe<span>tennis</span><span className="brand-period">.</span></a><span className="header-note">A feel for every point.</span><a className="header-link" href="#scorer">{saved.match ? "Back to match" : "Play a match"} ↗</a></header>
    <nav className="mode-navigation" aria-label="Tennis activities"><button aria-pressed={view === "scorer"} onClick={() => setView("scorer")}>Match scorer</button><button aria-pressed={view === "practice"} onClick={() => setView("practice")}>Play & practice ↗</button></nav>
    {view === "scorer" && !saved.match && <section className="hero"><div className="hero-copy"><p className="eyebrow">THE COURT IS YOUR CANVAS</p><h1>Every point.<br/>A little <em>more felt.</em></h1><p className="hero-description">Trace the rally. Capture the score.<br/>Turn your time on court into a story you can replay.</p><a href="#scorer" className="hero-link">Make your next match count <span>↓</span></a></div><div className="court-art" aria-hidden="true"><div className="art-court"><div className="art-singles"/><div className="art-service"/><div className="art-net"/><div className="art-trace"/><span className="art-ball"/></div><span className="art-caption">LOVE THE GAME. REMEMBER THE MATCH.</span></div></section>}

    <main id="scorer"><div hidden={view !== "practice"}><PracticeCourt visible={view === "practice"} /></div><div hidden={view !== "scorer"}><TennisApp match={saved.match} history={saved.history} defaultPlayer={saved.player} onDefaultPlayerChange={player => setSaved(current => ({ ...current, player }))} onChange={changeMatch} onCancel={() => changeMatch(null)} /></div></main>
    <footer className="site-footer"><span>swipetennis<span className="brand-period">.</span></span><p role="status">{view === "practice" ? "Practice sessions stay in this tab." : saveError ? "Storage is full or unavailable. Keep this tab open to retain your match." : "Your matches are saved in this browser on this device."}</p><span>See you on court ↗</span></footer>
  </div>;
}
