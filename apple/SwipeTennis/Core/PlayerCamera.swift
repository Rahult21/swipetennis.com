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
    // Frame the playable lane between the receiver and the next target. A
    // portrait camera pointed only at the player has to retreat far behind
    // the baseline to keep a crosscourt return in view.
    let trackingWeight = 0.68 + 0.16*wide
    let nextX = Float((receiver ?? recovery ?? player).x)
    let lookAcross = max(-1.55,min(1.55,(nextX-own.x)*0.30))*(1-0.8*wide)
    let focusX = 4.115+(trackedX-4.115)*trackingWeight+lookAcross
    let closeTarget = CourtPoint3D(focusX,0.78,own.z-sign*(6.8+0.7*wide))
    let goal = broadcastTarget+(closeTarget-broadcastTarget)*amount
    let closeDir = simd_normalize(CourtPoint3D(0,0.535-0.06*wide,sign))
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
      for x: Float in [-0.42,8.65] { include([x,1.95,far],margin:1.08) }
      for point in [receiver,recovery].compactMap({$0}) {
        for dx: Float in [-0.82,0.82] { include(point.world()+[dx,0,sign*0.45],margin:1.13) }
      }
    }
    if reduceMotion {
      // Hold a steady broadcast frame, with room beyond both baselines.
      for x: Float in [-4,12.23] { for z: Float in [-7.5,31.27] {
        include([x,0,z],margin:1.08)
      } }
    } else { include(ball,margin:1.12) }
    let opening = Self(eye:goal+view*(distance+(1-t)*2.8),target:goal,verticalFOV:fov)
    guard aspect > 1, !reduceMotion else { return opening }
    // From the baseline rail both courts stay in shot. Only the lateral
    // framing follows play, so rushing the net does not drag the lens forward.
    let centre: Float = 4.115
    let pan = style == .baseline ? min(0.65,max(-0.65,(trackedX-centre)*0.16)) : 0
    let end = side == 0 ? Float(PracticeEngine.length) : 0
    let extra: Float = style == .wide ? 2.3 : 0
    var rail = Self(eye:[centre+pan*0.40,8.1+extra*0.38,end+sign*(10.7+extra)],
                    target:[centre+pan,0.45,end-sign*7.7],verticalFOV:36.5)
    for x: Float in [-1.37,9.60] {
      rail = rail.including([x,0,end],aspect:aspect,margin:1.04)
      rail = rail.including([x,1.9,Float(PracticeEngine.length)-end],aspect:aspect,margin:1.05)
    }
    for target in [player,receiver,recovery].compactMap({ $0 }) {
      rail = rail.including(target.world()+[0,0,sign*0.24],aspect:aspect,margin:1.06)
      rail = rail.including(target.world(height:2.95),aspect:aspect)
    }
    rail = rail.including(ball,aspect:aspect)
    let blend = min(1,(aspect-1)/0.40)*t*t*(3-2*t)
    return Self(eye:opening.eye+(rail.eye-opening.eye)*blend,target:opening.target+(rail.target-opening.target)*blend,
                verticalFOV:opening.verticalFOV+(rail.verticalFOV-opening.verticalFOV)*blend)
  }

  /// Keep the entire player-side swing inside a narrow portrait frame, even
  /// when the follow-through and the outgoing ball occupy opposite edges.
  func including(_ athlete: AthletePose, aspect: Float) -> Self {
    var fit = self
    for joint: BodyJoint in [.head,.leftElbow,.rightElbow,.leftHand,.grip,.leftShoe,.rightShoe,.strings,.racketEdge] {
      var p = athlete[joint]
      if joint == .head { p.y += 0.15 }
      if joint == .strings { p += simd_normalize(p-athlete[.grip])*0.19 }
      fit = fit.including(p,aspect:aspect,margin:1.16)
    }
    return fit
  }

  /// Back up along the same optical axis when a ball would leave the frame.
  /// The lens, heading and player's eyeline stay steady as it travels past.
  func including(_ ball: CourtPoint3D, aspect: Float, margin: Float = 1.06) -> Self {
    let view = simd_normalize(eye-target), right = simd_normalize(simd_cross([0,1,0],view))
    let up = simd_cross(view,right), ray = ball-eye
    let tangent = tan(verticalFOV * .pi/360)
    let span = max(abs(simd_dot(ray,right))/max(0.29,aspect),abs(simd_dot(ray,up)))
    let retreat = max(0,simd_dot(ray,view)+margin*span/tangent)
    return Self(eye:eye+view*retreat,target:target,verticalFOV:verticalFOV)
  }

  func projected(_ position: CourtPoint3D, aspect: Float) -> SIMD2<Float> {
    let back = simd_normalize(eye-target), right = simd_normalize(simd_cross([0,1,0],back))
    let up = simd_cross(back,right), ray = position-eye
    let half = max(0.001,-simd_dot(ray,back))*tan(verticalFOV * .pi/360)
    return [simd_dot(ray,right)/(half*aspect),simd_dot(ray,up)/half]
  }
}

/// A fixed courtside shot composed from the recorded swing, including its
/// backswing and finish. Scrubbing and changing playback speed keep the same lens.
struct ReplayStrokeCamera {
  let cutToCourt: Double
  private let points: [CourtPoint3D]
  private let direction: CourtPoint3D

  init?(_ replay: PointReplay) {
    guard let hit = replay.strikes.last, let impact = replay.frame(at:hit.time) else { return nil }
    cutToCourt = hit.time+0.38
    let body = hit.hitter == 0 ? impact.near : impact.far
    let hip = (body[.rightHip]+body[.leftHip])*0.5
    let facing: Float = hit.hitter == 0 ? 1 : -1
    let side: Float = abs(hit.point.x-hip.x) < 0.12 ? facing : (hit.point.x >= hip.x ? 1 : -1)
    // At net, stay behind the volleyer's shoulder so the mesh never crosses the face.
    let netSide: Float = abs(hip.z-Float(PracticeEngine.net)) < 2.3 ? 0.44 : -0.60
    direction = simd_normalize([side*0.82,0.14,facing*netSide])
    let first = max(0,Int(floor((hit.time-hit.preparation)/PointReplay.tick)))
    let last = min(replay.frames.count-1,Int(ceil(cutToCourt/PointReplay.tick)))
    var envelope: [CourtPoint3D] = []
    for index in first...last {
      let frame = replay.frames[index]
      let pose = hit.hitter == 0 ? frame.near : frame.far
      for joint in BodyJoint.allCases { envelope.append(pose[joint]) }
      envelope.append(pose[.head]+[0,0.17,0])
      envelope.append(pose[.leftShoe]-[0,0.08,0])
      envelope.append(pose[.rightShoe]-[0,0.08,0])
      let tip = pose[.strings]-pose[.grip]
      envelope.append(pose[.strings]+tip*0.42)
      if hit.serve && Double(index)*PointReplay.tick <= hit.time { envelope.append(frame.ball) }
    }
    points = envelope
  }

  func frame(aspect: Float) -> PlayerCamera {
    let across = simd_normalize(simd_cross([0,1,0],direction))
    let up = simd_cross(direction,across)
    var low = SIMD3<Float>(repeating:.infinity), high = -low
    for point in points {
      let view = SIMD3(simd_dot(point,across),simd_dot(point,up),simd_dot(point,direction))
      low = simd_min(low,view)
      high = simd_max(high,view)
    }
    let mid = (low+high)*0.5
    let target = across*mid.x+up*mid.y+direction*mid.z
    let lens: Float = 33
    let halfHeight = max((high.y-low.y)*0.5,(high.x-low.x)*0.5/max(0.25,aspect))
    let distance = max(3.9,halfHeight*1.16/tan(lens * .pi/360)+(high.z-mid.z))
    return PlayerCamera(eye:target+direction*distance,target:target,verticalFOV:lens)
  }
}

/// Replay seconds run at half real time. Hold the hands in frame before lifting
/// clear of the seat backs and completing an orbit over the spectators.
enum MatchCeremony {
  static let duration = 6.5
  static func distanceToNet(at seconds: Double) -> Double {
    0.54 + 1.18*(1-StrokeAnimation.ease(seconds/1.05))
  }
  static func camera(seconds: Double, aspect: Float, reduceMotion: Bool) -> PlayerCamera {
    let center = CourtPoint3D(4.115,0,11.885)
    // Fit both approaching bodies in a portrait frame, then close in on the clasp.
    // The stationary accessibility camera holds the initial two-player composition.
    let separation = Float(distanceToNet(at:reduceMotion ? 0 : seconds))
    let horizontalTangent = max(0.26,aspect)*tan(Float(43)*(.pi/360))
    let openingRadius = max(4.5,(0.90*separation+0.40)/horizontalTangent+0.45*separation+0.28)
    if reduceMotion {
      return PlayerCamera(eye:center+[0.90*openingRadius,2.15,0.435*openingRadius],
                          target:center+[0,1.03,0],verticalFOV:46)
    }
    func ease(_ a: Double,_ b: Double) -> Float { Float(StrokeAnimation.ease((seconds-a)/(b-a))) }
    let rise = ease(1.5,6.1), expand = ease(1.45,4.55), orbit = ease(1.35,6.35)
    let target = center+[0,1.04-0.68*rise,0]
    let angle = Float(1.12)-(2 * .pi+1.12)*orbit
    let radius = (openingRadius+(23.5-openingRadius)*expand)*(1-0.985*ease(4.70,6.50))
    let halfFOV = tan(Float(56) * .pi/360)
    let seatingWidth: Float = 22.0, seatingDepth: Float = 29.6, galleryHeight: Float = 8.5
    let overheadHeight = max(seatingDepth,seatingWidth/max(0.26,aspect))*1.07/halfFOV+galleryHeight
    let height = 1.15+rise*(overheadHeight-1.15)
    return PlayerCamera(eye:target+[sin(angle)*radius,height,cos(angle)*radius],
                        target:target,verticalFOV:43+13*expand)
  }
}
