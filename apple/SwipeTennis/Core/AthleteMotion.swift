import Foundation
import simd

enum BodyJoint: Int, CaseIterable {
  case leftShoe, rightShoe, leftKnee, rightKnee, leftHip, rightHip
  case leftShoulder, rightShoulder, leftElbow, rightElbow, leftHand, grip, head, strings, racketEdge
}

struct AthletePose {
  private var joints = Array(repeating: CourtPoint3D.zero, count: BodyJoint.allCases.count)
  var hairSway = SIMD2<Float>.zero
  var heelPitch: Float = 0
  var footRoll = SIMD2<Float>.zero
  var fingerCurl = SIMD2<Float>(0.30,0.92)
  var supportGrip: Float = 0
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
    result.hairSway += (other.hairSway-hairSway)*fraction
    result.fingerCurl += (other.fingerCurl-fingerCurl)*fraction
    result.supportGrip += (other.supportGrip-supportGrip)*fraction
    result.footRoll += (other.footRoll-footRoll)*fraction
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
  private var returnLanding: (left: CourtPoint3D, right: CourtPoint3D)?
  private var gaze = SIMD2<Float>.zero
  private var hair = SIMD2<Float>.zero, hairVelocity = SIMD2<Float>.zero
  private var lastShoulderYaw: Float?
  private var lastHipYaw: Float?
  private var lastVelocity: CourtPoint3D?
  private var acceleration = CourtPoint3D.zero
  private var swing = StrokeAnimation()
  private var spacing: Float = 0, spacingAtImpact: Float = 0
  private var hitPoint = CourtPoint3D.zero
  private var previousStrings: CourtPoint3D?
  private var carryingPalm: CourtPoint3D?
  private var carryingAxis: CourtPoint3D?
  private var freePalm: CourtPoint3D?
  private var elbowPlanes = [CourtPoint3D?](repeating: nil, count: 2)

  private var upperArmOffsets = [CourtPoint3D?](repeating: nil, count: 2)

  /// Transport each bend plane with the arm. Near full extension a tiny wrist
  /// change otherwise selects the opposite bend plane and flips the elbow.
  private mutating func elbow(_ index: Int, shoulder: CourtPoint3D, palm: CourtPoint3D,
                              preferred: CourtPoint3D, dt: Float, driving: Bool) -> CourtPoint3D {
    let axis = unit(palm-shoulder, fallback: [0,-1,0])
    func planar(_ v: CourtPoint3D) -> CourtPoint3D { v-axis*simd_dot(v,axis) }
    let proposal = planar(preferred)
    let fallback = unit(simd_cross(axis, abs(axis.x) < 0.9 ? [1,0,0] : [0,0,1]), fallback: [0,0,1])
    var plane = unit(proposal, fallback: fallback)
    if let prior = elbowPlanes[index], dt > 0 {
      var carried = unit(planar(prior), fallback: plane)
      if driving, let offset = upperArmOffsets[index] {
        // Of all elbows that reach the handle, start with the one nearest
        // the previous upper arm in shoulder space. This keeps a turning
        // wrist from swinging the elbow around the handle on a low drive.
        let nearest = planar(offset)
        let weight = ramp(simd_length(nearest),0.035,0.15)
        carried = unit(carried+(unit(nearest,fallback:carried)-carried)*weight,fallback:carried)
      }
      let angle = atan2(simd_dot(simd_cross(carried,plane),axis),simd_dot(carried,plane))
      let turn = min(1,simd_length(proposal)*3) * min(1,20*dt)
      plane = simd_quatf(angle:angle*turn,axis:axis).act(carried)
    }
    elbowPlanes[index] = plane
    let joint = hinge(shoulder,palm,length:0.34,bend:plane)
    upperArmOffsets[index] = joint-shoulder
    return joint
  }
  private var transitionStart: CourtPoint3D?
  private var transitionTime: Double = 0

  mutating func sample(game: PracticeEngine, side: Int, hit: Bool, dt: Double, reduceMotion: Bool) -> AthletePose {
    let player = game.players[side]
    var centre = player.pos.world()
    let velocity = player.velocity.world()
    if let prior = lastVelocity, dt > 0 {
      let change = (velocity-prior)/Float(dt)
      // A remote update or a point ending can stop the root in one sample.
      let load = change*min(1,16/max(0.001,simd_length(change)))
      acceleration += (load-acceleration)*(1-exp(-Float(dt)*13))
    }
    lastVelocity = velocity
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
      arrival = max(0, flight.time(at: phase) - flight.elapsed)
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
      if horizontal > 1.40 + Float(remaining) * (game.showsGoldenContact(side) ? 9.0 : 6.0) { target = nil; arrival = nil }
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
    // While the runner still has time to plant, start the unit turn on the
    // approach. The last contact reading decides whether the shot is a block.
    let closingOnBall = game.contactGuide(side).map { player.destination.distance(to: $0) < PracticeEngine.contactRadius+0.18 } ?? false
    let timeToPlant = max(0, (incomingGap ?? 0)-PracticeEngine.contactRadius) / max(1.5,player.velocity.length)
    let canPrepare = closingOnBall && (arrival ?? 0) > timeToPlant+0.23
    let blocked = !canPrepare && (quality == .stretched || quality == .diving) && swing.style != .serve && swing.style != .overhead
    let planted = quality == .planted && swing.style == .groundstroke
    let volley = swing.style == .volley
    let forehand = swing.style == .groundstroke && swing.stance == .forehand
    let fullForehand = forehand && !blocked && (arrival != nil || elapsed != nil)
    // Make an adjustment step within yellow on a prepared forehand that
    // would otherwise crowd the hitting hip. Keep the plant through contact.
    if hit { spacingAtImpact = spacing }
    var wantedSpacing: Float = 0
    if fullForehand && !reduceMotion {
      if elapsed != nil {
        wantedSpacing = spacingAtImpact*(1-ramp(time,0.56,0.88))
      } else {
        let feetX = closingOnBall ? Float(player.destination.x) : centre.x
        let room = (strike.x-feetX)*sign
        wantedSpacing = min(0.43,max(0,0.54-room))*ramp(time,-0.84,-0.44)
      }
    }
    let stepWidth = Float(max(0,dt)) * (elapsed == nil ? 1.42 : 1.66)
    spacing += max(-stepWidth,min(stepWidth,wantedSpacing-spacing))
    centre -= right*spacing
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
    let receiver = ReceiverFootwork.pose(game: game, side: side, reduceMotion: reduceMotion)
    let beat = Float(game.time) * 8.7 + Float(side)*1.45
    let toeBounce: Float = waiting && service != nil && !reduceMotion ? 0.031 * pow(max(0,sin(beat)),2) : 0
    // A timed tap and the receiver's split are one physical jump.
    let receiveLift = min(receiver.left.y,receiver.right.y)
    let hop: Float = reduceMotion ? 0 : max(0,0.115*sin(split * .pi)-receiveLift)+toeBounce
    let landing = game.serveLanding.flatMap { $0.server == side ? $0.progress : nil }
    let effort = player.netEffort
    let effortTime = effort.map { Float(game.time - $0.impactTime) } ?? 1
    let windup = effort.map { Float(min(-0.001, $0.startTime - $0.impactTime)) } ?? -0.21
    let actionScale: Float = reduceMotion ? 0.72 : 1
    let dive = effort?.stroke == .dive ? ramp(effortTime, windup, 0) * (1 - ramp(effortTime, 0.18, Float(NetStroke.dive.recovery)-0.04)) * actionScale : 0
    let landingBrace = effort?.stroke == .dive
      ? ramp(effortTime,-0.015,0.16)*(1-ramp(effortTime,0.33,0.78))*actionScale : 0
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
      gather = fullForehand ? ramp(time,-0.335,-0.18) : ramp(time,-0.34,-0.145)
      // On a knee-high drive, stay down through the ball. Straightening at the
      // waist-high timing forces the wrist to dip steeply to reach the same contact.
      let lowDrive = swing.style == .groundstroke && !blocked ? lowBall : 0
      extend = fullForehand ? ramp(time,-0.19+0.14*lowDrive,0.046+0.18*lowDrive)
        : ramp(time,-0.14+0.055*lowDrive,0.055+0.102*lowDrive)
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
    if receiver.landing, let offsets = returnLanding {
      feet.landSplit(leftOffset: offsets.left, rightOffset: offsets.right)
    }
    if receiver.finalFlight {
      returnLanding = (relative([receiver.left.x,0,receiver.left.z]), relative([receiver.right.x,0,receiver.right.z]))
    } else { returnLanding = nil }
    // Step into a settled drive on the lead shoe, then load the outside leg.
    // These are ground targets for individual steps, never translations of a planted sole.
    let driveSet: Float = swing.style == .groundstroke && !blocked
      ? ramp(time,-0.74,-0.34)*(1-ramp(time,0.21,0.50))*(1-ramp(speed,1.7,4.5)) : 0
    let stanceDepth: Float = planted ? 0.22 : 0.16
    let leadStep = forward*stanceDepth - right*sideOfBall*0.056
    let outsideStep = forward*(-0.105+0.19*ramp(time,-0.02,0.19)) + right*sideOfBall*0.085
    let leftSet = (backhand ? outsideStep : leadStep)*driveSet
    let rightSet = (backhand ? leadStep : outsideStep)*driveSet
    let lateralDriveTime: Float? = !reduceMotion && game.phase == .live && swing.style == .groundstroke
      && effort == nil && activePower == nil && (arrival != nil || elapsed != nil) ? time : nil
    feet.advance(centre: centre, velocity: velocity, destination: player.destination.world()-right*spacing,
      facing: sign, strideBias: step+leftSet, dt: Float(dt), readiness: max(stance,driveSet), surface: game.settings.surface,
      rightStrideBias: rightSet, lateralDriveTime: lateralDriveTime)
    let recoveryRun = game.phase == .live && game.flight?.hitter == side && !game.followingApproach[side] && abs(player.velocity.x) > 0.9
    let captured = capture.step(speed:speed,remaining:player.pos.distance(to:player.destination),recovering:recoveryRun,dt:Float(dt))
    var pose = AthletePose()
    pose.heelPitch = receiver.heel + readiness * 0.015 + 0.045 * rush + (swing.style == .groundstroke ? 0.195 : 0.17) * pushOff
    let ankleHeight = 0.06 + 0.14 * sin(pose.heelPitch) + hop + leap
    let splitWidth = 0.05 * ramp(sinceSplit, 0.02, 0.155) * (1 - ramp(sinceSplit, 0.24, 0.4)) * readiness
    let stanceWidth = 0.175 + stance * 0.07
    pose[.leftShoe] = (reduceMotion ? centre - right * stanceWidth : feet.left) + up * ankleHeight
    pose[.rightShoe] = (reduceMotion ? centre + right * stanceWidth : feet.right) + up * ankleHeight
    pose[.leftShoe] += relative(receiver.left)
    pose[.rightShoe] += relative(receiver.right)
    pose[.leftShoe] -= right * splitWidth
    pose[.rightShoe] += right * splitWidth
    pose[.leftShoe] += (up * 0.18 - reachDirection * 0.45) * dive + forward * (0.19 * jump)
    pose[.rightShoe] += (up * 0.29 - reachDirection * 0.51) * dive + (up * 0.17 - forward * 0.24) * jump
    if highOverhead {
      // The rear leg passes the front leg after impact on a jumping overhead.
      // Keep the scissors in the airborne part of the stroke.
      let exchange = jump*ramp(time,-0.075,0.17)
      pose[.rightShoe] += forward*(0.40*exchange)
      pose[.leftShoe] -= forward*(0.31*exchange)
    }
    if landingBrace > 0 {
      // The trailing shoe lands first. The other knee gathers under the hips
      // while the free hand takes weight, then both feet recover to standing.
      pose[.rightShoe].y += (0.085-pose[.rightShoe].y)*landingBrace
      pose[.leftShoe] += reachDirection*(0.23*landingBrace)
      pose[.leftShoe].y += (0.10-pose[.leftShoe].y)*landingBrace
    }
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
    if let landing {
      pose[.rightShoe] += (up * 0.32 - forward * 0.24) * Float(sin(landing * .pi))
    }
    // Uncoil the pelvis first, the ribcage second, and release the racket last.
    // On a two-handed backhand the right shoulder points toward the net in preparation.
    // The pelvis opens while the shoulders still hold the coil. The hands then travel through.
    let coil = ramp(time, -0.72, -0.23) * finish
    var hipTurn = backhand ? coil * (0.56 - 1.03 * ramp(time, -0.20, 0.035))
      : sideOfBall * drive * (-0.48 + 0.94 * ramp(time, -0.16, 0.05))
    var chestTurn = backhand ? coil * (1.30 - 2.18 * ramp(time, -0.115, 0.125))
      : sideOfBall * drive * (-0.96 + 1.82 * ramp(time, -0.09, 0.10)) * (volley ? 0.42 : 1)
    if swing.style == .groundstroke && !blocked {
      // Turn as a unit while there is time to read the bounce. The belt
      // starts opening while the lead shoulder is still pointing upcourt.
      let handed: Float = backhand ? 1 : -1
      let set = ramp(time,-0.79,backhand ? -0.32 : -0.38)
      let reset = 1-ramp(time,0.24,0.58)
      let belt = backhand ? Float(0.91) : 0.98
      let ribs = backhand ? Float(1.61) : 1.68
      // The outside knee starts to extend before contact. Let that release
      // lead the belt, with the chest following while the hands are still low.
      let plantDrive = feet.plantedSide == 0 ? 0 : pushOff
      let beltRelease = ramp(time,backhand ? -0.19 : -0.225,backhand ? 0.082 : 0.065)
      let ribRelease = ramp(time,backhand ? -0.165 : -0.155,backhand ? 0.145 : 0.135)
      hipTurn = handed*set*(belt-(belt+0.65)*beltRelease-0.085*plantDrive)*reset
      chestTurn = handed*set*(ribs-(ribs+1.20)*ribRelease-(backhand ? 0.065*plantDrive : 0))*reset
    }
    let running = reduceMotion ? 0 : feet.runBlend
    let shuffleTurn = min(0.28,abs(Float(player.velocity.x))*0.065)*(player.velocity.x*Double(sign) >= 0 ? Float(-1) : 1)
    let moveTurn = shuffleTurn+(feet.runYaw-shuffleTurn)*running
    let armSwing = feet.armStride * (1-drive)
    let runner = running > 0.001 ? RunningStride.sample(phase:feet.gaitPhase) : nil
    let runWeight = running*(1-drive)
    let runningHips = runner.map { $0.trunk.x*runWeight } ?? (0.10*armSwing)
    let runningShoulders = runner.map { $0.trunk.y*runWeight } ?? (-0.13*armSwing)
    pose.footRoll = reduceMotion ? .zero : feet.footPitch
    pose.shoeYaw += SIMD2<Float>(repeating:moveTurn*0.73*(1-drive))
    let transfer = ramp(time,-0.115,0.10)*(1-ramp(time,0.27,0.54))
    let rear = backhand ? 0 : 1, lead = 1-rear
    // The outside heel releases as the hips open. The lead heel takes the load.
    pose.shoeYaw[rear] += -sideOfBall*driveSet*(0.61-0.95*transfer)
    pose.shoeYaw[lead] += -sideOfBall*driveSet*(0.23-0.40*transfer)
    if !reduceMotion {
      pose.footRoll[rear] += 0.34*transfer*driveSet
      pose.footRoll[lead] -= 0.13*pushOff*driveSet
    }
    func axis(_ angle: Float) -> CourtPoint3D { right * cos(angle) + forward * sin(angle) }
    let weight = right * sideOfBall * (0.09*kneeLoad-0.072*transfer*driveSet)
    let approaching = game.followingApproach[side]
    let forwardRun = min(1, max(0, simd_dot(player.velocity.world(), forward) / 5))
    let weightForward = forward * ((0.08 + 0.14 * volleyStep) * drive)
    let shoeMid = (pose[.leftShoe] + pose[.rightShoe]) / 2
    let offset = shoeMid - centre
    let support = CourtPoint3D(max(-0.19, min(0.19, offset.x)), 0, max(-0.14, min(0.14, offset.z)))
    var pelvis = centre + support * 0.72 + weight + weightForward + up * (0.99 - bend + 0.022 * pushOff + hop + leap)
    if feet.plantedSide != 0 {
      // Carry the belt over the outside knee as the shot loads, then send it
      // toward the stepping shoe while the shoulders finish their rotation.
      let pressure = ramp(time,-0.33,-0.16)*(1-ramp(time,-0.08,0.11))
      pelvis += right*feet.plantedSide*((fullForehand ? 0.119 : 0.078)*pressure-0.058*feet.push)
      pelvis.y -= 0.025*pressure+0.038*feet.push
    }
    if fullForehand {
      let grounded = driveSet*(1-ramp(speed,1.7,3.4))
      pelvis += forward*(0.09*pushOff*grounded)
      pelvis.y += 0.032*(1-lowBall)*pushOff*grounded
    }
    if !reduceMotion { pelvis.y += max(-0.07,min(0.06,captured.pelvis)) }
    pelvis += relative(receiver.hips) + forward*0.065*transfer*driveSet
    pelvis.y += (runner?.trunk.z ?? 0)*runWeight
    pelvis += (reachDirection * 0.16 - up * 0.47) * dive
    // Lead the drive with the hips. On the serve, hold the tossing shoulder up until release.
    let powerCoil: Float = activePower == .rally ? (backhand ? 0.18 : -0.24) : activePower == .ace ? -0.35 : 0
    var hips = axis(hipTurn + runningHips + powerCoil * (1 - 1.6 * ramp(time,-0.20,0)) * coil + moveTurn * (1 - drive))
    var shoulders = axis(runningShoulders + chestTurn * (blocked ? 0.25 : 1) + powerCoil * (1 - 1.8 * ramp(time,-0.12,0.12)) * coil
      + moveTurn * (1 - (backhand ? coil : drive)))
    if let measured, swing.style == .serve || swing.style == .overhead {
      let blend = 0.83 * motionWeight
      hips = unit(hips + (axis(max(-1.55,min(1.4,measured.hipYaw)))-hips)*blend,fallback:right)
      shoulders = unit(shoulders + (axis(max(-1.80,min(1.52,measured.chestYaw)))-shoulders)*blend,fallback:right)
    }
    if let measured, swing.style == .groundstroke && !blocked {
      // Retain each player's contact geometry. The captured chest follows
      // the pelvis through preparation and turns through the outgoing ball.
      let amount = motionWeight*(planted ? 0.17 : 0.20)
      hips = unit(hips+(axis(max(-1.25,min(1.12,measured.hipYaw)))-hips)*amount*0.48,fallback:right)
      var capturedYaw = measured.chestYaw
      if forehand, time > -0.23, time < -0.025, let loaded = CapturedStroke.sample(.forehand,at:-0.23) {
        // Keep the non-hitting shoulder closed during the initial pelvic release.
        capturedYaw = loaded.chestYaw+(capturedYaw-loaded.chestYaw)*ramp(time,-0.09,-0.025)
      }
      shoulders = unit(shoulders+(axis(max(-1.62,min(1.66,capturedYaw)))-shoulders)*amount,fallback:right)
    }
    // A change in the estimated contact window can switch a run into a block
    // within one tick. The pelvis and rib cage still have rotational inertia.
    func continuousAxis(_ line: CourtPoint3D, previous: Float?, speedLimit: Float) -> CourtPoint3D {
      guard let previous, dt > 0 else { return line }
      let next = atan2(simd_dot(line,forward),simd_dot(line,right))
      let gap = atan2(sin(next-previous),cos(next-previous))
      let limit = speedLimit*Float(dt)
      return axis(previous+min(limit,max(-limit,gap)))
    }
    let shoulderRelease = ramp(time,-0.16,-0.045)*(1-ramp(time,0.13,0.29))
    hips = continuousAxis(hips,previous:lastHipYaw,speedLimit:6.2+8.5*shoulderRelease)
    lastHipYaw = atan2(simd_dot(hips,forward),simd_dot(hips,right))
    shoulders = continuousAxis(shoulders,previous:lastShoulderYaw,speedLimit:8.5+16*shoulderRelease)
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
    func ankleForLeg(_ index: Int) -> CourtPoint3D {
      // The pose's shoe marker tracks sole clearance. A pivoting shoe brings
      // the ankle up even while the ball of the foot remains on the court.
      let rolling = sin(pose.heelPitch+pose.footRoll[index])-sin(pose.heelPitch)
      return pose[index == 0 ? .leftShoe : .rightShoe] + up*(0.18*max(0,rolling))
    }
    for (shoe, hipOffset) in [(ankleForLeg(0), -hips * 0.14), (ankleForLeg(1), hips * 0.14)] {
      let leg = pelvis + hipOffset - shoe
      let legLength: Float = 0.936
      let height = sqrt(max(0.30, legLength * legLength - leg.x * leg.x - leg.z * leg.z))
      pelvis.y = min(pelvis.y, shoe.y + height)
    }
    // Drive the torso in the direction of the first step. When braking into
    // the outside leg the acceleration reverses before the feet do.
    var movingLean = velocity*0.006+acceleration*0.0065
    movingLean *= min(1,0.135/max(0.001,simd_length(movingLean)))*rush*(1-0.62*drive)
    if reduceMotion { movingLean *= 0.30 }
    var chest = pelvis + up * (0.49 - 0.018 * kneeLoad) + movingLean
      + forward * (0.015 + receiver.lean + kneeLoad * (0.065 + lowBall * 0.08))
    if swing.style == .groundstroke && !blocked {
      let throughLow = lowBall*ramp(time,-0.28,-0.09)*(1-ramp(time,0.08,0.25))
      chest += forward*0.105*throughLow - up*0.044*throughLow
    }
    // Lean into the low first volley; retain the shot finish as the first approach step starts.
    if swing.style == .serve {
      let arch = ramp(time,-0.55,-0.26)*(1-ramp(time,-0.195,-0.012))
      let carry = ramp(time,-0.095,0.082)*(1-ramp(time,0.17,0.45))
      chest += forward*(-0.087*arch+0.10*carry)-right*0.048*arch
    }
    if volley { chest += (right * sideOfBall * 0.10 + forward * 0.12) * kneeLoad }
    if approaching { chest += forward * (0.12 * forwardRun) }
    chest += (reachDirection * 0.39 - up * 0.22) * dive + wrongStep
    chest.y -= 0.045*landingBrace
    pose[.leftHip] = pelvis - hips * 0.14; pose[.rightHip] = pelvis + hips * 0.14
    let overheadLoad = swing.style == .serve || swing.style == .overhead
    let tiltAmount: Float = activePower == .ace || activePower == .overhead ? 0.13 : 0.095
    var shoulderTilt = overheadLoad ? tiltAmount * (ramp(time,-0.46,-0.20) - 1.70 * ramp(time,-0.15,0.015)) * finish : 0
    if let measured, overheadLoad {
      shoulderTilt += (measured.tilt-shoulderTilt)*motionWeight*0.60
    }
    shoulderTilt += simd_dot(movingLean,shoulders)*0.19*(1-drive)
    if swing.style == .groundstroke && !blocked { shoulderTilt += sideOfBall*0.042*low }
    if backhand && swing.style == .groundstroke && !blocked {
      // The left shoulder dips with the low backswing and comes up behind
      // the left hand as it drives the two-handed finish.
      shoulderTilt += 0.041*lowBall*(ramp(time,-0.10,0.14)*finish-kneeLoad)
    }
    shoulderTilt -= 0.052*landingBrace
    let halfWidth = sqrt(max(0.002,0.22*0.22-shoulderTilt*shoulderTilt))
    pose[.leftShoulder] = chest - shoulders * halfWidth + up * shoulderTilt
    pose[.rightShoulder] = chest + shoulders * halfWidth - up * shoulderTilt
    let chestYaw = atan2(simd_dot(shoulders,forward),simd_dot(shoulders,right))
    if dt>0 && !reduceMotion {
      let tick = min(0.033,Float(dt)), prev = lastShoulderYaw ?? chestYaw
      let turning = atan2(sin(chestYaw-prev),cos(chestYaw-prev))/Float(dt)
      let lateral = Float(player.velocity.x)*sign
      // A tied ponytail trails a shoulder turn and settles after the feet land.
      let wanted = SIMD2<Float>(max(-0.48,min(0.48,-0.044*turning-0.025*lateral)),
        max(-0.26,min(0.38,simd_dot(player.velocity.world(),forward)*0.035 + 0.16*pushOff - 0.18*landingLoad)))
      hairVelocity += ((wanted-hair)*118-hairVelocity*16)*tick
      hair += hairVelocity*tick
    } else if reduceMotion { hair = .zero; hairVelocity = .zero }
    lastShoulderYaw = chestYaw; pose.hairSway = hair
    // Track the knees outward over the wider base as the feet plant for the shot.
    let kneeForward = unit(forward*cos(moveTurn)-right*sin(moveTurn),fallback:forward)
    for i in 0...1 {
      let left = i == 0
      let toeTurn = 0.27*(lastHipYaw ?? 0)+pose.shoeYaw[i]
      let toeFront = forward*cos(toeTurn)-right*sin(toeTurn)
      let overToes = toeFront + axis(toeTurn)*(left ? -1 : 1)*(0.15+0.35*kneeLoad)
      pose[left ? .leftKnee : .rightKnee] = hinge(pose[left ? .leftHip : .rightHip],
        ankleForLeg(i), length: 0.47, bend: overToes)
    }
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
    } else if swing.style == .groundstroke {
      let ray = strike-centre
      let path = GroundstrokePath(time: time, backhand: backhand,
        strike: [simd_dot(ray,right),ray.y,simd_dot(ray,forward)], rush: rush, power: activePower == .rally, shoulderHeight:pose[.rightShoulder].y)
      strings = centre+relative(path.strings)
      shaft = relative(path.shaft)
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
    } else if volley {
      let set = local(sideOfBall*0.46,max(1.05,strike.y+0.14),0.21)
      let follow = local(sideOfBall*0.51,max(0.72,min(1.6,strike.y+0.13)),0.66)
      strings = ready+(set-ready)*load
      strings += (strike-strings)*ramp(time,-0.105,0)
      strings += (follow-strings)*ramp(time,0,0.115)
      strings += (ready-strings)*(1-finish)
      let lag = ramp(time,-0.19,-0.065)*(1-ramp(time,-0.065,0))
      shaft = up*(0.86-drive*0.45-low*1.65)+right*sideOfBall*(0.25+drive*0.65)-forward*lag*0.12
      shaft += (-right*sideOfBall*1.6+up*0.48)*ramp(time,0,0.18)*finish
    } else if swing.style == .serve, let measured {
      // The tracked wrist leads. The racket drops behind the back, then its
      // long axis comes up on edge before the forearm turns the strings through.
      let trophy = unit(right*0.26+up*0.91-forward*0.34,fallback:up)
      let drop = unit(-right*0.28-up*0.92-forward*0.32,fallback:-up)
      let extensionAxis = unit(up*0.98+right*0.12+forward*0.15,fallback:up)
      let finishAxis = unit(-right*0.68-up*0.70+forward*0.23,fallback:-up)
      let descend = ramp(time,-0.33,-0.145)
      // Swing around the wrist on an arc. Linear interpolation between these
      // almost opposing directions makes the racket flip in the middle.
      func swingArc(_ from: CourtPoint3D, _ to: CourtPoint3D, _ phase: Float) -> CourtPoint3D {
        let turn = simd_quatf(from:from,to:to)
        return simd_slerp(simd_quatf(real:1,imag:.zero),turn,phase).act(from)
      }
      shaft = swingArc(trophy,drop,descend)
      shaft = swingArc(shaft,extensionAxis,ramp(time,-0.145,-0.004))
      shaft = swingArc(shaft,finishAxis,ramp(time,0.025,0.235))
      var palm = pose[.rightShoulder]+relative(measured.hand)*0.665
      // Keep the bent hitting arm beside the head while the tossing arm rises.
      // The racket head, rather than the wrist, drops behind the shoulder.
      let trophyWeight = ramp(time,-0.65,-0.39)*(1-ramp(time,-0.14,-0.044))
      let trophyPalm = pose[.rightShoulder]+right*0.14+up*0.23-forward*0.16
      palm += (trophyPalm-palm)*(0.87*trophyWeight)
      let crossing = ramp(time,0.068,0.23)*(1-ramp(time,0.34,0.58))
      let finishPalm = pose[.leftHip]+up*0.23+forward*0.14
      palm += (finishPalm-palm)*(0.82*crossing)
      let lock = ramp(time,-0.15,0)*(1-ramp(time,0,0.19))
      let impactPalm = strike-extensionAxis*0.49
      palm += (impactPalm-palm)*lock
      let capturedStrings = palm+shaft*0.49
      strings = ready+(capturedStrings-ready)*motionWeight
    } else {
      let existing = swing.pose
      let position = existing.racketCentre
      strings = local(Float(position.x) / 30, Float(position.y) / 30 + leap, 0.23 - 0.25 * kneeLoad)
      let lock = ramp(time, -0.18, 0) * (1 - ramp(time, 0, 0.19))
      strings += (strike - strings) * lock
      shaft = right * Float(-sin(existing.racketAngle)) + up * Float(cos(existing.racketAngle)) + forward * 0.18
    }
    if let measured, swing.style == .groundstroke && !blocked {
      let palm = pose[.rightShoulder] + relative(measured.hand)*0.64
      let recorded = palm+unit(shaft,fallback:up)*0.49
      let onBall = ramp(time,-0.11,-0.005)*(1-ramp(time,0.004,0.13))
      let difference = recorded-strings
      let amount = motionWeight*(1-onBall)*0.26
      strings += unit(difference,fallback:.zero)*min(0.37,simd_length(difference))*amount
    }
    let chestFront = unit(simd_cross(up,shoulders),fallback:forward)
    if swing.style == .groundstroke && !blocked && (arrival != nil || elapsed != nil) {
      // The hands trace the outside of the rotating rib cage on the wrap.
      // Holding a finish in court coordinates drags the forearm back through
      // the shirt when the shoulders continue opening under the racket.
      let wrap = ramp(time,0.052,0.245)*(1-ramp(time,0.34,0.57))
      let across = backhand ? Float(0.20) : -0.22
      let carry = ramp(time,0.16,0.31)
      let clearance: Float = backhand ? 0.32-0.085*carry : 0.29-0.15*carry
      let palm = chest + shoulders*across + up*(backhand ? 0.105+0.066*carry : 0.18+0.065*carry)
        + chestFront*clearance
      let blade = unit(-shoulders*sideOfBall*0.67 + up*0.45 - chestFront*0.55,fallback:up)
      let followShaft = unit(shaft,fallback:up)
      shaft = simd_slerp(simd_quatf(real:1,imag:.zero),simd_quatf(from:followShaft,to:blade),(backhand ? 0.55 : 0.72)*wrap).act(followShaft)
      strings += (palm+shaft*0.49-strings)*((backhand ? 0.65 : 0.84)*wrap)
    }
    if volley && !blocked && dive == 0 {
      // Keep the handle in front of the sternum on the punch. On a low
      // volley, turn the head of the racket down instead of folding the
      // forearm back into the abdomen to make the recorded contact.
      let window = ramp(time,-0.27,-0.10)*(1-ramp(time,0.11,0.29))
      let palm = chest+shoulders*(sideOfBall*0.20)+chestFront*0.31-up*(0.12+lowBall*0.23)
      let from = unit(shaft,fallback:up), to = unit(strings-palm,fallback:from)
      shaft = simd_slerp(simd_quatf(real:1,imag:.zero),simd_quatf(from:from,to:to),window*0.85).act(from)
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
      // The ball leaves the strings while the player is still travelling.
      // Carry the scoop with the shoulder, then fold the arm outside the
      // landing elbow; a racket left at impact passes through the runner's head.
      let scoop = ramp(effortTime,0,0.12)
      let gather = ramp(effortTime,0.21,0.59)
      let out = unit(reachDirection+right*0.20,fallback:reachDirection)
      let blade = unit(out+up*(0.06+0.44*scoop-0.52*gather),fallback:out)
      var followingPalm = pose[.rightShoulder]+out*(0.58-0.32*gather)
      followingPalm += right*(0.11+0.10*gather)
      // On the backhand side the racket passes across the front of the chest.
      // Give the bent elbow room in front as the near shoulder comes back up.
      let crossBody = max(0,-simd_dot(reachDirection,right))
      followingPalm += forward*((0.34+0.23*gather)*crossBody)
      followingPalm.y -= 0.10*crossBody*gather
      followingPalm.y += 0.11*scoop-0.24*gather
      let follow = ramp(effortTime,0,0.14)
      extensionPoint += (followingPalm+blade*0.49-extensionPoint)*follow
      strings += (extensionPoint - strings) * dive
      shaft += (blade-shaft)*dive
    }
    if volley && !reduceMotion && time < 0 {
      let prep = CapturedTransitions.sample("volley", seconds: time+0.52)
      let blend = 1-ramp(time,-0.16,-0.015)
      strings += (right * prep.hand.x * sideOfBall + up * prep.hand.y) * (0.55*blend)
      shaft += right * (prep.hand.x*blend) + forward * (prep.hand.y*blend)
    }
    // In a chase the grip travels beside the ribs, in opposition to the feet.
    // The outside plant releases this carry into the normal unit turn.
    let footSeparation = min(1,max(-1,simd_dot(pose[.rightShoe]-pose[.leftShoe],forward)/0.48))
    let stride = footSeparation*(1-running)+feet.armStride
    let carryAcross = axis(moveTurn)
    let carryForward = kneeForward
    let chaseCarry = reduceMotion || jumping || waiting ? 0 : rush*(0.15+0.85*running)*(1-drive)*(1-dive)*readiness
    func inHeading(_ v: CourtPoint3D) -> CourtPoint3D { carryAcross*v.x+up*v.y+carryForward*v.z }
    var runningGrip = pose[.rightShoulder]+carryAcross*0.12-up*(0.31-stride*0.034)+carryForward*(0.17+stride*0.16)
    if let runner {
      let palm = pose[.rightShoulder]+inHeading(runner.hand)*0.64
      runningGrip += (palm-runningGrip)*(running*0.78)
    }
    let runningShaft = unit(carryAcross*0.43+up*0.80+carryForward*(0.36+stride*0.12),fallback:up)
    strings += (runningGrip+runningShaft*0.49-strings)*chaseCarry
    shaft += (runningShaft-shaft)*chaseCarry
    if receiver.readyHands > 0 {
      let handle = chest + right*0.095 + forward*0.36 - up*0.22
      let blade = unit(up*0.82 + forward*0.45 - right*0.16, fallback: up)
      strings += (handle + blade*0.49 - strings)*receiver.readyHands
      shaft += (blade-shaft)*receiver.readyHands
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
    // Filter in shoulder space so court translation never delays the hand.
    // Release the constraint into impact to leave the actual ball on the strings.
    let delta = Float(max(0,dt))
    let release = ramp(time,-0.085,-0.005)*(1-ramp(time,0.012,0.095))
    if !hit, delta > 0, let previous = carryingPalm, let oldAxis = carryingAxis {
      let directionChange = simd_quatf(from:oldAxis,to:shaft)
      let rotation = min(1,(14+release*32)*delta/max(0.001,directionChange.angle))
      shaft = simd_slerp(simd_quatf(real:1,imag:.zero),directionChange,rotation).act(oldAxis)
      let desired = strings-shaft*0.49-pose[.rightShoulder]
      let change = desired-previous
      let distance = simd_length(change)
      let speed: Float = swing.style == .serve || swing.style == .overhead ? 8.5 : 7.5
      let amount = min(1,speed*delta/max(0.0001,distance))
      strings = pose[.rightShoulder]+previous+change*(amount+(1-amount)*release)+shaft*0.49
    }
    // The grip is half a metre behind the strings. Reorient it toward a reachable
    // wrist before asking the shoulder to reach. The recorded impact stays fixed.
    let preparedDrive = swing.style == .groundstroke && !blocked && dive == 0 && (arrival != nil || elapsed != nil)
    let armReach: Float = preparedDrive ? 0.615 + 0.035*release : volley && dive == 0 ? 0.60 : 0.66
    let handleToStrings: Float = 0.49
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
    if preparedDrive || swing.style == .serve || volley {
      limitWrist(at:.rightShoulder,handle:handleToStrings,length:volley ? 0.35 : 0.28,minimum:true)
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
    if dive > 0 {
      let reach = 0.60*dive*(1-ramp(effortTime,0.038,0.18))
      limitWrist(at:.rightShoulder,handle:handleToStrings,length:reach,minimum:true)
    }
    limitWrist(at:.rightShoulder,handle:handleToStrings,length:armReach)
    pose[.strings] = strings
    pose[.grip] = strings - shaft * 0.49
    var across = unit(simd_cross(shaft, forward + up * (volley ? 0.22 : 0.08)), fallback: right)
    if dive > 0 || swing.style == .lob {
      let normal = unit(forward*0.58+up*0.81,fallback:up)
      let openFace = unit(simd_cross(shaft,normal),fallback:across)
      let blend = max(dive, swing.style == .lob ? drive*0.82 : 0)
      across = unit(across+(openFace-across)*blend,fallback:openFace)
    }
    if fullForehand {
      // Show the strings to the side on the unit turn, approach edge-on and
      // roll the face across after extension. Square the face at impact.
      let set = ramp(time,-0.73,-0.39)*(1-ramp(time,-0.19,-0.02))
      let wrap = ramp(time,0.035,0.255)*(1-ramp(time,0.36,0.57))
      across = simd_quatf(angle:-0.92*set+0.98*wrap,axis:shaft).act(across)
    }
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
    let supportDistance: Float = backhand && (elapsed != nil || arrival != nil) ? 0.095 : 0.20
    if swing.pose.supportHandOnGrip { offHand = pose[.grip] + shaft*supportDistance }
    if forehand && !blocked && (arrival != nil || elapsed != nil) {
      let onThroat = 1-ramp(time,-0.48,-0.32)
      let fold = ramp(time,-0.15,0.085)
      let balance = pose[.leftShoulder] + right*0.38 + forward*0.28 - up*0.13
      let tucked = chest - shoulders*0.18 + chestFront*0.27 - up*0.22
      let left = balance+(tucked-balance)*fold
      offHand += (left-offHand)*ramp(time,-0.74,-0.45)*(1-ramp(time,0.31,0.57))
      let throat = pose[.grip]+shaft*0.205
      offHand += (throat-offHand)*onThroat
    }
    if rush > 0.12 && !reduceMotion && !waiting && !jumping && dive == 0 {
      // The free arm counterbalances the opposite shoe when chasing a wide ball.
      let chase = twoHands ? 0 : chaseCarry*(1-rest)
      var pumping = pose[.leftShoulder]-up*(0.36+stride*0.07)-carryAcross*0.10+carryForward*(0.12-stride*0.22)
      if let runner { pumping += (pose[.leftShoulder]+inHeading(runner.freeHand)*0.64-pumping)*running }
      offHand += (pumping-offHand)*chase
    }
    if dive > 0 { offHand += (chest - up * 0.32 - reachDirection * 0.20 - offHand) * dive }
    if landingBrace > 0 {
      var brace = pose[.leftShoulder] + reachDirection*0.13
      brace.y = 0.046
      offHand += (brace-offHand)*landingBrace
    }
    offHand += (local(-0.29, 0.85, 0.06) - offHand) * rest
    if let service {
      let t = Float(service.tossProgress ?? 0)
      let fold = ramp(t,0.57,0.94)
      let tossHand = ServiceToss.palm(feet:player.pos,side:side,progress:t)
      let tucked = chest-shoulders*0.10-up*0.21+chestFront*0.22
      // Fold the tossing arm around the face, keeping its initial toss and
      // final tuck fixed. A straight chord between them passes through the shoulder.
      let around = (-shoulders*0.18+chestFront*0.22) * (4*fold*(1-fold))
      offHand = tossHand+(tucked-tossHand)*fold+around
    } else if swing.style == .serve, let after = elapsed {
      let tuck = 1 - ramp(Float(after),0.10,0.31)
      offHand += (chest - shoulders * 0.07 - up * 0.19 + forward * 0.17 - offHand) * tuck
    } else if swing.style == .overhead {
      let locate = ramp(time,-0.75,-0.38)*(1-ramp(time,-0.17,0.025))
      let tuck = ramp(time,-0.17,0.025)*(1-ramp(time,0.18,0.45))
      let guide = pose[.leftShoulder]+up*0.47+forward*0.24-shoulders*0.06
      let folded = chest+forward*0.17-up*0.20-shoulders*0.05
      offHand += (guide-offHand)*locate
      offHand += (folded-offHand)*tuck
    }
    if side == 0 && game.flight?.acknowledge == true && game.isResolvingPoint { offHand = local(-0.24, 2.03, 0.12) }
    if receiver.readyHands > 0 {
      let throat = pose[.grip]+shaft*0.20
      offHand += (throat-offHand)*receiver.readyHands
    }
    let freeReach = offHand-pose[.leftShoulder]
    if simd_length_squared(freeReach) > armReach*armReach {
      offHand = pose[.leftShoulder]+unit(freeReach,fallback:forward)*armReach
    }
    if let last = freePalm, delta > 0, !twoHands, service == nil {
      let offset = offHand-pose[.leftShoulder]
      let difference = offset-last
      offHand = pose[.leftShoulder]+last+difference*min(1,5.6*delta/max(0.0001,simd_length(difference)))
    }
    pose[.leftHand] = offHand
    let onHandle = max(0,1-simd_distance(offHand,pose[.grip]+shaft*supportDistance)/0.10)
    pose.supportGrip = service == nil && swing.style != .serve && landingBrace == 0 ? onHandle : 0
    pose.fingerCurl = [0.46+0.42*onHandle+0.06*chaseCarry,0.88+0.10*drive]
    if let service {
      let t = Float(service.tossProgress ?? 0)
      pose.fingerCurl.x = 0.44-0.34*ramp(t,0.12,0.42)+0.21*ramp(t,0.60,0.94)
    }
    pose.fingerCurl.x *= 1-0.84*landingBrace
    var rightPole = unit(right-up*0.5-forward,fallback:right)
    var leftPole = unit(-right-up*0.5-forward,fallback:-right)
    if let measured {
      let blend = motionWeight*0.87
      rightPole += (unit(relative(measured.elbow),fallback:rightPole)-rightPole)*blend
      leftPole += (unit(relative(measured.supportElbow),fallback:leftPole)-leftPole)*blend
    }
    if preparedDrive {
      // The swing plane follows the shoulders. Both elbows have to clear the
      // torso even when a hand crosses the centreline on a two-handed finish.
      let through = ramp(time,-0.18,0.085)
      let strength = ramp(time,-0.74,-0.40)*(1-ramp(time,0.36,0.55))
      let rightBend = unit(shoulders*(0.78-0.27*through) + chestFront*(0.42+0.63*through) - up*0.68,fallback:rightPole)
      let leftBend = unit(-shoulders*(backhand ? 0.66 : 0.39) + chestFront*(backhand ? 0.84 : 0.27) - up*0.91,fallback:leftPole)
      let fold = ramp(time,0.045,0.245)*(1-ramp(time,0.31,0.55))
      // The upper arms travel with the rotating chest. The elbows rise and
      // fold around the shoulders only after the hands have extended forward.
      let rightFinish = unit(shoulders*0.74 + chestFront*0.68 + up*0.20,fallback:rightBend)
      let leftFinish = unit(-shoulders*0.54 + chestFront*0.93 + up*0.17,fallback:leftBend)
      var guide = rightBend+(rightFinish-rightBend)*fold
      if forehand {
        // Carry the upper arm back at shoulder level with a soft elbow.
        // As the leg extends the hand drops, then the elbow comes through.
        let takeback = ramp(time,-0.70,-0.38)*(1-ramp(time,-0.25,-0.11))
        let wrist = pose[.grip]-pose[.rightShoulder]
        let horizontal = wrist-up*wrist.y
        let direction = unit(horizontal,fallback:-forward)
        // The intersection of the two arm segments with a horizontal plane
        // places the elbow at shoulder level without straightening it rigidly.
        let along = min(0.34,simd_length_squared(wrist)/(2*max(0.01,simd_length(horizontal))))
        let outward = unit(simd_cross(up,direction),fallback:right)
        let side = simd_dot(outward,right) >= 0 ? outward : -outward
        let elbow = direction*along + side*sqrt(max(0,0.34*0.34-along*along))
        guide += (unit(elbow-wrist*0.5,fallback:guide)-guide)*takeback
      }
      rightPole += (guide-rightPole)*strength
      leftPole += (leftBend+(leftFinish-leftBend)*(backhand ? fold : 0)-leftPole)*strength
    }
    if volley && !blocked && dive == 0 {
      let inFront = ramp(time,-0.31,-0.16)*(1-ramp(time,0.15,0.32))
      rightPole += (unit(shoulders*0.70+chestFront*0.65-up*0.68,fallback:right)-rightPole)*inFront
    }
    if let runner {
      let weight = running*chaseCarry
      rightPole += (unit(inHeading(runner.elbow),fallback:rightPole)-rightPole)*weight
      leftPole += (unit(inHeading(runner.freeElbow),fallback:leftPole)-leftPole)*weight
    }
    if let reaction, !reduceMotion, side == 0 && reaction.affirmation != nil && game.flight?.acknowledge != true {
      let t = ramp(Float(game.pointResolution?.elapsed ?? 0), 0.12, 0.4)
      pose[.leftHand] += (chest + forward * 0.15 - pose[.leftHand]) * t
    }
    pose[.rightElbow] = elbow(1,shoulder:pose[.rightShoulder],palm:pose[.grip],preferred:rightPole,dt:delta,driving:preparedDrive)
    pose[.leftElbow] = elbow(0,shoulder:pose[.leftShoulder],palm:pose[.leftHand],preferred:leftPole,dt:delta,driving:preparedDrive)
    carryingPalm = pose[.grip]-pose[.rightShoulder]
    carryingAxis = shaft
    freePalm = pose[.leftHand]-pose[.leftShoulder]
    previousStrings = strings
    return pose
  }
}

extension AthletePose {
  var handshakeRacketAxis: CourtPoint3D {
    let across = unit(self[.rightHip]-self[.leftHip],fallback:[1,0,0])
    let forward = simd_cross(CourtPoint3D(0,1,0),across)
    let arm = unit(self[.leftHand]-self[.leftElbow],fallback:[0,-1,0])
    return unit(-across*0.34+forward*0.16+arm*0.20+[0,-0.88,0],fallback:[0,-1,0])
  }

  mutating func walkToHandshake(from center: CourtPoint3D, at location: CourtPoint3D,
                                turn: Float, side: Int, depart: Float,
                                reach: Float, meet: CourtPoint3D) {
    let sign: Float = side == 0 ? 1 : -1
    let yaw = simd_quatf(angle:-sign*turn*(.pi/2),axis:[0,1,0])
    let across = yaw.act([sign,0,0]), forward = yaw.act([0,0,-sign])
    // Turn over the outside foot and let the other step around it. Using the
    // hip as the pivot makes both shoes skate as the pair turn to leave.
    let outside = CourtPoint3D(0.175,0,0.025)
    let offset = (outside-yaw.act(outside))*(1-depart)
    for joint in BodyJoint.allCases { self[joint] = location+offset+yaw.act(self[joint]-center) }
    let movingShoe: BodyJoint = side == 0 ? .leftShoe : .rightShoe
    self[movingShoe].y += 0.09*sin(turn * .pi)
    let stride = simd_dot(self[.leftShoe]-self[.rightShoe],forward)
    let rightPalm = self[.rightHip]+across*0.14+[0,-0.10,0]+forward*(0.12+0.38*stride)
    self[.grip] = rightPalm+(meet-rightPalm)*reach
    self[.leftHand] = self[.leftHip]-across*0.15+[0,-0.09,0]+forward*(0.10-0.28*stride)
    self[.rightElbow] = hinge(self[.rightShoulder],self[.grip],length:0.34,bend:across*0.43-forward)
    self[.leftElbow] = hinge(self[.leftShoulder],self[.leftHand],length:0.34,bend:-across*0.43-forward)
    fingerCurl = [0.92,0.25+0.35*reach]
  }
}
