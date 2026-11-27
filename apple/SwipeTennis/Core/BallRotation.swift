import Foundation
import simd

struct BallRotation {
  private(set) var orientation = simd_quatf(angle:0,axis:[0,1,0])

  mutating func advance(_ game: PracticeEngine, dt: Double) {
    guard dt>0 else { return }
    if let flight = game.flight, game.phase == .live || (game.pointResolution?.elapsed ?? 2)<0.7 {
      let dx = Float(flight.landing.x-flight.from.x), dz = Float(flight.landing.y-flight.from.y)
      let travel = CourtPoint3D(dx,0,dz)
      guard simd_length_squared(travel)>0.0001 else { return }
      var axle = simd_normalize(simd_cross([0,1,0],travel))
      var rate: Float
      if flight.serve {
        let spin = Float(flight.serveProfile?.spin.rawValue ?? 0)
        rate = 46+spin*48
        axle = simd_normalize(axle+[0,dx>=0 ? 0.55 : -0.55,0])
      } else {
        switch flight.kind {
        case .slice: rate = -72
        case .drop: rate = -43
        case .lob: rate = 49
        default: rate = flight.stroke == .volley ? 22 : 94
        }
      }
      if flight.progress>0.8 { rate *= 0.76 }
      orientation = simd_normalize(simd_quatf(angle:rate*Float(dt),axis:axle)*orientation)
    } else if let t = game.servePreparation?.tossProgress {
      if Float(t)>ServiceToss.release {
        orientation = simd_normalize(simd_quatf(angle:2.4*Float(dt),axis:[0,1,0])*orientation)
      }
    }
  }
}
