export type Side = 0 | 1;
export type Difficulty = "easy" | "medium" | "tough";
export type Profile =
  | "baseline"
  | "aggressive"
  | "volley"
  | "allcourt"
  | "retriever";
export type Vec = { x: number; y: number };
export type ShotKind = "cross" | "line" | "angle" | "lob";
export const COURT = { width: 8.23, length: 23.77, net: 11.885 };
export const LEVELS = {
  easy: {
    accuracy: 1,
    reaction: 0.52,
    speed: 0.9,
    botAccuracy: 0.92,
    riskPenalty: 0.22,
    pace: 0.92,
  },
  medium: {
    accuracy: 0.9,
    reaction: 0.32,
    speed: 1,
    botAccuracy: 0.96,
    riskPenalty: 0.17,
    pace: 1,
  },
  tough: {
    accuracy: 0.8,
    reaction: 0.19,
    speed: 1.07,
    botAccuracy: 0.98,
    riskPenalty: 0.12,
    pace: 1.08,
  },
};
export const PROFILES = {
  baseline: {
    name: "Baseline",
    description:
      "Steady depth. Crosscourt patterns. Recovers behind the baseline.",
    speed: 5.3,
    pace: 1,
    risk: 0.12,
    depth: 1.5,
    loft: 1,
  },
  aggressive: {
    name: "Aggressive baseliner",
    description: "Takes time away, changes direction, and attacks the corners.",
    speed: 5.6,
    pace: 1.22,
    risk: 0.58,
    depth: 0.7,
    loft: 0.8,
  },
  volley: {
    name: "Serve and volley",
    description:
      "Follows the serve forward, closes the net, and looks for volleys.",
    speed: 5.5,
    pace: 1.1,
    risk: 0.36,
    depth: 3,
    loft: 0.8,
  },
  allcourt: {
    name: "All-court player",
    description: "Builds from the baseline and approaches behind a short ball.",
    speed: 5.7,
    pace: 1.08,
    risk: 0.3,
    depth: 1.8,
    loft: 1,
  },
  retriever: {
    name: "Retriever",
    description:
      "Runs down width, uses height and depth, and waits for an opening.",
    speed: 6.1,
    pace: 0.82,
    risk: 0.06,
    depth: 1.6,
    loft: 1.7,
  },
};
export type Settings = {
  mode: "bot" | "local";
  profile: Profile;
  difficulty: Difficulty;
};
export type Player = {
  pos: Vec;
  destination: Vec;
  velocity: Vec;
  settled: number;
  aim: Vec | null;
  kind: ShotKind;
};
export type Flight = {
  from: Vec;
  landing: Vec;
  contact: Vec;
  elapsed: number;
  duration: number;
  hitter: Side;
  red: boolean;
  fault: string | null;
  explanation: string;
  loft: number;
  serve: boolean;
};
export type Feedback = {
  title: string;
  reason: string;
  tip: string;
  tone: "positive" | "neutral" | "risk";
};
export type Practice = {
  settings: Settings;
  players: [Player, Player];
  score: [number, number];
  server: Side;
  phase: "ready" | "live" | "point" | "finished";
  flight: Flight | null;
  ball: Vec;
  rally: number;
  time: number;
  reactAt: number;
  approach: boolean;
  feedback: Feedback;
  lastContact: string;
  history: Feedback[];
  balanced: [number, number];
  attempts: [number, number];
};
export const other = (side: Side): Side => (side === 0 ? 1 : 0);
export const distance = (a: Vec, b: Vec) => Math.hypot(a.x - b.x, a.y - b.y);
const clamp = (n: number, low: number, high: number) =>
  Math.max(low, Math.min(high, n));
export function ownPosition(side: Side, p: Vec): Vec {
  return {
    x: clamp(p.x, -1.6, COURT.width + 1.6),
    y:
      side === 0
        ? clamp(p.y, COURT.net + 0.7, COURT.length + 2.5)
        : clamp(p.y, -2.5, COURT.net - 0.7),
  };
}
export function aimPosition(side: Side, p: Vec): Vec {
  return {
    x: clamp(p.x, 0.15, COURT.width - 0.15),
    y:
      side === 0
        ? clamp(p.y, 0.15, COURT.net - 0.5)
        : clamp(p.y, COURT.net + 0.5, COURT.length - 0.15),
  };
}
export function redZone(p: Vec) {
  const edge = Math.min(p.x, COURT.width - p.x);
  const baseline = Math.min(p.y, COURT.length - p.y);
  return (
    edge < 0.85 || baseline < 0.8 || (Math.abs(p.y - COURT.net) < 5 && edge < 2)
  );
}
export function recoverySpot(side: Side, opponentContact: Vec): Vec {
  // Bisect the two available baseline angles, rather than always chasing centre.
  const baselineY = side === 0 ? COURT.length : 0;
  const leftAngle = Math.atan2(
    -opponentContact.x,
    Math.abs(baselineY - opponentContact.y),
  );
  const rightAngle = Math.atan2(
    COURT.width - opponentContact.x,
    Math.abs(baselineY - opponentContact.y),
  );
  const x =
    opponentContact.x +
    Math.tan((leftAngle + rightAngle) / 2) *
      Math.abs(baselineY - opponentContact.y);
  return {
    x: clamp(x, 2.4, COURT.width - 2.4),
    y: side === 0 ? COURT.length + 0.8 : -0.8,
  };
}
export function createPractice(settings: Settings): Practice {
  const player = (y: number): Player => ({
    pos: { x: 4.115, y },
    destination: { x: 4.115, y },
    velocity: { x: 0, y: 0 },
    settled: 0,
    aim: null,
    kind: "cross",
  });
  return {
    settings,
    players: [player(24.6), player(-0.8)],
    score: [0, 0],
    server: 1,
    phase: "ready",
    flight: null,
    ball: { x: 4.115, y: -0.8 },
    rally: 0,
    time: 0,
    reactAt: 0,
    approach: false,
    lastContact: "Get ready",
    history: [],
    balanced: [0, 0],
    attempts: [0, 0],
    feedback: {
      title: "Read. Move. Settle.",
      reason:
        "Move toward the landing marker early, then give yourself room to stop before contact.",
      tip: "After hitting, recover toward the dashed coverage circle. Your shot is played automatically when the ball reaches you.",
      tone: "neutral",
    },
  };
}
export function presetAim(side: Side, kind: ShotKind, position: Vec): Vec {
  const oppositeX = position.x < COURT.width / 2 ? COURT.width - 1.4 : 1.4;
  const x =
    kind === "line"
      ? clamp(position.x, 0.5, COURT.width - 0.5)
      : kind === "angle"
        ? oppositeX < 4
          ? 0.55
          : COURT.width - 0.55
        : oppositeX;
  const depth = kind === "angle" ? 8.4 : kind === "lob" ? 2.2 : 1.8;
  return { x, y: side === 0 ? depth : COURT.length - depth };
}
export function movePlayer(player: Player, dt: number, maxSpeed: number) {
  const d = distance(player.pos, player.destination);
  const targetSpeed = Math.min(maxSpeed, Math.sqrt(2 * 11 * d));
  const desired =
    d > 0.02
      ? {
          x: ((player.destination.x - player.pos.x) / d) * targetSpeed,
          y: ((player.destination.y - player.pos.y) / d) * targetSpeed,
        }
      : { x: 0, y: 0 };
  const delta = distance(player.velocity, desired);
  const fraction = delta > 0 ? Math.min(1, (11 * dt) / delta) : 1;
  player.velocity.x += (desired.x - player.velocity.x) * fraction;
  player.velocity.y += (desired.y - player.velocity.y) * fraction;
  player.pos.x += player.velocity.x * dt;
  player.pos.y += player.velocity.y * dt;
}
export function contactChance(
  difficulty: Difficulty,
  settled: number,
  gap: number,
  speed: number,
  risky: boolean,
) {
  if (gap > 1.35) return 0;
  if (gap <= 0.85 && settled >= 0.18 && speed < 2.2)
    return LEVELS[difficulty].accuracy;
  const stretchPenalty = Math.max(0, gap - 0.6) * 0.3;
  return clamp(
    LEVELS[difficulty].accuracy -
      0.22 -
      stretchPenalty -
      (speed > 3 ? 0.13 : 0) -
      (risky ? 0.14 : 0),
    0.12,
    0.78,
  );
}
export function flightPosition(f: Flight): Vec {
  const t = Math.min(1, f.elapsed / f.duration);
  if (t < 0.8)
    return {
      x: f.from.x + ((f.landing.x - f.from.x) * t) / 0.8,
      y: f.from.y + ((f.landing.y - f.from.y) * t) / 0.8,
    };
  return {
    x: f.landing.x + ((f.contact.x - f.landing.x) * (t - 0.8)) / 0.2,
    y: f.landing.y + ((f.contact.y - f.landing.y) * (t - 0.8)) / 0.2,
  };
}
function botAim(s: Practice, random: () => number): Vec {
  const profile = PROFILES[s.settings.profile];
  const opponent = s.players[0].pos;
  const openX = opponent.x < 4.115 ? COURT.width - 0.5 : 0.5;
  const attacking = random() < profile.risk;
  let x = attacking ? openX : s.players[1].pos.x < 4.115 ? 6.6 : 1.6;
  let depth = profile.depth;
  if (s.settings.profile === "retriever")
    x = clamp(8.23 - opponent.x, 1.5, 6.73);
  if (s.approach && s.players[1].pos.y > 5) {
    x = openX;
    depth = 5;
  }
  return {
    x: clamp(x + (random() - 0.5) * 0.5, 0.2, 8.03),
    y: COURT.length - depth,
  };
}
function endPoint(s: Practice, winner: Side, feedback: Feedback) {
  s.score[winner]++;
  s.feedback = feedback;
  s.history = [feedback, ...s.history].slice(0, 8);
  s.phase =
    s.score[winner] >= 7 && s.score[winner] - s.score[other(winner)] >= 2
      ? "finished"
      : "point";
}
export function playerName(s: Practice, side: Side) {
  return side === 0
    ? s.settings.mode === "local"
      ? "Player 1"
      : "You"
    : s.settings.mode === "local"
      ? "Player 2"
      : PROFILES[s.settings.profile].name;
}
function launch(
  s: Practice,
  hitter: Side,
  aim: Vec,
  kind: ShotKind,
  fault: string | null,
  explanation: string,
  serve = false,
) {
  const bot = hitter === 1 && s.settings.mode === "bot";
  const from = { ...s.players[hitter].pos };
  const red = redZone(aim);
  const landing = { ...aim };
  if (fault === "wide") landing.x = aim.x < 4.115 ? -0.5 : 8.73;
  if (fault === "long") landing.y = hitter === 0 ? -0.6 : COURT.length + 0.6;
  if (fault === "net") landing.y = COURT.net + (hitter === 0 ? 0.25 : -0.25);
  const contact = {
    x: landing.x,
    y: landing.y + (hitter === 0 ? -1 : 1) * (kind === "angle" ? 0.45 : 1.1),
  };
  if (serve) {
    contact.y = hitter === 0 ? 0.3 : COURT.length - 0.3;
    contact.x =
      from.x +
      ((landing.x - from.x) * (contact.y - from.y)) / (landing.y - from.y);
  }
  const profile = PROFILES[s.settings.profile];
  const pace = bot ? profile.pace * LEVELS[s.settings.difficulty].pace : 1;
  const loft = kind === "lob" ? 2.5 : bot ? profile.loft : 1;
  const duration = clamp(
    distance(from, landing) / (15 * pace) + 0.35 + (loft - 1) * 0.45,
    0.85,
    2.65,
  );
  s.flight = {
    from,
    landing,
    contact,
    elapsed: 0,
    duration,
    hitter,
    red,
    fault,
    explanation,
    loft,
    serve,
  };
  s.ball = from;
  s.players[other(hitter)].settled = 0;
  s.reactAt = s.time + LEVELS[s.settings.difficulty].reaction;
  s.rally++;
  if (bot) {
    s.approach =
      s.settings.profile === "volley" ||
      (s.settings.profile === "allcourt" && from.y > 3);
    s.players[1].destination = s.approach
      ? { x: clamp(aim.x, 2, 6.23), y: 8 }
      : recoverySpot(1, contact);
    if (s.settings.profile === "retriever") s.players[1].destination.y = -1.7;
  }
}
export function startPoint(s: Practice) {
  if (s.phase === "finished" || s.phase === "live") return;
  s.server = (s.score[0] + s.score[1]) % 2 === 0 ? 1 : 0;
  s.players.forEach((p, side) => {
    p.pos = { x: 4.115, y: side === 0 ? 24.6 : -0.8 };
    p.destination = { ...p.pos };
    p.velocity = { x: 0, y: 0 };
    p.settled = 0;
    p.aim = null;
  });
  s.rally = 0;
  s.approach = false;
  s.phase = "live";
  s.lastContact = "Opening serve";
  // A repeatable legal serve starts each point so the exercise stays about footwork.
  launch(
    s,
    s.server,
    { x: s.server === 1 ? 2.5 : 5.73, y: s.server === 1 ? 17.2 : 6.57 },
    "cross",
    null,
    "",
    true,
  );
  s.feedback = {
    title: "Find the bounce early.",
    reason:
      "The small ring marks where you can meet the ball after its bounce. Move there, slow down, and prepare your shot.",
    tip: "You can change your aim before contact. A quick swipe changes your target, never your running speed.",
    tone: "neutral",
  };
}
export function interceptPoint(s: Practice, side: Side): Vec {
  const f = s.flight!;
  const p = s.players[side].pos;
  const nearNet = side === 0 ? p.y < 19 : p.y > 4.77;
  if (nearNet && !f.serve && f.loft < 2) {
    const denominator = f.landing.y - f.from.y;
    const t = (p.y - f.from.y) / denominator;
    if (t > 0 && t < 1)
      return { x: f.from.x + (f.landing.x - f.from.x) * t, y: p.y };
  }
  return f.contact;
}
function returnBall(
  s: Practice,
  side: Side,
  volley: boolean,
  random: () => number,
) {
  const p = s.players[side];
  const incoming = s.flight!;
  const contact = volley ? s.ball : incoming.contact;
  const gap = distance(p.pos, contact);
  const speed = Math.hypot(p.velocity.x, p.velocity.y);
  const bot = side === 1 && s.settings.mode === "bot";
  const aim = bot ? botAim(s, random) : p.aim || presetAim(side, p.kind, p.pos);
  const risk = redZone(aim);
  const balanced = gap <= 0.85 && p.settled >= 0.18 && speed < 2.2;
  s.attempts[side]++;
  if (balanced) s.balanced[side]++;
  let chance = contactChance(
    s.settings.difficulty,
    p.settled,
    gap,
    speed,
    risk,
  );
  if (bot) {
    const level = LEVELS[s.settings.difficulty];
    chance = balanced
      ? level.botAccuracy - (risk ? level.riskPenalty : 0)
      : Math.min(0.78, chance);
  }
  const miss = random() >= chance;
  const actor = playerName(s, side);
  const reason = balanced
    ? `${actor} arrived early and balanced.`
    : gap > 0.85
      ? `Contact was stretched, ${gap.toFixed(1)} m from the ball.`
      : speed >= 2.2
        ? `${actor} ${side === 0 && s.settings.mode === "bot" ? "were" : "was"} still moving through contact.`
        : `${actor} arrived too late to set the feet.`;
  s.lastContact = `${playerName(s, side)} · ${balanced ? "Balanced" : "Rushed"}${volley ? " volley" : ""}`;
  p.aim = null;
  let fault: string | null = null;
  if (miss)
    fault = risk
      ? Math.min(aim.x, 8.23 - aim.x) < 1
        ? "wide"
        : "long"
      : speed > 3
        ? "net"
        : "long";
  const explanation = balanced
    ? `Balanced contact. This was a timing error within the ${Math.round((1 - chance) * 100)}% miss chance for this shot.`
    : `${reason} The available shot margin fell to ${Math.round(chance * 100)}%.`;
  s.feedback = {
    title: balanced
      ? "Early feet. Quiet contact."
      : "Give yourself a little more time.",
    reason,
    tip: risk
      ? "You chose a red-zone target. A rushed contact leaves very little margin."
      : "Recover toward the coverage circle as your opponent prepares.",
    tone: balanced ? "positive" : "neutral",
  };
  const kind = bot && s.settings.profile === "retriever" ? "lob" : p.kind;
  launch(s, side, aim, kind, fault, explanation);
}
export function stepPractice(
  s: Practice,
  dt: number,
  random: () => number = Math.random,
) {
  if (s.phase !== "live" || !s.flight) return;
  dt = Math.min(0.04, Math.max(0, dt));
  s.time += dt;
  const f = s.flight;
  const receiver = other(f.hitter);
  if (s.settings.mode === "bot" && receiver === 1 && s.time >= s.reactAt) {
    s.players[1].destination = ownPosition(1, interceptPoint(s, 1));
  }
  s.players.forEach((p, i) => {
    const maxSpeed =
      i === 1 && s.settings.mode === "bot"
        ? PROFILES[s.settings.profile].speed *
          LEVELS[s.settings.difficulty].speed
        : 6;
    movePlayer(p, dt, maxSpeed);
    p.pos = ownPosition(i as Side, p.pos);
    const target = interceptPoint(s, i as Side);
    p.settled =
      distance(p.pos, target) <= 0.85 &&
      Math.hypot(p.velocity.x, p.velocity.y) < 2.2
        ? p.settled + dt
        : 0;
  });
  f.elapsed += dt;
  s.ball = flightPosition(f);
  const progress = f.elapsed / f.duration;
  if (f.fault && progress >= 0.8) {
    const opponentMiss = f.hitter === 1;
    const goodRisk = f.red && f.explanation.startsWith("Balanced");
    endPoint(s, receiver, {
      title: `${playerName(s, f.hitter)} missed ${f.fault}.`,
      reason: f.explanation,
      tip:
        opponentMiss && f.red
          ? "A good miss to draw out. You made the opponent play a high-risk red-zone shot. Accept the occasional winner there; that risk can pay you back later."
          : goodRisk
            ? "A good miss in execution. You were balanced and committed to your target. Give the line more space next time."
            : f.red
              ? "The target was in the red zone. When stretched, choose a higher-margin ball through the middle and recover."
              : "Read the direction sooner, move before the bounce, then brake before contact.",
      tone: (opponentMiss && f.red) || goodRisk ? "positive" : "neutral",
    });
    return;
  }
  const ballOnReceiverSide =
    receiver === 0 ? s.ball.y > COURT.net + 0.8 : s.ball.y < COURT.net - 0.8;
  // Volleys happen before the bounce; lobs pass above volley reach.
  if (
    !f.fault &&
    !f.serve &&
    f.loft < 2 &&
    progress < 0.76 &&
    ballOnReceiverSide &&
    distance(s.players[receiver].pos, s.ball) < 0.9
  ) {
    returnBall(s, receiver, true, random);
    return;
  }
  if (progress < 1) return;
  const gap = distance(s.players[receiver].pos, f.contact);
  if (gap > 1.35) {
    const riskyWinner =
      f.red && (f.hitter === 1 || s.settings.mode === "local");
    endPoint(s, f.hitter, {
      title: `${playerName(s, f.hitter)} wins the point.`,
      reason: `${playerName(s, receiver)} finished ${gap.toFixed(1)} m from the contact point, beyond the 1.35 m reach. ${s.players[receiver].pos.y < 19 && receiver === 0 && f.loft >= 2 ? "The lob went over your net position." : "The ball arrived before the player could get there."}`,
      tip: riskyWinner
        ? `Good tactical concession for ${playerName(s, receiver).toLowerCase()}. ${playerName(s, f.hitter)} made a red-zone winner. The coverage asked for a high-risk shot; accept this one and keep asking for that precision.`
        : "Recover toward the angle-bisecting circle, split-step as the opponent hits, and move toward the new landing marker early.",
      tone: riskyWinner ? "positive" : "neutral",
    });
    return;
  }
  returnBall(s, receiver, false, random);
}
