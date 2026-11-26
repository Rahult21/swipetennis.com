import Foundation
import simd

/// Step out with the travel-side foot, then bring the pushing foot back underneath the hips.
struct CourtFootwork {
  private(set) var left = CourtPoint3D.zero
  private(set) var right = CourtPoint3D.zero
  private var previous: CourtPoint3D?
  private var leftSwings = false
  private var stepping = false
  private var replanting = false
  private var lateralDirection: Float = 0
  private var liftOff = CourtPoint3D.zero
  private var touchdown = CourtPoint3D.zero
  private var progress: Float = 0
  private var length: Float = 0.4

  mutating func advance(centre: CourtPoint3D, velocity: CourtPoint3D, destination: CourtPoint3D,
    facing: Float, strideBias: CourtPoint3D, dt: Float, readiness: Float = 1, surface: CourtSurface = .hard) {
    let base = CourtPoint3D((0.175 + 0.070 * readiness) * facing, 0, (0.025 + 0.03 * readiness) * facing)
    guard let last = previous, simd_distance(centre, last) < 1.8 else {
      previous = centre; left = centre - base; right = centre + base
      stepping = false; replanting = false; lateralDirection = 0
      return
    }
    previous = centre
    let speed = simd_length(velocity)
    let travel = simd_distance(centre, last)
    let remaining = simd_distance(destination, centre)
    let lateral = abs(velocity.x) > max(0.09, abs(velocity.z) * 1.1)
    let direction: Float = lateral ? (velocity.x * facing > 0 ? 1 : -1) : 0
    if !stepping {
      let moving = speed > 0.12 && remaining > 0.04
      length = lateral ? min(0.40, 0.16 + speed * 0.055) : min(0.70, 0.21 + speed * 0.072)
      if surface == .grass { length *= 0.84 }
      let lead = moving ? velocity / speed * min(remaining, length * 1.15) : .zero
      let goals = (left: centre - base + lead + strideBias, right: centre + base + lead)
      let leftGap = simd_distance(left, goals.left), rightGap = simd_distance(right, goals.right)
      guard max(leftGap, rightGap) > (moving ? 0.085 : 0.04 + 0.075 * readiness) else {
        if !moving { lateralDirection = 0 }
        return
      }
      if direction != 0 && direction != lateralDirection { leftSwings = direction < 0 }
      else if !moving { leftSwings = leftGap > rightGap }
      lateralDirection = direction
      liftOff = leftSwings ? left : right
      touchdown = leftSwings ? goals.left : goals.right
      if lateral {
        // A closing foot must leave space under the body. It cannot pass the planted shoe.
        let plantedX = (leftSwings ? right.x : left.x) * facing
        let x = touchdown.x * facing
        touchdown.x = (leftSwings ? min(x, plantedX - 0.245) : max(x, plantedX + 0.245)) * facing
      }
      progress = 0; stepping = true; replanting = false
    }
    let reversing = lateral && lateralDirection != 0 && direction != lateralDirection
    if reversing && !replanting {
      // Brake an airborne shoe where it is. The new lead steps out after it lands.
      liftOff = leftSwings ? left : right
      touchdown = [liftOff.x,0,liftOff.z]
      replanting = true; progress = 0
    }
    progress = min(1, progress + (replanting ? dt / 0.065 : max(travel / length, dt * 6)))
    let u = progress * progress * (3 - 2 * progress)
    var shoe = liftOff + (touchdown - liftOff) * u
    if surface == .clay && lateral && speed > 2.6 && remaining < 1.7 && !replanting {
      // The planted outside shoe slides with the body during deceleration.
      let slide = (centre-last)*0.54
      if leftSwings { right += slide } else { left += slide }
    }
    if !replanting { shoe.y = (0.055 + min(speed, 6) * (lateral ? 0.010 : 0.025)) * sin(progress * .pi) }
    if leftSwings { left = shoe } else { right = shoe }
    if progress >= 1 {
      if leftSwings { left = touchdown } else { right = touchdown }
      leftSwings.toggle(); stepping = false
    }
  }
}
