import Foundation
import simd

enum BodyJoint: Int, CaseIterable {
  case leftShoe, rightShoe, leftKnee, rightKnee, leftHip, rightHip
  case leftShoulder, rightShoulder, leftElbow, rightElbow, leftHand, grip, head, strings, racketEdge
}

struct AthletePose {
  private var joints = Array(repeating: CourtPoint3D.zero, count: BodyJoint.allCases.count)
  subscript(_ joint: BodyJoint) -> CourtPoint3D {
    get { joints[joint.rawValue] }
    set { joints[joint.rawValue] = newValue }
  }

  func blended(to other: Self, by fraction: Float) -> Self {
    var result = self
    for joint in BodyJoint.allCases { result[joint] += (other[joint] - self[joint]) * fraction }
    return result
  }
}

private func ramp(_ t: Float, _ start: Float, _ end: Float) -> Float {
  let u = max(0, min(1, (t - start) / max(0.00001, end - start)))
  return u * u * (3 - 2 * u)
}

private func unit(_ v: CourtPoint3D, fallback: CourtPoint3D) -> CourtPoint3D {
  simd_length_squared(v) > 0.00001 ? simd_normalize(v) : fallback
}

/// Position the hinge using segment lengths and a preferred bending plane.
private func hinge(_ start: CourtPoint3D, _ end: CourtPoint3D, length: Float, bend: CourtPoint3D) -> CourtPoint3D {
  let axis = unit(end - start, fallback: CourtPoint3D(0, -1, 0))
  let perpendicular = unit(bend - axis * simd_dot(bend, axis), fallback: CourtPoint3D(0, 0, 1))
  let half = simd_distance(start, end) / 2
  return (start + end) / 2 + perpendicular * sqrt(max(0.0004, length * length - half * half))
}

struct AthleteMotion {
  private var feet = CourtFootwork()
  private var swing = StrokeAnimation()
  private var hitPoint = CourtPoint3D.zero
  private var previousStrings: CourtPoint3D?
  private var transitionStart: CourtPoint3D?
  private var transitionTime: Double = 0

  mutating func sample(game: PracticeEngine, side: Int, hit: Bool, dt: Double, reduceMotion: Bool) -> AthletePose {
    let player = game.players[side]
    let centre = player.pos.world()
    let sign: Float = side == 0 ? 1 : -1
    let up = CourtPoint3D(0, 1, 0), right = CourtPoint3D(sign, 0, 0)
    let forward = CourtPoint3D(0, 0, -sign)
    func local(_ x: Float, _ h: Float, _ depth: Float) -> CourtPoint3D {
      centre + right * x + up * h + forward * depth
    }
    var style = player.kind.strokeStyle
    var arrival: Double?
    var target: CourtPoint3D?
    let service = game.servePreparation.flatMap { $0.server == side ? $0 : nil }
    if let flight = game.flight, flight.hitter != side, game.phase == .live,
      flight.fault == nil, flight.power == nil,
      !(side == 1 && (flight.opponentError == .unreachable || flight.dropReachable == false)) {
      let window = game.contactWindow(side)
      var phase = max(flight.progress, window?.entry ?? 1)
      if window?.volley == true { style = window?.overhead == true ? .overhead : .volley }
      arrival = max(0, phase * flight.duration - flight.elapsed)
      if side == 0, let assist = game.assist {
        phase = assist.impactProgress
        arrival = max(0, assist.travelTime - assist.elapsed)
        style = assist.power == .overhead ? .overhead : .groundstroke
      }
      target = flight.worldBall(at: phase)
    }
    if let elapsed = service?.tossElapsed {
      arrival = max(0, ServePreparation.tossDuration - elapsed)
      style = .serve
      target = serviceImpact(at: player.pos, side: side, explosive: game.queuedPower == .ace)
    }
    // A missed ball must pass the runner. Only prepare a reach the athlete could make.
    if let goal = target, let remaining = arrival {
      let horizontal = hypot(goal.x - centre.x, goal.z - centre.z)
      if horizontal > 1.40 + Float(remaining) * 6.0 { target = nil; arrival = nil }
    }
    let oldFollow = swing.timeAfterContact != nil
    if hit, let outgoing = game.flight {
      hitPoint = outgoing.strikeOrigin ?? game.worldBall
      swing.hit(style: outgoing.stroke)
      transitionStart = nil
    }
    let lateral = Double(((target ?? game.worldBall).x - centre.x) * sign)
    swing.update(delta: hit ? 0 : dt, lateralBall: lateral, arrival: arrival, incomingStyle: style)
    if oldFollow && swing.timeAfterContact == nil && arrival != nil {
      transitionStart = previousStrings; transitionTime = game.time
    }
    let elapsed = swing.timeAfterContact
    let time = Float(elapsed ?? swing.timeUntilContact.map { -$0 } ?? -2)
    let sideOfBall: Float = swing.stance == .forehand ? 1 : -1
    let strike = elapsed != nil ? hitPoint : target ?? local(sideOfBall * 0.7, 1, 0.28)
    let volley = swing.style == .volley
    let forehand = swing.style == .groundstroke && swing.stance == .forehand
    let speed = Float(player.velocity.length)
    let atNet = abs(player.pos.y - PracticeEngine.net) < 5
    let rush = min(1, speed / 5.5)
    let load = ramp(time, volley ? -0.28 : -0.62, -0.16)
    let finish = 1 - ramp(time, 0.20, Float(swing.recoveryDuration))
    let drive = load * finish
    let low = min(1, max(0, (1.10 - strike.y) / 0.85)) * drive
    let split = Float(game.splitProgress(side) ?? 0)
    let hop: Float = reduceMotion ? 0 : 0.115 * sin(split * .pi)
    let landing = game.serveLanding.flatMap { $0.server == side ? $0.progress : nil }
    let leap = reduceMotion ? 0 : Float(ServeMotion.jumpHeight(tossProgress: service?.tossProgress, landingProgress: landing)) * 0.034
    let kneeLoad = load * (1 - ramp(time, -0.13, 0.12))
    let bend = 0.125 + rush * 0.055 + kneeLoad * 0.13 + low * 0.28 + (atNet ? 0.045 : 0) + (landing.map { Float(sin($0 * .pi)) * 0.1 } ?? 0)
    let volleyStep = volley ? drive : 0
    let step = (forward * 0.36 + right * (sideOfBall * 0.15)) * volleyStep
    feet.advance(centre: centre, velocity: player.velocity.world(), destination: player.destination.world(),
      facing: sign, strideBias: step, dt: Float(dt))
    var pose = AthletePose()
    pose[.leftShoe] = (reduceMotion ? centre - right * 0.23 : feet.left) + up * (0.055 + hop + leap)
    pose[.rightShoe] = (reduceMotion ? centre + right * 0.23 : feet.right) + up * (0.055 + hop + leap)
    if let landing {
      pose[.rightShoe] += (up * 0.32 - forward * 0.24) * Float(sin(landing * .pi))
    }
    // Uncoil the pelvis first, the ribcage second, and release the racket last.
    let hipTurn = sideOfBall * drive * (-0.48 + 0.94 * ramp(time, -0.16, 0.05))
    let chestTurn = sideOfBall * drive * (-0.96 + 1.82 * ramp(time, -0.09, 0.10)) * (volley ? 0.42 : 1)
    let moveTurn = min(0.65, abs(Float(player.velocity.x)) * 0.11) * (player.velocity.x * Double(sign) >= 0 ? -1 : 1)
    func axis(_ angle: Float) -> CourtPoint3D { right * cos(angle) + forward * sin(angle) }
    let weight = right * (sideOfBall * 0.09 * kneeLoad)
    let approaching = game.followingApproach[side]
    let forwardRun = min(1, max(0, simd_dot(player.velocity.world(), forward) / 5))
    let weightForward = forward * ((0.08 + 0.14 * volleyStep) * drive)
    let shoeMid = (pose[.leftShoe] + pose[.rightShoe]) / 2
    let offset = shoeMid - centre
    let support = CourtPoint3D(max(-0.19, min(0.19, offset.x)), 0, max(-0.14, min(0.14, offset.z)))
    var pelvis = centre + support * 0.72 + weight + weightForward + up * (0.98 - bend + hop + leap)
    let hips = axis(hipTurn + moveTurn * (1 - drive))
    let shoulders = axis(chestTurn + moveTurn * (1 - drive))
    // Lower the hips over the extended support leg before its knee can lock straight.
    for (shoe, hipOffset) in [(pose[.leftShoe], -hips * 0.14), (pose[.rightShoe], hips * 0.14)] {
      let leg = pelvis + hipOffset - shoe
      let height = sqrt(max(0.30, 0.90 * 0.90 - leg.x * leg.x - leg.z * leg.z))
      pelvis.y = min(pelvis.y, shoe.y + height)
    }
    let lean = max(-1, min(1, Float(player.velocity.x) / 5.5))
    var chest = pelvis + up * 0.47 + CourtPoint3D(0.048 * lean, 0, 0) + forward * (0.085 + 0.07 * rush + low * 0.13)
    // Lean into the low first volley; retain the shot finish as the first approach step starts.
    chest += (right * sideOfBall * 0.13 + forward * 0.18) * volleyStep
    if approaching { chest += forward * (0.12 * forwardRun) }
    pose[.leftHip] = pelvis - hips * 0.14; pose[.rightHip] = pelvis + hips * 0.14
    pose[.leftShoulder] = chest - shoulders * 0.22; pose[.rightShoulder] = chest + shoulders * 0.22
    pose[.leftKnee] = hinge(pose[.leftHip], pose[.leftShoe], length: 0.47, bend: forward - right * 0.15)
    pose[.rightKnee] = hinge(pose[.rightHip], pose[.rightShoe], length: 0.47, bend: forward + right * 0.15)
    pose[.head] = chest + up * 0.23 + forward * 0.042

    let ready = local(0.16, atNet ? 1.48 : 1.29, 0.43)
    var strings: CourtPoint3D
    var shaft: CourtPoint3D
    if forehand || volley {
      let set = volley ? local(sideOfBall * 0.46, max(1.05, strike.y + 0.14), 0.21)
        : local(0.70 - rush * 0.16, 1.48, -0.44 + rush * 0.28)
      let drop = volley ? set : local(0.79 - rush * 0.11, max(0.36, strike.y - 0.27), -0.37 + rush * 0.22)
      let follow = volley ? local(sideOfBall * 0.51, max(0.72, min(1.6, strike.y + 0.13)), 0.66)
        : local(-0.38, 1.71 - rush * 0.12, 0.16 + rush * 0.24)
      strings = ready + (set - ready) * load
      strings += (drop - set) * ramp(time, -0.20, -0.075)
      let release = ramp(time, volley ? -0.105 : -0.085, 0)
      strings += (strike - strings) * release
      strings += (follow - strings) * ramp(time, 0, volley ? 0.115 : 0.21)
      strings += (ready - strings) * (1 - finish)
      let lag = ramp(time, -0.19, -0.065) * (1 - ramp(time, -0.065, 0))
      shaft = up * (0.86 - drive * 0.45) + right * sideOfBall * (0.25 + drive * 0.65)
      // A low volley takes the strings below the hand as the knees absorb the ball.
      shaft -= up * low * (volley ? 1.65 : 0.92)
      shaft -= forward * lag * (volley ? 0.12 : 1.2)
      shaft += (-right * sideOfBall * 1.6 + up * 0.48) * ramp(time, 0, 0.18) * finish
    } else {
      let existing = swing.pose
      let position = existing.racketCentre
      strings = local(Float(position.x) / 30, Float(position.y) / 30 + leap, 0.23 - 0.25 * kneeLoad)
      let lock = ramp(time, -0.18, 0) * (1 - ramp(time, 0, 0.19))
      strings += (strike - strings) * lock
      shaft = right * Float(-sin(existing.racketAngle)) + up * Float(cos(existing.racketAngle)) + forward * 0.18
    }
    if let start = transitionStart, !hit {
      let blend = ramp(Float(game.time - transitionTime), 0, min(0.09, Float(arrival ?? 0.1) + Float(game.time - transitionTime)))
      if blend < 1 { strings = start + (strings - start) * blend } else { transitionStart = nil }
    }
    if hit { strings = hitPoint }
    let reaction = game.isResolvingPoint ? game.pointResolution?.reaction : nil
    if (side == 1 && (reaction?.frustration ?? 0) > 0) || (side == 0 && reaction?.affirmation != nil) {
      let t = ramp(Float(game.pointResolution?.elapsed ?? 0), 0.16, 0.46)
      strings += (local(0.52, side == 1 ? 0.61 : 1.05, 0.24) - strings) * t
      pose[.head] -= up * (side == 1 ? 0.08 * t : 0)
    }
    shaft = unit(shaft, fallback: up)
    pose[.strings] = strings
    pose[.grip] = strings - shaft * 0.49
    let across = unit(simd_cross(shaft, forward + up * (volley ? 0.22 : 0.08)), fallback: right)
    pose[.racketEdge] = strings + across * 0.132
    var offHand = pose[.leftShoulder] - shoulders * (0.18 + drive * 0.12) + forward * 0.23 - up * 0.18
    if swing.pose.supportHandOnGrip { offHand = pose[.grip] + shaft * 0.095 }
    if let service {
      let t = Float(service.tossProgress ?? 0)
      offHand = local(-0.32, 1.05 + 1.02 * ramp(t, 0, 0.4) - 1.02 * ramp(t, 0.52, 1), 0.17)
    } else if swing.style == .overhead && arrival != nil { offHand = local(-0.29, 1.9, 0.19) }
    if side == 0 && game.flight?.acknowledge == true && game.isResolvingPoint { offHand = local(-0.24, 2.03, 0.12) }
    pose[.leftHand] = offHand
    pose[.rightElbow] = hinge(pose[.rightShoulder], pose[.grip], length: 0.34, bend: right - up * 0.5 - forward)
    pose[.leftElbow] = hinge(pose[.leftShoulder], offHand, length: 0.34, bend: -right - up * 0.5 - forward)
    if let reaction, !reduceMotion {
      let t = ramp(Float(game.pointResolution?.elapsed ?? 0), 0.12, 0.4)
      if side == 1 && reaction.frustration > 0 {
        let gesture = reaction.frustration > 1 ? pose[.head] - right * 0.12 : pose[.leftShoulder] - right * 0.19
        pose[.leftHand] += (gesture - pose[.leftHand]) * t
      } else if side == 0 && reaction.affirmation != nil && game.flight?.acknowledge != true {
        pose[.leftHand] += (chest + forward * 0.15 - pose[.leftHand]) * t
      }
      pose[.leftElbow] = hinge(pose[.leftShoulder], pose[.leftHand], length: 0.34, bend: -right - forward)
    }
    previousStrings = strings
    return pose
  }
}
