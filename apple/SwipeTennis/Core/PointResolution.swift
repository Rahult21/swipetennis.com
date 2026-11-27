import Foundation

/// A completed point keeps its ball visible before the result card covers the court.
struct PointResolution: Codable {
  static let markerDuration = 0.3
  static let resultDelay = 0.75
  var elapsed = 0.0
  let impact: FaultImpact?
  let reaction: PointReaction?

  init(impact: FaultImpact?, reaction: PointReaction? = nil) {
    self.impact = impact
    self.reaction = reaction
  }
  var duration: Double { reaction?.duration ?? Self.resultDelay }

  var isWaiting: Bool { elapsed < duration - 0.000001 }
  var showsMarker: Bool { impact != nil && elapsed < Self.markerDuration - 0.000001 }
}

struct FaultImpact: Codable {
  let point: Vec
  let direction: Vec
  let speed: Double
  let isNet: Bool
  var height: Double { isNet ? 0.45 : 0 }

  init?(flight: BallFlight) {
    guard ["net", "wide", "long"].contains(flight.fault ?? "") else { return nil }
    point = flight.landing
    isNet = flight.fault == "net"
    let distance = max(0.001, flight.launchPosition.distance(to: flight.landing))
    direction = Vec(x: (flight.landing.x - flight.launchPosition.x) / distance,
      y: (flight.landing.y - flight.launchPosition.y) / distance)
    speed = distance / max(0.001, flight.duration * 0.8)
  }

  /// A net contact drops back on the hitter's side; an out bounce keeps travelling and slows.
  func ball(after elapsed: Double) -> (position: Vec, height: Double) {
    let t = clamp(elapsed, 0, PointResolution.resultDelay)
    if isNet {
      let recoil = 0.65 * (1 - exp(-t * 5))
      return (Vec(x: point.x + direction.x * recoil * 0.25,
        y: point.y - direction.y * recoil), max(0, height - 4.9 * t * t))
    }
    let airborne = min(t,0.55)
    let travel = min(speed*0.68,20)*(-expm1(-0.32*airborne)/0.32
      + 0.53*exp(-0.32*airborne)*(-expm1(-2.8*(t-airborne)))/2.8)
    let bounce = clamp(t / 0.55, 0, 1)
    return (CourtRunoff.afterPlay(Vec(x: point.x + direction.x * travel, y: point.y + direction.y * travel)),
      0.6 * 4 * bounce * (1 - bounce))
  }
}

extension PracticeEngine {
  var isResolvingPoint: Bool { pointResolution?.isWaiting == true }
  var needsSimulation: Bool { phase.isPlaying || isResolvingPoint }
  var showsPointResult: Bool { demo == nil && (phase == .point || phase == .finished) && !isResolvingPoint }
  var showsAffirmation: Bool {
    isResolvingPoint && pointResolution?.reaction?.affirmation != nil
  }

  /// A dead ball can still be chased while its out bounce is being shown.
  /// Scoring and shot selection stay closed; an affirmation keeps its tap-to-dismiss behavior.
  var acceptsCourtMovement: Bool {
    phase.isPlaying || (isResolvingPoint && !showsAffirmation
      && ["wide", "long"].contains(flight?.fault ?? ""))
  }

  func outBallChaseTarget(_ side: Int) -> Vec? {
    guard side == 0 || settings.local, acceptsCourtMovement,
      let flight, flight.hitter != side, ["wide", "long"].contains(flight.fault ?? "") else { return nil }
    return Self.own(side, flight.contact)
  }

  @discardableResult
  mutating func dismissAffirmation() -> Bool {
    guard showsAffirmation, var resolution = pointResolution else { return false }
    resolution.elapsed = resolution.duration
    pointResolution = resolution
    if flight != nil { ball = worldBall.courtPosition }
    return true
  }

  mutating func stepPointResolution(_ dt: Double) {
    guard var resolution = pointResolution, resolution.isWaiting else { return }
    resolution.elapsed = min(resolution.duration, resolution.elapsed + dt)
    pointResolution = resolution
    if flight != nil { ball = worldBall.courtPosition }
    updateFootwork(dt)
    if phase == .serveFault && !resolution.isWaiting { prepareSecondServe() }
  }
}
