import Foundation
import simd

enum MatchViewpoint: String, CaseIterable {
  case baseline = "Player follow", wide = "Wide court"
}

/// A perspective camera fitted to playable positions. The close end may crop
/// unused run-off, but the athlete, ball and next playable ring stay inside.
struct PlayerCamera {
  let eye, target: CourtPoint3D
  let verticalFOV: Float

  static func frame(side: Int, player: Vec, trackedX: Float, receiver: Vec?, recovery: Vec?, ball: CourtPoint3D,
                    aspect: Float, intro: Float, reduceMotion: Bool, style: MatchViewpoint) -> Self {
    let sign: Float = side == 0 ? 1 : -1
    let wide = min(1,max(0,(aspect-0.75)/0.55))
    let t = reduceMotion ? 1 : intro
    let broadcastTarget = CourtPoint3D(4.115,0.55,11.885+sign*(2.1+3.4*wide))
    let follow = reduceMotion ? 0 : min(0.95,max(-0.95,(trackedX-4.115)*0.23))
    let direction = simd_normalize(CourtPoint3D(follow*0.11+(1-t)*0.38,0.75-0.17*wide+(1-t)*2.4,sign))
    let baseline = style == .baseline && !reduceMotion
    let amount = baseline ? t*t*(3-2*t) : 0
    let own = player.world()
    let closeTarget = CourtPoint3D(0.86*trackedX+0.14*4.115,0.95,own.z-sign*(5.7+1.6*wide))
    let goal = broadcastTarget+(closeTarget-broadcastTarget)*amount
    let closeDir = simd_normalize(CourtPoint3D(0,0.365+0.05*wide,sign))
    let view = simd_normalize(direction+(closeDir-direction)*amount)
    let fov = (53+5*wide)*(1-amount)+(45+3*wide)*amount
    let xAxis = simd_normalize(simd_cross([0,1,0],view)), yAxis = simd_cross(view,xAxis)
    let tangent = tan(fov * .pi/360)
    var distance: Float = baseline ? 7.0 : 12.0
    func include(_ point: CourtPoint3D, margin: Float) {
      let local = point-goal
      let projected = max(abs(simd_dot(local,xAxis))/(max(0.29,aspect)*tangent),abs(simd_dot(local,yAxis))/tangent)
      distance = max(distance,simd_dot(view,local)+margin*projected)
    }
    if amount<1 {
      for x: Float in [-1.64,9.87] { for z: Float in [-2.4,26.4] {
        // The opening shot dissolves continuously from the full stadium to the player.
        let corner = CourtPoint3D(x,0,z)
        include(corner+(own-corner)*amount,margin:1.06)
      } }
    }
    if baseline {
      // Allow space for the hitting arm on both sides and the overhead toss.
      for dx: Float in [-1.12,1.12] {
        include(own+[dx,0,sign*0.55],margin:1.17)
        include(own+[dx,3.12,0],margin:1.12)
      }
      let far = side == 0 ? Float(-1.1) : 24.87
      for x: Float in [-1,9.23] { include([x,1.95,far],margin:1.08) }
      for point in [receiver,recovery].compactMap({$0}) {
        for dx: Float in [-0.82,0.82] { include(point.world()+[dx,0,sign*0.45],margin:1.13) }
      }
      include(ball,margin:1.12)
    }
    return Self(eye:goal+view*(distance+(1-t)*2.8),target:goal,verticalFOV:fov)
  }

  func projected(_ position: CourtPoint3D, aspect: Float) -> SIMD2<Float> {
    let back = simd_normalize(eye-target), right = simd_normalize(simd_cross([0,1,0],back))
    let up = simd_cross(back,right), ray = position-eye
    let half = max(0.001,-simd_dot(ray,back))*tan(verticalFOV * .pi/360)
    return [simd_dot(ray,right)/(half*aspect),simd_dot(ray,up)/half]
  }
}
