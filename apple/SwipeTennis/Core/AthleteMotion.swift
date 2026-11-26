import Foundation
import simd

enum BodyJoint: Int, CaseIterable {
  case leftShoe, rightShoe, leftKnee, rightKnee, leftHip, rightHip
  case leftShoulder, rightShoulder, leftElbow, rightElbow, leftHand, grip, head, strings, racketEdge
}

struct AthletePose {
  private var joints = Array(repeating: CourtPoint3D.zero, count: BodyJoint.allCases.count)
  var heelPitch: Float = 0
  subscript(_ joint: BodyJoint) -> CourtPoint3D {
    get { joints[joint.rawValue] }
    set { joints[joint.rawValue] = newValue }
  }

  func blended(to other: Self, by fraction: Float) -> Self {
    var result = self
    result.heelPitch += (other.heelPitch - heelPitch) * fraction
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
        style = assist.power == .overhead && assist.setup != true ? .overhead : .groundstroke
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
    let assisted = side == 0 ? game.assist : nil
    let activePower = assisted?.setup == true ? nil : assisted?.power
      ?? (game.flight?.hitter == side && swing.timeAfterContact != nil ? game.flight?.power : nil)
      ?? (service != nil ? game.queuedPower : nil)
    if activePower == .rally { swing.setPowerHand(backhand: assisted?.backhand ?? game.flight?.powerBackhand ?? false) }
    if oldFollow && swing.timeAfterContact == nil && arrival != nil {
      transitionStart = previousStrings; transitionTime = game.time
    }
    let elapsed = swing.timeAfterContact
    let time = Float(elapsed ?? swing.timeUntilContact.map { -$0 } ?? -2)
    let sideOfBall: Float = swing.stance == .forehand ? 1 : -1
    let strike = elapsed != nil ? hitPoint : target ?? local(sideOfBall * 0.7, 1, 0.28)
    let volley = swing.style == .volley
    let forehand = swing.style == .groundstroke && swing.stance == .forehand
    let backhand = swing.stance == .backhand && (swing.style == .groundstroke || swing.style == .lob)
    let readiness: Float
    switch game.phase {
    case .ready: readiness = 0
    case .serving: readiness = ramp(Float(game.servePreparation?.elapsed ?? 1), 0, 0.26)
    case .live: readiness = 1
    case .point, .finished, .serveFault:
      readiness = 1 - ramp(Float(game.pointResolution?.elapsed ?? 1), 0.04, 0.35)
    }
    let speed = Float(player.velocity.length)
    let atNet = abs(player.pos.y - PracticeEngine.net) < 5
    let rush = min(1, speed / 5.5)
    let load = ramp(time, volley ? -0.28 : -0.62, -0.16)
    let finish = 1 - ramp(time, 0.20, Float(swing.recoveryDuration))
    let drive = load * finish
    let lowBall = min(1, max(0, (1.10 - strike.y) / 0.85))
    let low = lowBall * drive
    let split = Float(game.splitProgress(side) ?? 0)
    let hop: Float = reduceMotion ? 0 : 0.115 * sin(split * .pi)
    let landing = game.serveLanding.flatMap { $0.server == side ? $0.progress : nil }
    let effort = player.netEffort
    let effortTime = effort.map { Float(game.time - $0.impactTime) } ?? 1
    let windup = effort.map { Float(min(-0.001, $0.startTime - $0.impactTime)) } ?? -0.21
    let actionScale: Float = reduceMotion ? 0.72 : 1
    let dive = effort?.stroke == .dive ? ramp(effortTime, windup, 0) * (1 - ramp(effortTime, 0.11, 0.55)) * actionScale : 0
    let reachDirection = effort.map { unit(CourtPoint3D($0.target.x - Float($0.from.x), 0, $0.target.z - Float($0.from.y)), fallback: right) } ?? right
    let jumpTime = activePower == .overhead ? time : effortTime
    let jumping = effort?.stroke == .jump || activePower == .overhead
    let jump = jumping ? ramp(jumpTime, activePower == .overhead ? -0.24 : windup, 0)
      * (1 - ramp(jumpTime, 0.015, 0.28)) * actionScale : 0
    let jumpHeight = activePower == .overhead ? Float(0.44) : min(0.49, max(0.18, (effort?.target.y ?? 2.7) - 2.52))
    let leap = jumpHeight * jump + (reduceMotion ? 0 : Float(ServeMotion.jumpHeight(tossProgress: service?.tossProgress,
      landingProgress: landing)) * (activePower == .ace ? 0.045 : 0.034))
    // The racket can prepare early while the legs stay tall. Load just before the
    // forward swing, then extend through impact. A low volley needs a later release.
    let gather, extend, depth: Float
    switch swing.style {
    case .serve:
      gather = ramp(time, -0.48, -0.30)
      extend = ramp(time, -0.30, -0.16)
      depth = activePower == .ace ? 0.25 : 0.205
    case .volley:
      gather = ramp(time, -0.22, -0.085)
      extend = ramp(time, -0.075, 0.09 + 0.05 * lowBall)
      depth = 0.065 + 0.145 * lowBall
    default:
      gather = ramp(time, -0.34, -0.145)
      extend = ramp(time, -0.14, 0.055)
      depth = swing.style == .drop || swing.style == .slice ? 0.065 + 0.145 * lowBall : 0.155 + 0.085 * lowBall
    }
    let kneeLoad = readiness * gather * (1 - extend)
    let pushOff = readiness * gather * extend * (1 - ramp(time, 0.06, 0.22))
    // The lead knee softens as the server touches down, then returns to standing height.
    let landingLoad = swing.style == .serve ? ramp(time, 0.28, 0.42) * (1 - ramp(time, 0.42, 0.56)) : 0
    let bend = depth * kneeLoad + 0.016 * rush + 0.065 * landingLoad
    let volleyStep = volley ? drive : 0
    let step = (forward * 0.36 + right * (sideOfBall * 0.15)) * volleyStep
    let stance = max(rush, kneeLoad)
    feet.advance(centre: centre, velocity: player.velocity.world(), destination: player.destination.world(),
      facing: sign, strideBias: step, dt: Float(dt), readiness: stance)
    var pose = AthletePose()
    pose.heelPitch = readiness * 0.015 + 0.045 * rush + 0.17 * pushOff
    let ankleHeight = 0.06 + 0.14 * sin(pose.heelPitch) + hop + leap
    let stanceWidth = 0.175 + stance * 0.07
    pose[.leftShoe] = (reduceMotion ? centre - right * stanceWidth : feet.left) + up * ankleHeight
    pose[.rightShoe] = (reduceMotion ? centre + right * stanceWidth : feet.right) + up * ankleHeight
    pose[.leftShoe] += (up * 0.18 - reachDirection * 0.45) * dive + forward * (0.19 * jump)
    pose[.rightShoe] += (up * 0.29 - reachDirection * 0.51) * dive + (up * 0.17 - forward * 0.24) * jump
    if let landing {
      pose[.rightShoe] += (up * 0.32 - forward * 0.24) * Float(sin(landing * .pi))
    }
    // Uncoil the pelvis first, the ribcage second, and release the racket last.
    // On a two-handed backhand the right shoulder points toward the net in preparation.
    // The pelvis opens while the shoulders still hold the coil. The hands then travel through.
    let coil = ramp(time, -0.72, -0.23) * finish
    let hipTurn = backhand ? coil * (0.56 - 1.03 * ramp(time, -0.20, 0.035))
      : sideOfBall * drive * (-0.48 + 0.94 * ramp(time, -0.16, 0.05))
    let chestTurn = backhand ? coil * (1.30 - 2.18 * ramp(time, -0.115, 0.125))
      : sideOfBall * drive * (-0.96 + 1.82 * ramp(time, -0.09, 0.10)) * (volley ? 0.42 : 1)
    let moveTurn = min(0.65, abs(Float(player.velocity.x)) * 0.11) * (player.velocity.x * Double(sign) >= 0 ? -1 : 1)
    func axis(_ angle: Float) -> CourtPoint3D { right * cos(angle) + forward * sin(angle) }
    let weight = right * (sideOfBall * 0.09 * kneeLoad)
    let approaching = game.followingApproach[side]
    let forwardRun = min(1, max(0, simd_dot(player.velocity.world(), forward) / 5))
    let weightForward = forward * ((0.08 + 0.14 * volleyStep) * drive)
    let shoeMid = (pose[.leftShoe] + pose[.rightShoe]) / 2
    let offset = shoeMid - centre
    let support = CourtPoint3D(max(-0.19, min(0.19, offset.x)), 0, max(-0.14, min(0.14, offset.z)))
    var pelvis = centre + support * 0.72 + weight + weightForward + up * (0.99 - bend + 0.022 * pushOff + hop + leap)
    pelvis += (reachDirection * 0.16 - up * 0.47) * dive
    // Lead the drive with the hips. On the serve, hold the tossing shoulder up until release.
    let powerCoil: Float = activePower == .rally ? (backhand ? 0.18 : -0.24) : activePower == .ace ? -0.35 : 0
    let hips = axis(hipTurn + powerCoil * (1 - 1.6 * ramp(time,-0.20,0)) * coil + moveTurn * (1 - drive))
    let shoulders = axis(chestTurn + powerCoil * (1 - 1.8 * ramp(time,-0.12,0.12)) * coil
      + moveTurn * (1 - (backhand ? coil : drive)))
    if activePower == .rally { pelvis += forward * (0.095 * pushOff) }
    var wrongStep = CourtPoint3D.zero
    if side == 1, let winner = game.flight, winner.power != nil {
      let elapsed = Float(winner.elapsed)
      let reaching = ramp(elapsed,0.075,0.29) * (1 - ramp(elapsed,0.39,0.74))
      let direction: Float = winner.landing.x >= player.pos.x ? 1 : -1
      wrongStep = CourtPoint3D(direction,0,0) * (reduceMotion ? 0.06 : 0.18) * reaching
      pelvis += wrongStep * 0.35
    }
    // Lower the hips over the extended support leg before its knee can lock straight.
    for (shoe, hipOffset) in [(pose[.leftShoe], -hips * 0.14), (pose[.rightShoe], hips * 0.14)] {
      let leg = pelvis + hipOffset - shoe
      let legLength: Float = 0.936
      let height = sqrt(max(0.30, legLength * legLength - leg.x * leg.x - leg.z * leg.z))
      pelvis.y = min(pelvis.y, shoe.y + height)
    }
    let lean = max(-1, min(1, Float(player.velocity.x) / 5.5))
    var chest = pelvis + up * (0.49 - 0.018 * kneeLoad) + CourtPoint3D(0.048 * lean, 0, 0)
      + forward * (0.015 + 0.065 * rush + kneeLoad * (0.065 + lowBall * 0.08))
    // Lean into the low first volley; retain the shot finish as the first approach step starts.
    if volley { chest += (right * sideOfBall * 0.10 + forward * 0.12) * kneeLoad }
    if approaching { chest += forward * (0.12 * forwardRun) }
    chest += (reachDirection * 0.39 - up * 0.22) * dive + wrongStep
    pose[.leftHip] = pelvis - hips * 0.14; pose[.rightHip] = pelvis + hips * 0.14
    let shoulderTilt: Float = activePower == .ace || activePower == .overhead
      ? 0.13 * (ramp(time,-0.46,-0.20) - 1.70 * ramp(time,-0.15,0.015)) * finish : 0
    pose[.leftShoulder] = chest - shoulders * 0.22 + up * shoulderTilt
    pose[.rightShoulder] = chest + shoulders * 0.22 - up * shoulderTilt
    // Track the knees outward over the wider base as the feet plant for the shot.
    let kneeOut = right * (0.15 + 0.40 * kneeLoad)
    pose[.leftKnee] = hinge(pose[.leftHip], pose[.leftShoe], length: 0.47, bend: forward - kneeOut)
    pose[.rightKnee] = hinge(pose[.rightHip], pose[.rightShoe], length: 0.47, bend: forward + kneeOut)
    pose[.head] = chest + up * 0.23 + forward * 0.042 + (reachDirection * 0.14 - up * 0.09) * dive

    let ready = local(0.16, atNet ? 1.48 : 1.29, 0.43)
    var strings: CourtPoint3D
    var shaft: CourtPoint3D
    if backhand {
      let set = local(-0.56, 1.40, -0.33 + 0.12 * rush)
      let drop = local(-0.68, max(0.29, strike.y - 0.24), -0.30 + 0.14 * rush)
      let follow = local(0.42, swing.style == .lob ? 1.89 : 1.73, 0.06 + rush * 0.18)
      strings = ready + (set - ready) * ramp(time, -0.62, -0.20)
      strings += (drop - set) * ramp(time, -0.22, -0.105)
      strings += (strike - strings) * ramp(time, -0.105, 0)
      // Extend out in front first, then wrap high over the right shoulder.
      let extensionPoint = strike + forward * (activePower == .rally ? 0.42 : 0.20) + right * 0.17 + up * 0.13
      strings += (extensionPoint - strings) * ramp(time, 0, 0.055)
      strings += (follow - strings) * ramp(time, 0.035, 0.23)
      strings += (ready - strings) * (1 - finish)
      if activePower == .rally {
        strings += (forward * 0.28 + up * 0.20 - right * 0.18) * ramp(time, 0, 0.11) * finish
      }
      let turn = ramp(time, -0.105, 0.035)
      shaft = up * 0.9 + right * 0.24
      shaft += (-right * 1.08 - up * 0.64 - forward * 0.67) * drive
      shaft += forward * turn * drive
      shaft += (right * 1.65 + up * 0.58 - forward * 0.52) * ramp(time, 0.025, 0.21) * finish
    } else if forehand || volley {
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
      if activePower == .rally {
        strings += (-right * 0.21 + forward * 0.23 + up * 0.13) * ramp(time, 0, 0.13) * finish
      }
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
    if jumping || activePower == .ace {
      let t = jumping ? jumpTime : time
      let release = ramp(t, -0.15, 0), wrap = ramp(t, 0, 0.23)
      var contact = strike
      if let effort, effort.stroke == .jump {
        contact = effort.reachable ? effort.target : effort.target - up * 0.20 - reachDirection * 0.08
      }
      let raised = local(0.41, 1.98 + leap, -0.28)
      let finishPoint = local(-0.44, 0.90 + leap, 0.38)
      let reach = raised + (contact - raised) * release
      let emphasis = ramp(t, -0.31, -0.15) * (1 - ramp(t, 0.26, 0.49))
      strings += (reach + (finishPoint - reach) * wrap - strings) * emphasis
      let overheadShaft = unit(up * (1.0 - 1.7 * wrap) + right * (0.31 - wrap) + forward * (0.18 + wrap), fallback: up)
      shaft += (overheadShaft - shaft) * emphasis
    }
    if let effort, dive > 0 {
      var extensionPoint = effort.target
      if !effort.reachable { extensionPoint -= reachDirection * 0.23 }
      strings += (extensionPoint - strings) * dive
      shaft += (reachDirection + up * 0.05 - shaft) * dive
    }
    if let start = transitionStart, !hit {
      let blend = ramp(Float(game.time - transitionTime), 0, min(0.09, Float(arrival ?? 0.1) + Float(game.time - transitionTime)))
      if blend < 1 { strings = start + (strings - start) * blend } else { transitionStart = nil }
    }
    let reaction = game.isResolvingPoint ? game.pointResolution?.reaction : nil
    // Keep the serving hand with the toss, even during the first frame of a rapid serve.
    let rest = game.phase == .serving && service?.isTossing == true ? 0 : 1 - readiness
    let restingShaft = unit(right * 0.47 - up * 0.85 + forward * 0.23, fallback: -up)
    let restingGrip = local(0.32, 0.85, 0.13)
    strings += (restingGrip + restingShaft * 0.49 - strings) * rest
    shaft += (restingShaft - shaft) * rest
    if side == 1, (reaction?.frustration ?? 0) > 0 {
      let t = Float(game.pointResolution?.elapsed ?? 0)
      let lift = ramp(t, 0.09, 0.31), snap = ramp(t, 0.31, 0.48)
      let settle = 1 - ramp(t, 0.55, 0.83)
      let grip = local(0.39, 1.13, 0.24) + (up * 0.21 - forward * 0.10) * lift
        + (forward * 0.19 - up * 0.54) * snap
      let angle = (reduceMotion ? 0.48 : 1.02) * (lift - 1.87 * snap)
      let gestureShaft = unit(right * 0.46 + up * sin(angle) + forward * cos(angle), fallback: right)
      strings += (grip + gestureShaft * 0.49 - strings) * lift * settle
      shaft += (gestureShaft - shaft) * lift * settle
    }
    if hit { strings = hitPoint }
    shaft = unit(shaft, fallback: up)
    pose[.strings] = strings
    pose[.grip] = strings - shaft * 0.49
    let across = unit(simd_cross(shaft, forward + up * (volley ? 0.22 : 0.08)), fallback: right)
    pose[.racketEdge] = strings + across * 0.132
    var offHand = pose[.leftShoulder] - shoulders * (0.18 + drive * 0.12) + forward * 0.23 - up * 0.18
    if swing.pose.supportHandOnGrip { offHand = pose[.grip] + shaft * 0.095 }
    if dive > 0 { offHand += (chest - up * 0.32 - reachDirection * 0.20 - offHand) * dive }
    offHand += (local(-0.29, 0.85, 0.06) - offHand) * rest
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
      if side == 0 && reaction.affirmation != nil && game.flight?.acknowledge != true {
        pose[.leftHand] += (chest + forward * 0.15 - pose[.leftHand]) * t
      }
      pose[.leftElbow] = hinge(pose[.leftShoulder], pose[.leftHand], length: 0.34, bend: -right - forward)
    }
    previousStrings = strings
    return pose
  }
}
