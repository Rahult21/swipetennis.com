import Foundation
import simd

enum BodyJoint: Int, CaseIterable {
  case leftShoe, rightShoe, leftKnee, rightKnee, leftHip, rightHip
  case leftShoulder, rightShoulder, leftElbow, rightElbow, leftHand, grip, head, strings, racketEdge
}

struct AthletePose {
  private var joints = Array(repeating: CourtPoint3D.zero, count: BodyJoint.allCases.count)
  var heelPitch: Float = 0
  var shoeYaw = SIMD2<Float>.zero
  /// Player-relative yaw and pitch of the gaze, stored with each replay sample.
  var gaze = SIMD2<Float>.zero
  subscript(_ joint: BodyJoint) -> CourtPoint3D {
    get { joints[joint.rawValue] }
    set { joints[joint.rawValue] = newValue }
  }

  func blended(to other: Self, by fraction: Float) -> Self {
    var result = self
    result.gaze += (other.gaze - gaze) * fraction
    result.shoeYaw += (other.shoeYaw - shoeYaw) * fraction
    result.heelPitch += (other.heelPitch - heelPitch) * fraction
    for joint in BodyJoint.allCases { result[joint] += (other[joint] - self[joint]) * fraction }
    // The racket is a rigid object between samples, including slow-motion scrubbing.
    // Blend its orientation as one frame around the already interpolated hand.
    func rotation(_ p: Self) -> simd_quatf? {
      let shaft = p[.strings]-p[.grip], width = p[.racketEdge]-p[.strings]
      let normal = simd_cross(width,shaft)
      guard simd_length_squared(normal) > 0.000001 else { return nil }
      let y = simd_normalize(shaft), z = simd_normalize(normal)
      return simd_quatf(simd_float3x3(columns:(simd_cross(y,z),y,z)))
    }
    if let a = rotation(self), let b = rotation(other) {
      let q = simd_slerp(a,b,fraction)
      result[.strings] = result[.grip] + q.act([0,0.49,0])
      result[.racketEdge] = result[.strings] + q.act([0.132,0,0])
    }
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
  private var capture = CapturedTransitions()
  private var feet = CourtFootwork()
  private var gaze = SIMD2<Float>.zero
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
    let incomingGap = game.contactGuide(side).map { player.pos.distance(to: $0) }
    let quality = elapsed != nil && game.flight?.hitter == side ? game.flight?.contactQuality
      : incomingGap.map { player.rallyContact(gap: $0) }
    let blocked = (quality == .stretched || quality == .diving) && swing.style != .serve && swing.style != .overhead
    let planted = quality == .planted && swing.style == .groundstroke
    let volley = swing.style == .volley
    let forehand = swing.style == .groundstroke && swing.stance == .forehand
    let backhand = swing.stance == .backhand && (swing.style == .groundstroke || swing.style == .lob)
    let captureKind: CapturedStroke.Kind
    switch swing.style {
    case .serve: captureKind = .serve
    case .overhead: captureKind = .smash
    case .volley: captureKind = .volley
    default: captureKind = backhand ? .backhand : .forehand
    }
    let motionWeight = ramp(time,-0.79,-0.47) * (1 - ramp(time,0.27,0.58))
    let measured = motionWeight > 0 && !blocked ? CapturedStroke.sample(captureKind,at:time) : nil
    func relative(_ v: CourtPoint3D) -> CourtPoint3D { right*v.x + up*v.y + forward*v.z }
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
    let waiting = game.phase == .serving && game.servePreparation?.isTossing == false
    let beat = Float(game.time) * 8.7 + Float(side)*1.45
    let toeBounce: Float = waiting && !reduceMotion ? 0.031 * pow(max(0,sin(beat)),2) : 0
    let hop: Float = reduceMotion ? 0 : 0.115 * sin(split * .pi) + toeBounce
    let landing = game.serveLanding.flatMap { $0.server == side ? $0.progress : nil }
    let effort = player.netEffort
    let effortTime = effort.map { Float(game.time - $0.impactTime) } ?? 1
    let windup = effort.map { Float(min(-0.001, $0.startTime - $0.impactTime)) } ?? -0.21
    let actionScale: Float = reduceMotion ? 0.72 : 1
    let dive = effort?.stroke == .dive ? ramp(effortTime, windup, 0) * (1 - ramp(effortTime, 0.11, 0.55)) * actionScale : 0
    let reachDirection = effort.map { unit(CourtPoint3D($0.target.x - Float($0.from.x), 0, $0.target.z - Float($0.from.y)), fallback: right) } ?? right
    let highOverhead = swing.style == .overhead && strike.y > 2.15 && (arrival != nil || elapsed != nil)
    let jumpTime = activePower == .overhead || highOverhead ? time : effortTime
    let jumping = effort?.stroke == .jump || activePower == .overhead || highOverhead
    let jump = jumping ? ramp(jumpTime, activePower == .overhead ? -0.24 : windup, 0)
      * (1 - ramp(jumpTime, 0.015, 0.28)) * actionScale : 0
    let jumpHeight = activePower == .overhead ? Float(0.44) : min(0.49, max(0.12, (effort?.target.y ?? strike.y) - 2.55))
    let leap = jumpHeight * jump + (reduceMotion ? 0 : Float(ServeMotion.jumpHeight(tossProgress: service?.tossProgress,
      landingProgress: landing)) * (activePower == .ace ? 0.026 : 0.013))
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
    let sinceSplit = Float(game.time - game.splitStarted[side])
    let splitLanding = readiness * ramp(sinceSplit, 0.125, 0.204) * (1 - ramp(sinceSplit, 0.204, 0.34))
    let bend = depth * kneeLoad + 0.016 * rush + 0.065 * landingLoad + 0.075 * splitLanding
    let volleyStep = volley ? drive : 0
    let step = (forward * 0.36 + right * (sideOfBall * 0.15)) * volleyStep
    let stance = max(rush, kneeLoad)
    feet.advance(centre: centre, velocity: player.velocity.world(), destination: player.destination.world(),
      facing: sign, strideBias: step, dt: Float(dt), readiness: stance, surface: game.settings.surface)
    let recoveryRun = game.phase == .live && game.flight?.hitter == side && !game.followingApproach[side] && abs(player.velocity.x) > 0.9
    let captured = capture.step(speed:speed,remaining:player.pos.distance(to:player.destination),recovering:recoveryRun,dt:Float(dt))
    var pose = AthletePose()
    pose.heelPitch = readiness * 0.015 + 0.045 * rush + 0.17 * pushOff
    let ankleHeight = 0.06 + 0.14 * sin(pose.heelPitch) + hop + leap
    let splitWidth = 0.05 * ramp(sinceSplit, 0.02, 0.155) * (1 - ramp(sinceSplit, 0.24, 0.4)) * readiness
    let stanceWidth = 0.175 + stance * 0.07
    pose[.leftShoe] = (reduceMotion ? centre - right * stanceWidth : feet.left) + up * ankleHeight
    pose[.rightShoe] = (reduceMotion ? centre + right * stanceWidth : feet.right) + up * ankleHeight
    pose[.leftShoe] -= right * splitWidth
    pose[.rightShoe] += right * splitWidth
    pose[.leftShoe] += (up * 0.18 - reachDirection * 0.45) * dive + forward * (0.19 * jump)
    pose[.rightShoe] += (up * 0.29 - reachDirection * 0.51) * dive + (up * 0.17 - forward * 0.24) * jump
    if let measured, swing.style == .serve {
      // Platform stance: the front shoe points toward the net post. The back
      // foot trails, releases, and swings behind the hip as the front foot lands.
      let weight = motionWeight * actionScale
      let depth = min(0.42,max(-0.42,measured.rearFoot.z))
      pose[.leftShoe] -= forward * depth * (0.42*weight)
      pose[.rightShoe] += forward * depth * (0.58*weight)
      pose[.rightShoe].y += max(0,min(0.19,measured.rearFoot.y))*weight
      pose.shoeYaw = SIMD2<Float>(0.39,1.12)*weight
    }
    if !reduceMotion {
      // Keep the support foot anchored. Retarget the captured crossover onto the airborne shoe.
      let movingRight = player.velocity.x*Double(sign) >= 0
      for joint in [BodyJoint.leftShoe,.rightShoe] {
        let left = joint == .leftShoe
        let delta = (left == movingRight) ? captured.left : captured.right
        let weight = min(1,max(0,(pose[joint].y-ankleHeight)/0.07))
        let cross = max(-0.24,min(0.24,delta.x))*(movingRight ? 1 : -1)
        pose[joint] += (right*cross + forward * abs(cross)*0.55 + up*max(-0.035,min(0.10,delta.y))) * weight
      }
    }
    if planted {
      let lead = swing.stance == .forehand ? BodyJoint.leftShoe : .rightShoe
      let rear: BodyJoint = lead == .leftShoe ? .rightShoe : .leftShoe
      let plant = drive * (1 - ramp(time, 0.025, 0.18))
      pose[lead] += (forward * 0.21 + right * sideOfBall * 0.08) * plant
      pose[rear] -= forward * (0.10 * plant)
    }
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
    if !reduceMotion { pelvis.y += max(-0.07,min(0.06,captured.pelvis)) }
    pelvis += (reachDirection * 0.16 - up * 0.47) * dive
    // Lead the drive with the hips. On the serve, hold the tossing shoulder up until release.
    let powerCoil: Float = activePower == .rally ? (backhand ? 0.18 : -0.24) : activePower == .ace ? -0.35 : 0
    var hips = axis(hipTurn + powerCoil * (1 - 1.6 * ramp(time,-0.20,0)) * coil + moveTurn * (1 - drive))
    var shoulders = axis(chestTurn * (blocked ? 0.25 : planted ? 1.27 : 1) + powerCoil * (1 - 1.8 * ramp(time,-0.12,0.12)) * coil
      + moveTurn * (1 - (backhand ? coil : drive)))
    if let measured, swing.style == .serve || swing.style == .overhead {
      let blend = 0.83 * motionWeight
      hips = unit(hips + (axis(max(-1.55,min(1.4,measured.hipYaw)))-hips)*blend,fallback:right)
      shoulders = unit(shoulders + (axis(max(-1.80,min(1.52,measured.chestYaw)))-shoulders)*blend,fallback:right)
    }
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
    let overheadLoad = swing.style == .serve || activePower == .overhead
    let tiltAmount: Float = activePower == .ace || activePower == .overhead ? 0.13 : 0.095
    var shoulderTilt = overheadLoad ? tiltAmount * (ramp(time,-0.46,-0.20) - 1.70 * ramp(time,-0.15,0.015)) * finish : 0
    if let measured, overheadLoad {
      shoulderTilt += (measured.tilt-shoulderTilt)*motionWeight*0.60
    }
    let halfWidth = sqrt(max(0.002,0.22*0.22-shoulderTilt*shoulderTilt))
    pose[.leftShoulder] = chest - shoulders * halfWidth + up * shoulderTilt
    pose[.rightShoulder] = chest + shoulders * halfWidth - up * shoulderTilt
    // Track the knees outward over the wider base as the feet plant for the shot.
    let kneeOut = right * (0.15 + 0.40 * kneeLoad)
    pose[.leftKnee] = hinge(pose[.leftHip], pose[.leftShoe], length: 0.47, bend: forward - kneeOut)
    pose[.rightKnee] = hinge(pose[.rightHip], pose[.rightShoe], length: 0.47, bend: forward + kneeOut)
    pose[.head] = chest + up * 0.23 + forward * 0.042 + (reachDirection * 0.14 - up * 0.09) * dive

    // Keep the head quiet through impact, then pick up the outgoing ball.
    let watch = elapsed.map { $0 < 0.14 } == true ? hitPoint : game.worldBall
    let sight = watch - pose[.head]
    let forwardDistance = max(0.28, simd_dot(sight, forward))
    let yaw = max(-0.88, min(0.88, atan2(simd_dot(sight,right),forwardDistance)))
    let pitch = max(-0.55, min(0.85, atan2(sight.y,max(0.3,hypot(sight.x,sight.z)))))
    let wanted = SIMD2<Float>(yaw, pitch) * readiness
    let rate: Float = reduceMotion ? 6 : 14
    gaze += (wanted - gaze) * (1 - exp(-rate * Float(max(dt,0))))
    pose.gaze = gaze

    let ready = local(0.16, atNet ? 1.48 : 1.29, 0.43)
    var strings: CourtPoint3D
    var shaft: CourtPoint3D
    if blocked {
      // Meet the ball in front with a firm face and only a short extension.
      let set = local(sideOfBall * 0.38, max(0.58, strike.y), 0.34)
      strings = ready + (set - ready) * load
      strings += (strike - strings) * ramp(time, -0.09, 0)
      strings += (forward * 0.14 + up * 0.09) * ramp(time, 0, 0.09)
      strings += (ready - strings) * (1 - finish)
      shaft = up * 0.78 + right * sideOfBall * 0.72
    } else if backhand {
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
    } else if swing.style == .serve, let measured {
      // The tracked wrist leads. The racket drops behind the back, then its
      // long axis comes up on edge before the forearm turns the strings through.
      let trophy = unit(right*0.26+up*0.91-forward*0.34,fallback:up)
      let drop = unit(-right*0.28-up*0.92-forward*0.32,fallback:-up)
      let extensionAxis = unit(up*0.98+right*0.12+forward*0.15,fallback:up)
      let finishAxis = unit(-right*0.68-up*0.70+forward*0.23,fallback:-up)
      let descend = ramp(time,-0.33,-0.145)
      shaft = trophy+(drop-trophy)*descend
      shaft += (extensionAxis-shaft)*ramp(time,-0.135,-0.004)
      shaft += (finishAxis-shaft)*ramp(time,0.025,0.235)
      shaft = unit(shaft,fallback:up)
      let palm = pose[.rightShoulder]+relative(measured.hand)*0.665
      let capturedStrings = palm+shaft*0.49
      strings = ready+(capturedStrings-ready)*motionWeight
      let lock = ramp(time,-0.11,0)*(1-ramp(time,0,0.19))
      strings += (strike-strings)*lock
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
    if volley && !reduceMotion && time < 0 {
      let prep = CapturedTransitions.sample("volley", seconds: time+0.52)
      let blend = 1-ramp(time,-0.16,-0.015)
      strings += (right * prep.hand.x * sideOfBall + up * prep.hand.y) * (0.55*blend)
      shaft += right * (prep.hand.x*blend) + forward * (prep.hand.y*blend)
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
    // The grip is half a metre behind the strings. Reorient it toward a reachable
    // wrist before asking the shoulder to reach. The recorded impact stays fixed.
    let armReach: Float = 0.68, handleToStrings: Float = 0.49
    let twoHands = backhand && swing.pose.supportHandOnGrip && !blocked && rest < 0.05
    func makeRoom(at shoulder: BodyJoint, handle: Float) {
      let ray = strings-pose[shoulder], distance = simd_length(ray)
      let extra = distance-armReach-handle
      guard extra > 0 else { return }
      let direction = ray/distance
      let reach = direction * (hit ? extra : min(0.13,extra))
      // Reach with the trunk. Once the spine is inclined, move the base
      // with it so the distance between the rib cage and pelvis stays human.
      let spine = chest+reach-pelvis
      let baseShift = spine - unit(spine,fallback:up)*min(simd_length(spine),0.536)
      for joint: BodyJoint in [.leftHip,.rightHip,.leftKnee,.rightKnee,.leftShoe,.rightShoe] {
        pose[joint] += baseShift
      }
      pelvis += baseShift; chest += reach
      for joint: BodyJoint in [.leftShoulder,.rightShoulder,.head] { pose[joint] += reach }
      if !hit { strings -= direction * max(0,extra-simd_length(reach)) }
    }
    func limitWrist(at shoulder: BodyJoint, handle: Float, length: Float, minimum: Bool = false) {
      let ray = strings-pose[shoulder], distance = simd_length(ray)
      let wristDistance = simd_length(ray-shaft*handle)
      guard distance > 0.001, minimum ? wristDistance < length : wristDistance > length else { return }
      let line = ray/distance
      let cosine = max(-1,min(1,(distance*distance+handle*handle-length*length)/(2*distance*handle)))
      let planar = unit(shaft-line*simd_dot(shaft,line),fallback:unit(simd_cross(line,right),fallback:forward))
      shaft = unit(line*cosine+planar*sqrt(max(0,1-cosine*cosine)),fallback:line)
    }
    makeRoom(at:.rightShoulder,handle:handleToStrings)
    if twoHands {
      makeRoom(at:.leftShoulder,handle:handleToStrings-0.095)
      // Both wrists share a handle. Project the shaft onto the intersection
      // of their reach cones before placing the two palms.
      for _ in 0..<3 {
        limitWrist(at:.rightShoulder,handle:handleToStrings,length:armReach)
        limitWrist(at:.leftShoulder,handle:handleToStrings-0.095,length:armReach)
      }
    }
    if swing.style == .serve {
      let extensionWeight = ramp(time,-0.085,-0.004)*(1-ramp(time,0.018,0.11))
      limitWrist(at:.rightShoulder,handle:handleToStrings,length:0.654*extensionWeight,minimum:true)
    }
    limitWrist(at:.rightShoulder,handle:handleToStrings,length:armReach)
    pose[.strings] = strings
    pose[.grip] = strings - shaft * 0.49
    var across = unit(simd_cross(shaft, forward + up * (volley ? 0.22 : 0.08)), fallback: right)
    if swing.style == .serve || swing.style == .overhead {
      // Approach the ball edge-first; square the string bed at impact.
      let roll = (-0.91 * (1-ramp(time,-0.09,0)) + 0.76*ramp(time,0,0.115))*motionWeight
      across = simd_quatf(angle:roll,axis:shaft).act(across)
    }
    pose[.racketEdge] = strings + across * 0.132
    var offHand = pose[.leftShoulder] - shoulders * (0.18 + drive * 0.12) + forward * 0.23 - up * 0.18
    if let measured, !backhand && swing.style != .serve && swing.style != .overhead {
      offHand += (pose[.leftShoulder]+relative(measured.support)*0.62-offHand)*motionWeight*0.65
    }
    if swing.pose.supportHandOnGrip { offHand = pose[.grip] + shaft * 0.095 }
    if rush > 0.12 && !reduceMotion && !waiting && !jumping && dive == 0 {
      // The free arm counterbalances the opposite shoe when chasing a wide ball.
      let chase = rush*(1-load*finish)*(1-rest)
      let stride = min(1,max(-1,simd_dot(pose[.rightShoe]-pose[.leftShoe],forward)/0.48))
      let pumping = pose[.leftShoulder]-up*(0.36+stride*0.07)-right*0.10+forward*(0.12-stride*0.22)
      offHand += (pumping-offHand)*chase
    }
    if dive > 0 { offHand += (chest - up * 0.32 - reachDirection * 0.20 - offHand) * dive }
    offHand += (local(-0.29, 0.85, 0.06) - offHand) * rest
    if let service {
      let t = Float(service.tossProgress ?? 0)
      let release = ramp(t,0.04,0.43)
      let fold = ramp(t,0.57,0.94)
      let tossHand = local(-0.32 + 0.11 * release, 1.05 + 1.16 * release, 0.17 + 0.045 * release)
      offHand = tossHand + (chest - shoulders * 0.11 + forward * 0.13 - tossHand) * fold
    } else if swing.style == .serve, let after = elapsed {
      let tuck = 1 - ramp(Float(after),0.10,0.31)
      offHand += (chest - shoulders * 0.11 + forward * 0.13 - offHand) * tuck
    } else if swing.style == .overhead && arrival != nil { offHand = local(-0.29, 1.9, 0.19) }
    if side == 0 && game.flight?.acknowledge == true && game.isResolvingPoint { offHand = local(-0.24, 2.03, 0.12) }
    let freeReach = offHand-pose[.leftShoulder]
    if simd_length_squared(freeReach) > armReach*armReach {
      offHand = pose[.leftShoulder]+unit(freeReach,fallback:forward)*armReach
    }
    pose[.leftHand] = offHand
    var rightPole = unit(right-up*0.5-forward,fallback:right)
    var leftPole = unit(-right-up*0.5-forward,fallback:-right)
    if let measured {
      let blend = motionWeight*0.87
      rightPole += (unit(relative(measured.elbow),fallback:rightPole)-rightPole)*blend
      leftPole += (unit(relative(measured.supportElbow),fallback:leftPole)-leftPole)*blend
    }
    pose[.rightElbow] = hinge(pose[.rightShoulder], pose[.grip], length: 0.34, bend: rightPole)
    pose[.leftElbow] = hinge(pose[.leftShoulder], offHand, length: 0.34, bend: leftPole)
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
