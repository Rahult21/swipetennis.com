import Foundation
import simd

/// Court coordinates in metres: x runs across the court, y is height, z runs toward the near baseline.
typealias CourtPoint3D = SIMD3<Float>

extension Vec {
  func world(height: Float = 0) -> CourtPoint3D {
    CourtPoint3D(Float(x), height, Float(y))
  }
}

func serviceImpact(at feet: Vec, side: Int, explosive: Bool) -> CourtPoint3D {
  let facing: Float = side == 0 ? 1 : -1
  return feet.world() + CourtPoint3D(0.35 * facing, explosive ? 2.88 : 2.73, -0.32 * facing)
}

extension BallFlight {
  func worldBall(at progress: Double) -> CourtPoint3D {
    let start = strikeOrigin ?? from.world(height: serve ? 2.73 : 0.93)
    let ground = landing.world(height: fault == "net" ? 0.45 : 0)
    if progress <= 0.8 {
      let t = Float(clamp(progress / 0.8, 0, 1))
      var point = start + (ground - start) * t
      point.y += sin(t * .pi) * Float(loft) * 1.7
      return point
    }
    let t = Float(clamp((progress - 0.8) / 0.2, 0, 1))
    var point = ground + (contact.world() - ground) * t
    if power == .overhead { point.y = 5.5 * sin(t * .pi / 2) }
    else if kind == .drop { point.y = 0.28 * 4 * t * (1 - t) }
    else {
      let kick = Float(serveProfile?.kick ?? 1) * (power == .ace ? 1.25 : 1)
      point.y = sin(t * .pi / 2) * (kind == .slice ? 0.54 : 1.14) * kick
    }
    return point
  }
}

extension PracticeEngine {
  var worldBall: CourtPoint3D {
    if let resolution = pointResolution, let impact = resolution.impact {
      let rebound = impact.ball(after: resolution.elapsed)
      return rebound.position.world(height: Float(rebound.height))
    }
    if let serve = servePreparation, phase == .serving {
      let feet = players[serve.server].pos
      return ServiceToss.ball(feet:feet,side:serve.server,progress:Float(serve.tossProgress ?? 0),explosive:queuedPower == .ace)
    }
    return flight.map { $0.worldBall(at: $0.progress) } ?? ball.world()
  }
}
