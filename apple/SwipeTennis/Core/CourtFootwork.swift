import Foundation
import simd

/// Step out with the travel-side foot, then bring the pushing foot back underneath the hips.
struct CourtFootwork {
  private(set) var left = CourtPoint3D.zero
  private(set) var right = CourtPoint3D.zero
  private(set) var runBlend: Float = 0
  private(set) var runYaw: Float = 0
  private(set) var footPitch = SIMD2<Float>.zero
  private(set) var armStride: Float = 0
  private(set) var gaitPhase: Float = 0
  private var shuffleLeft = CourtPoint3D.zero, shuffleRight = CourtPoint3D.zero
  private var running = false
  private var supportFeet = [CourtPoint3D?](repeating:nil,count:2)
  private var toeOffOffsets = [CourtPoint3D](repeating:.zero,count:2)
  private var previous: CourtPoint3D?
  private var leftSwings = false
  private var stepping = false
  private var replanting = false
  private var lateralDirection: Float = 0
  private var liftOff = CourtPoint3D.zero
  private var touchdown = CourtPoint3D.zero
  private var progress: Float = 0
  private var length: Float = 0.4

  // Anatomical side of the last lateral approach, independent of racket hand.
  private var approachSide: Float = 0
  private(set) var plantedSide: Float = 0
  private var insideStart = CourtPoint3D.zero, insideGoal = CourtPoint3D.zero
  private var firstStep: Float = 0
  private(set) var push: Float = 0

  /// Take ownership of both ground contacts at the end of a receiver's hop.
  /// Subsequent strides pick each shoe up from its actual landing spot.
  mutating func landSplit(leftOffset: CourtPoint3D, rightOffset: CourtPoint3D) {
    left += leftOffset; right += rightOffset
    left.y = 0; right.y = 0
    shuffleLeft = left; shuffleRight = right
    stepping = false; replanting = false
  }

  mutating func advance(centre: CourtPoint3D, velocity: CourtPoint3D, destination: CourtPoint3D,
    facing: Float, strideBias: CourtPoint3D, dt: Float, readiness: Float = 1, surface: CourtSurface = .hard, rightStrideBias: CourtPoint3D = .zero, lateralDriveTime: Float? = nil) {
    let restarted = previous.map { simd_distance(centre,$0) >= 1.8 } ?? true
    left = shuffleLeft
    right = shuffleRight
    if restarted || lateralDriveTime == nil {
      approachSide = 0; plantedSide = 0; firstStep = 0; push = 0
    }
    if let time = lateralDriveTime, time < 0,
       abs(velocity.x) > max(1.25,abs(velocity.z)*1.3) {
      approachSide = velocity.x*facing > 0 ? 1 : -1
    }
    if let time = lateralDriveTime, !restarted,
       strokeStep(time:time,centre:centre,destination:destination,facing:facing,dt:dt) {
      previous = centre
      shuffleLeft = left; shuffleRight = right
      return
    }
    shuffle(centre:centre,velocity:velocity,destination:destination,facing:facing,
            strideBias:strideBias,rightBias:rightStrideBias,dt:dt,readiness:readiness,surface:surface)
    shuffleLeft = left
    shuffleRight = right
    if restarted {
      runBlend = 0; runYaw = 0; footPitch = .zero; armStride = 0; running = false
      supportFeet = [nil,nil]; toeOffOffsets = [.zero,.zero]
      return
    }
    let speed = simd_length(velocity), remaining = simd_distance(destination,centre)
    let lateral = abs(velocity.x) > abs(velocity.z)
    let forward = -velocity.z*facing
    var shufflePitch = SIMD2<Float>.zero
    if stepping && !replanting && speed > 0.2 {
      let strength = min(1,speed/3.4)
      let swing = leftSwings ? 0 : 1
      // Roll off the trailing forefoot as the outside shoe takes the weight.
      // The forward step presents a heel, the shuffle lands nearer the forefoot.
      shufflePitch[1-swing] = strength*(lateral ? 0.21 : 0.32)*progress*progress
      shufflePitch[swing] = strength*((lateral ? 0.21 : 0.32)*(1-progress)
        - (forward > 0.4 && !lateral ? 0.13 : 0.035)*progress)
    }
    let rollEase = 1-exp(-dt*36)
    // A shallow adjustment stays square to the net. On a longer chase the hips
    // turn and the legs alternate under the direction of travel.
    if running {
      running = speed > 2.9 && remaining > 0.48 && (lateral || forward > 0)
    } else if speed > (lateral ? 5.2 : 4.1) && remaining > 1.7 && (lateral || forward > 0) {
      running = true
      if runBlend < 0.02 {
        gaitPhase = simd_dot(right-left,velocity) > 0 ? 0.50 : 0
      }
    }
    runBlend += ((running ? 1 : 0)-runBlend) * (1-exp(-dt*(running ? 11 : 14)))
    if runBlend < 0.002 {
      if runBlend > 0 { supportFeet = [nil,nil]; toeOffOffsets = [.zero,.zero] }
      runBlend = 0; footPitch += (shufflePitch-footPitch)*rollEase; armStride = 0
      return
    }
    let direction = speed > 0.01 ? velocity / speed : CourtPoint3D(0,0,-facing)
    let desiredYaw = -atan2(direction.x*facing,max(0.16,-direction.z*facing))
    runYaw += (desiredYaw-runYaw)*(1-exp(-dt*12))
    let across = CourtPoint3D(cos(runYaw)*facing,0,-sin(runYaw)*facing)
    // Cadence is bounded. Extra distance comes from stride length and a flight
    // phase between toe-off and the opposite foot's next ground contact.
    let stepsPerSecond = min(5.15, 3.10+speed*0.19)
    let period = 2/stepsPerSecond
    gaitPhase = (gaitPhase+dt/period).truncatingRemainder(dividingBy:1)
    let support = max(0.21,0.43-speed*0.015)
    let reach = speed*period*support*0.5
    for index in 0...1 {
      let phase = (gaitPhase+Float(index)*0.5).truncatingRemainder(dividingBy:1)
      let lane = across * (index == 0 ? -0.135 : 0.135)
      let travel, lift, pitch: Float
      if phase < support {
        let contact = phase/support
        travel = reach*(1-2*contact); lift = 0
        pitch = -0.13*(1-contact) + 0.47*contact*contact
      } else {
        let flight = (phase-support)/(1-support)
        // Match ground speed at toe-off and touchdown to avoid a frozen shoe
        // at either end of the swing. The trailing heel recovers under the hip.
        let eased = flight*flight*(3-2*flight)
        travel = reach*(2*eased-1) - speed*period*(1-support)*flight*(1-flight)*(1-2*flight)
        let arc = sin(.pi*flight)
        lift = min(0.38,0.16+0.024*speed)*arc*(1.22-0.44*flight)
        pitch = 0.47*(1-eased)-0.13*eased+0.36*arc
      }
      var shoe = centre+lane+direction*travel+CourtPoint3D(0,lift,0)
      if phase < support {
        // A change of heading or speed moves the hip over a planted shoe.
        // Remember that first court contact until toe-off, including on a cut.
        if supportFeet[index] == nil { supportFeet[index] = shoe }
        let anchor = supportFeet[index] ?? shoe
        toeOffOffsets[index] = anchor-shoe
        shoe = anchor
      } else {
        supportFeet[index] = nil
        let flight = (phase-support)/(1-support)
        shoe += toeOffOffsets[index]*(1-flight*flight*(3-2*flight))
      }
      if index == 0 { left += (shoe-left)*runBlend } else { right += (shoe-right)*runBlend }
      let roll = shufflePitch[index]+(pitch-shufflePitch[index])*runBlend
      footPitch[index] += (roll-footPitch[index])*rollEase
    }
    armStride = cos(2*Float.pi*(gaitPhase-support*0.5))*runBlend
  }

  /// Hold a real landing through the turn. On a recovery command the inside
  /// shoe opens toward the target before the outside shoe leaves the court.
  private mutating func strokeStep(time: Float, centre: CourtPoint3D, destination: CourtPoint3D,
                                    facing: Float, dt: Float) -> Bool {
    let toTarget = destination-centre
    if plantedSide == 0 {
      guard approachSide != 0, time > -0.43, time < -0.035, runBlend < 0.04,
            simd_length(toTarget) < 0.28 else { return false }
      let shoe = approachSide > 0 ? right : left
      guard shoe.y < 0.018, (shoe.x-centre.x)*facing*approachSide > 0.21 else { return false }
      plantedSide = approachSide
      if plantedSide > 0 { right.y = 0 } else { left.y = 0 }
      insideStart = plantedSide > 0 ? left : right
      firstStep = 0; push = 0
      running = false; runBlend = 0; armStride = 0
      supportFeet = [nil,nil]; toeOffOffsets = [.zero,.zero]
      stepping = false; replanting = false
    }
    let outsideRight = plantedSide > 0
    let outside = outsideRight ? right : left
    let inward: Float = -plantedSide*facing
    let returning = time >= 0 && toTarget.x*inward > 0.18 && abs(toTarget.x) > abs(toTarget.z)*0.7
    if time > 0.58 || abs(centre.x-outside.x) > 0.62 ||
       (simd_length(toTarget) > 0.45 && !returning && firstStep == 0) {
      plantedSide = 0; firstStep = 0; push = 0
      return false
    }
    var inside = outsideRight ? left : right
    if returning || firstStep > 0 {
      if firstStep == 0 {
        insideStart = inside
        let distance = simd_length(toTarget)
        insideGoal = centre + CourtPoint3D(0.22*inward,0,0) + toTarget/distance*min(0.44,distance)
      }
      firstStep = min(1,firstStep+dt/0.185)
      let u = firstStep*firstStep*(3-2*firstStep)
      inside = insideStart+(insideGoal-insideStart)*u
      inside.y += 0.092*sin(.pi*firstStep)
      push = sin(.pi*firstStep)
    } else {
      // Finish grounding an airborne inside shoe without moving either sole laterally.
      inside.y = max(0,inside.y-dt*0.75)
    }
    let outsideIndex = outsideRight ? 1 : 0
    let pitch = 0.34*firstStep*firstStep
    footPitch[outsideIndex] += (pitch-footPitch[outsideIndex])*min(1,dt*30)
    footPitch[1-outsideIndex] *= max(0,1-dt*26)
    if outsideRight { left = inside } else { right = inside }
    if firstStep == 1 {
      // Continue the shuffle from these contacts, collecting the trailing shoe.
      leftSwings = !outsideRight
      lateralDirection = -plantedSide
      plantedSide = 0; firstStep = 0; push = 0
    }
    return true
  }

  private mutating func shuffle(centre: CourtPoint3D, velocity: CourtPoint3D, destination: CourtPoint3D,
    facing: Float, strideBias: CourtPoint3D, rightBias: CourtPoint3D, dt: Float, readiness: Float, surface: CourtSurface) {
    let base = CourtPoint3D((0.175 + 0.070 * readiness) * facing, 0, (0.025 + 0.03 * readiness) * facing)
    guard let last = previous, simd_distance(centre, last) < 1.8 else {
      previous = centre; left = centre - base; right = centre + base
      stepping = false; replanting = false; lateralDirection = 0
      return
    }
    previous = centre
    let speed = simd_length(velocity)
    let travel = simd_distance(centre, last)
    let remaining = simd_distance(destination, centre)
    let lateral = abs(velocity.x) > max(0.09, abs(velocity.z) * 1.1)
    let direction: Float = lateral ? (velocity.x * facing > 0 ? 1 : -1) : 0
    if !stepping {
      let moving = speed > 0.12 && remaining > 0.04
      length = lateral ? min(0.57, 0.15 + speed * 0.13) : min(0.78, 0.21 + speed * 0.13)
      if surface == .grass { length *= 0.84 }
      let lead = moving ? velocity / speed * min(remaining, length * 1.15) : .zero
      let goals = (left: centre - base + lead + strideBias, right: centre + base + lead + rightBias)
      let leftGap = simd_distance(left, goals.left), rightGap = simd_distance(right, goals.right)
      guard max(leftGap, rightGap) > (moving ? 0.085 : 0.04 + 0.075 * readiness) else {
        if !moving { lateralDirection = 0 }
        return
      }
      if direction != 0 && direction != lateralDirection { leftSwings = direction < 0 }
      else if !moving { leftSwings = leftGap > rightGap }
      lateralDirection = direction
      liftOff = leftSwings ? left : right
      touchdown = leftSwings ? goals.left : goals.right
      if lateral {
        // A closing foot must leave space under the body. It cannot pass the planted shoe.
        let plantedX = (leftSwings ? right.x : left.x) * facing
        let x = touchdown.x * facing
        touchdown.x = (leftSwings ? min(x, plantedX - 0.245) : max(x, plantedX + 0.245)) * facing
      }
      progress = 0; stepping = true; replanting = false
    }
    let reversing = lateral && lateralDirection != 0 && direction != lateralDirection
    if reversing && !replanting {
      // Brake an airborne shoe where it is. The new lead steps out after it lands.
      liftOff = leftSwings ? left : right
      touchdown = [liftOff.x,0,liftOff.z]
      replanting = true; progress = 0
    }
    progress = min(1, progress + (replanting ? dt / 0.065 : max(travel / length, dt * 4.7)))
    let u = progress * progress * (3 - 2 * progress)
    var shoe = liftOff + (touchdown - liftOff) * u
    if surface == .clay && lateral && speed > 2.6 && remaining < 1.7 && !replanting {
      // The planted outside shoe slides with the body during deceleration.
      let slide = (centre-last)*0.54
      if leftSwings { right += slide } else { left += slide }
    }
    if !replanting { shoe.y = (0.055 + min(speed, 6) * (lateral ? 0.010 : 0.025)) * sin(progress * .pi) }
    if leftSwings { left = shoe } else { right = shoe }
    // On a fast lateral shuffle the trailing toe pushes off before the
    // opening foot lands. Let it clear the surface rather than pulling the
    // pelvis down between shoes that are over a metre apart.
    if lateral && speed > 2.7 && !replanting {
      let dir = velocity/speed
      func releaseToe(_ shoe: CourtPoint3D) -> CourtPoint3D {
        let excess = simd_dot(centre-shoe,dir)-0.52
        guard excess > 0 else { return shoe }
        return shoe+dir*excess+[0,max(0,min(0.09,excess*0.48)-shoe.y),0]
      }
      if leftSwings { right = releaseToe(right) } else { left = releaseToe(left) }
    }
    if progress >= 1 {
      if leftSwings { left = touchdown } else { right = touchdown }
      leftSwings.toggle(); stepping = false
    }
  }
}
