export type RuleCourtPoint = { x: number; y: number };
export type ServeAttempt = 1 | 2;

export const TENNIS_COURT = {
  singlesLeft: 12,
  singlesRight: 88,
  topBaseline: 8,
  bottomBaseline: 152,
  topServiceLine: 45,
  net: 80,
} as const;

const LINE_TOLERANCE = 1.25;

export function courtSide(point: RuleCourtPoint) {
  return point.y < TENNIS_COURT.net ? "top" : "bottom";
}

function within(value: number, start: number, end: number) {
  return value >= start - LINE_TOLERANCE && value <= end + LINE_TOLERANCE;
}

export function isSinglesLanding(point: RuleCourtPoint) {
  return within(point.x, TENNIS_COURT.singlesLeft, TENNIS_COURT.singlesRight)
    && within(point.y, TENNIS_COURT.topBaseline, TENNIS_COURT.bottomBaseline);
}

export type ServeLandingResult = {
  valid: boolean;
  reason: "legal" | "net" | "long" | "wide" | "wrong-box";
};

export function validateServeLanding(point: RuleCourtPoint, serveFromRight: boolean): ServeLandingResult {
  if (courtSide(point) !== "top") return { valid: false, reason: "net" };
  if (point.y < TENNIS_COURT.topServiceLine - LINE_TOLERANCE) return { valid: false, reason: "long" };
  if (point.y > TENNIS_COURT.net + LINE_TOLERANCE) return { valid: false, reason: "net" };
  if (!within(point.x, TENNIS_COURT.singlesLeft, TENNIS_COURT.singlesRight)) return { valid: false, reason: "wide" };

  const correctHalf = serveFromRight
    ? within(point.x, TENNIS_COURT.singlesLeft, 50)
    : within(point.x, 50, TENNIS_COURT.singlesRight);
  return correctHalf ? { valid: true, reason: "legal" } : { valid: false, reason: "wrong-box" };
}

export function selectServeLanding(pausedLanding: RuleCourtPoint, fingerUp: RuleCourtPoint, capturedLandingCount: number) {
  const fingerUpIsServiceDepth = courtSide(fingerUp) === "top" && fingerUp.y >= TENNIS_COURT.topServiceLine - LINE_TOLERANCE;
  return capturedLandingCount === 1 && fingerUpIsServiceDepth ? fingerUp : pausedLanding;
}

export function classifyServe(attempt: ServeAttempt, point: RuleCourtPoint, serveFromRight: boolean) {
  const landing = validateServeLanding(point, serveFromRight);
  if (landing.valid) return { kind: "legal" as const, reason: landing.reason };
  return { kind: attempt === 1 ? "first-fault" as const : "double-fault" as const, reason: landing.reason };
}

export function classifyFinalShot(finalShotIndex: number, landing: RuleCourtPoint, forcedByPreviousShot: boolean) {
  if (isSinglesLanding(landing)) {
    return { winner: "hitter" as const, outcome: finalShotIndex === 1 ? "Return winner" : "Winner" };
  }
  if (finalShotIndex === 1) return { winner: "opponent" as const, outcome: "Return error" };
  return { winner: "opponent" as const, outcome: forcedByPreviousShot ? "forced error" : "unforced error" };
}
