import Foundation

/// The ball shares the tossing palm's path through release. The remaining
/// flight is a parabola passing through the engine's actual strike location.
enum ServiceToss {
  static let release: Float = 0.31

  static func palm(feet: Vec, side: Int, progress: Float) -> CourtPoint3D {
    let sign: Float = side == 0 ? 1 : -1
    let start = feet.world(height:1.05)+[-0.32*sign,0,-0.17*sign]
    let lift = CourtPoint3D(0.09*sign,0.70,-0.046*sign)
    if progress <= release {
      let t = max(0,progress/release)
      return start+lift*(t*t)
    }
    let t = min(1,(progress-release)/0.16)
    return start+lift+CourtPoint3D(0.035*sign,0.29,-0.018*sign)*(1-(1-t)*(1-t))
  }

  static func ball(feet: Vec, side: Int, progress: Float, explosive: Bool) -> CourtPoint3D {
    if progress <= release { return palm(feet:feet,side:side,progress:progress) }
    let start = palm(feet:feet,side:side,progress:release)
    let end = serviceImpact(at:feet,side:side,explosive:explosive)
    let t = min(1,(progress-release)/(1-release))
    let duration = Float(ServePreparation.tossDuration)*(1-release)
    let arc: Float = 0.5*9.81*duration*duration*t*(1-t)
    return start+(end-start)*t+[0,arc,0]
  }
}
