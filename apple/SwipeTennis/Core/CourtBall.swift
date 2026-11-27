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

extension SIMD3 where Scalar == Float {
  var courtPosition: Vec { Vec(x: Double(x), y: Double(z)) }
}

extension Vec {
  /// Continue the strike-to-bounce bearing to a given court depth.
  func projected(from origin: Vec, toDepth depth: Double) -> Vec {
    let dz = y-origin.y
    guard abs(dz) > 0.00001 else { return self }
    return Vec(x: x+(depth-y)*(x-origin.x)/dz, y: depth)
  }
}

/// Inside faces of the padded court perimeter in the 3D stadium (metres).
/// A dead ball can carry deep into the run-off and lose speed against a pad.
enum CourtRunoff {
  static let side: ClosedRange<Double> = -10.84...19.07
  static let depth: ClosedRange<Double> = -9.82...33.59

  static func afterPlay(_ position: Vec) -> Vec {
    func rebound(_ value: Double, within limits: ClosedRange<Double>) -> Double {
      if value < limits.lowerBound { return limits.lowerBound+0.25*(limits.lowerBound-value) }
      if value > limits.upperBound { return limits.upperBound-0.25*(value-limits.upperBound) }
      return value
    }
    return Vec(x:rebound(position.x,within:side),y:rebound(position.y,within:depth))
  }
}

extension BallFlight {
  var launchPoint: CourtPoint3D { strikeOrigin ?? from.world(height: serve ? 2.73 : 0.93) }
  var launchPosition: Vec { strikeOrigin?.courtPosition ?? from }

  /// The return window ends here. Older saved flights sometimes stored an
  /// endpoint straight ahead of the bounce even on a diagonal shot.
  var reboundEnd: Vec {
    if power != nil && power != .ace { return landing.projected(from:launchPosition,toDepth:contact.y) }
    if serve {
      let depth = hitter == 0 ? min(-0.45,contact.y) : max(PracticeEngine.length+0.45,contact.y)
      return landing.projected(from:launchPosition,toDepth:depth)
    }
    let dx = landing.x-launchPosition.x, dz = landing.y-launchPosition.y
    let distance = hypot(dx,dz)
    guard distance > 0.00001 else { return landing }
    // A short angle can travel almost parallel to the net. Limit the return
    // window by distance along the shot before it runs off the side of court.
    // End the ordinary swing window slightly in front of the receiver’s feet.
    // Placing a footwork marker farther back must not speed up the rebound.
    let depth = reboundDepth ?? abs(contact.y-landing.y)
    let travel = min(depth*1.35,depth*distance/max(0.00001,abs(dz)))
    return Vec(x:landing.x+travel*dx/distance,y:landing.y+travel*dz/distance)
  }

  var reboundDuration: Double {
    let ordinary = max(0.001,0.2*duration)
    // A power shot can travel from midcourt through the baseline after it
    // lands. Give that distance real time, including the kick of a wide ace.
    if power != nil {
      let incidentSpeed = launchPosition.distance(to:landing)/max(0.001,duration*0.8)
      let exitSpeed = min(25,max(3,incidentSpeed*(power == .overhead ? 0.88 : 0.78)))
      return max(ordinary,landing.distance(to:reboundEnd)/exitSpeed)
    }
    return ordinary
  }

  func time(at progress: Double) -> Double {
    progress <= 0.8 ? progress*duration : 0.8*duration+(progress-0.8)/0.2*reboundDuration
  }

  func courtPosition(at progress: Double) -> Vec {
    let before = progress <= 0.8
    let a = before ? launchPosition : landing, b = before ? landing : reboundEnd
    let t = clamp(before ? progress/0.8 : (progress-0.8)/0.2,0,1)
    if t == 1 { return b }
    return Vec(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t)
  }

  func altitude(at progress: Double) -> Double {
    if progress <= 0.8 {
      let t = clamp(progress/0.8,0,1), ground: Double = fault == "net" ? 0.45 : 0
      return Double(launchPoint.y)*(1-t)+ground*t+sin(t * .pi)*loft*1.7
    }
    let t = clamp((progress-0.8)/0.2,0,1)
    if power == .overhead { return 5.5*sin(t * .pi/2) }
    if kind == .drop { return 0.28*4*t*(1-t) }
    let kick = (serveProfile?.kick ?? 1)*(power == .ace ? 1.25 : 1)
    return sin(t * .pi/2)*(kind == .slice ? 0.54 : 1.14)*kick
  }

  func worldBall(at progress: Double) -> CourtPoint3D {
    courtPosition(at: progress).world(height: Float(altitude(at: progress)))
  }

  /// Continue from the last reachable ball. Normal drives crest near the
  /// return window, then descend, bounce again and lose horizontal speed.
  func runout(after elapsed: Double) -> CourtPoint3D {
    let t = clamp(elapsed,0,PointResolution.resultDelay)
    let end = reboundEnd, h = max(0,altitude(at: 1))
    let fallTime = sqrt(2*h/9.81), first = min(t,fallTime), after = max(0,t-first)
    let rebound = after*max(0,4.0*fallTime-4.905*after)
    let height = max(0,h-4.905*first*first)+rebound
    let groundSpeed = kind == .drop ? 0.17 : 0.64
    let travelTime = -expm1(-0.22*first)/0.22
      + groundSpeed*exp(-0.22*first)*(-expm1(-2.8*after))/2.8
    let scale = travelTime/reboundDuration
    let position = Vec(x:end.x+(end.x-landing.x)*scale,y:end.y+(end.y-landing.y)*scale)
    // During the result beat the power smash is still above the 2.24 m
    // backstop. Its high rebound clears the padding and carries into the seats.
    let final = power == .overhead ? position : CourtRunoff.afterPlay(position)
    return final.world(height:Float(height))
  }
}

extension PracticeEngine {
  var worldBall: CourtPoint3D {
    if let resolution = pointResolution {
      if let impact = resolution.impact {
        let rebound = impact.ball(after: resolution.elapsed)
        return rebound.position.world(height: Float(rebound.height))
      }
      if let flight, flight.progress >= 1 { return flight.runout(after: resolution.elapsed) }
    }
    if let serve = servePreparation, phase == .serving {
      let feet = players[serve.server].pos
      return ServiceToss.ball(feet:feet,side:serve.server,progress:Float(serve.tossProgress ?? 0),explosive:queuedPower == .ace)
    }
    return flight.map { $0.worldBall(at: $0.progress) } ?? ball.world()
  }
}
