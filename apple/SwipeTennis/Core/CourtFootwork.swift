import Foundation
import simd

/// Alternating stance and swing feet. A planted shoe stays in court coordinates until its next step.
struct CourtFootwork {
  private(set) var left = CourtPoint3D.zero
  private(set) var right = CourtPoint3D.zero
  private var previous: CourtPoint3D?
  private var leftSwings = false
  private var stepping = false
  private var liftOff = CourtPoint3D.zero
  private var touchdown = CourtPoint3D.zero
  private var progress: Float = 0
  private var length: Float = 0.4

  mutating func advance(centre: CourtPoint3D, velocity: CourtPoint3D, destination: CourtPoint3D,
    facing: Float, strideBias: CourtPoint3D, dt: Float) {
    let base = CourtPoint3D(0.23 * facing, 0, 0.06 * facing)
    guard let last = previous, simd_distance(centre, last) < 1.8 else {
      previous = centre; left = centre - base; right = centre + base; stepping = false
      return
    }
    let travel = simd_distance(centre, last)
    previous = centre
    let speed = simd_length(velocity)
    let distance = simd_distance(destination, centre)
    let sprint = min(1, max(0, (speed - 2) / 3))
    let lateral = abs(velocity.x) > abs(velocity.z)
    let adjustment = distance < 0.9 && speed < 3
    let lookAhead: Float = adjustment ? 0.065 : lateral && speed < 3 ? 0.09 : 0.13
    let lead = velocity * min(lookAhead, distance / max(0.01, speed))
    let stance = base + CourtPoint3D(0.05 * facing * (lateral ? 1 : 0), 0, 0)
    let leftGoal = centre - stance + lead + strideBias
    let rightGoal = centre + stance + lead
    if !stepping {
      let leftGap = simd_distance(left, leftGoal), rightGap = simd_distance(right, rightGoal)
      guard max(leftGap, rightGap) > (speed < 0.3 ? 0.16 : 0.10) else { return }
      if abs(leftGap - rightGap) > 0.32 || speed < 0.3 { leftSwings = leftGap > rightGap }
      liftOff = leftSwings ? left : right
      touchdown = leftSwings ? leftGoal : rightGoal
      length = adjustment ? 0.26 : 0.31 + sprint * 0.62
      progress = 0; stepping = true
    }
    // Distance drives cadence; a final adjustment can finish after the body has braked.
    progress = min(1, progress + max(travel / length, dt * (adjustment ? 5 : 3.6)))
    let u = progress * progress * (3 - 2 * progress)
    var shoe = liftOff + (touchdown - liftOff) * u
    shoe.y = (0.065 + sprint * 0.13) * sin(progress * .pi)
    if leftSwings { left = shoe } else { right = shoe }
    if progress >= 1 {
      if leftSwings { left = touchdown } else { right = touchdown }
      leftSwings.toggle(); stepping = false
    }
  }
}
