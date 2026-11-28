import Foundation

enum PracticeGestureAction: Equatable {
  case move(Vec)
  case aim(Vec)
  case shot(ShotKind)
  case guidedMove(MovementGuideKind)
  case courtTap(Vec)
  case run(Vec)
  case shotSwipe(Vec)
}

enum CourtTouchIntent { case movement, shot, slice }

/// A short swipe toward an uncommanded guide starts a run. A fresh swipe on a
/// player already heading there selects a shot; one touch never does both.
struct PracticeGesture {
  let side: Int
  var intent: CourtTouchIntent = .movement
  var movementEpoch: Int?
  var shotEpoch: Int?
  var allowsDrop = false
  var movementGain = 1.0
  var targetGuide: MovementGuide?
  var movementOrigin: Vec?
  var allowsApproach = false
  private var guidedHeading: Vec?
  private var guideSample: Vec?
  private var lastTarget: Vec?
  private var lastSent: Double?
  private var start: Vec?
  private var travelled = 0.0
  private var screenStart: Vec?
  private(set) var screenTravelled = 0.0
  private var circlePoints: [Vec] = []
  private(set) var previewDelta: Vec?
  private(set) var runPace = 1.0
  private var startedAt: Double?

  mutating func update(at point: Vec, screenPoint: Vec? = nil, ended: Bool = false, timestamp: Double? = nil, playerPosition: Vec? = nil)
    -> PracticeGestureAction?
  {
    if start == nil { start = point }
    guard let start else { return nil }
    travelled = max(travelled, start.distance(to: point))
    let screen = screenPoint ?? point
    if screenStart == nil { screenStart = screen }
    screenTravelled = max(screenTravelled, screenStart!.distance(to: screen))
    if startedAt == nil { startedAt = timestamp }
    if let timestamp, let startedAt, let screenStart, screenPoint != nil, timestamp > startedAt {
      let speed = screenStart.distance(to: screen) / max(1.0 / 120, timestamp - startedAt)
      runPace = clamp(1 + (speed - 340) / 1050, 0.75, 1.5)
    }
    var delta = Vec(x: (point.x - start.x) * movementGain, y: (point.y - start.y) * movementGain)
    let enough = screenPoint == nil ? delta.length >= 0.2 : screen.distance(to:screenStart!) >= 8
    if let heading = guidedHeading, let previous = guideSample {
      let segment = Vec(x:point.x-previous.x,y:point.y-previous.y)
      guard movementOrigin != nil, segment.length >= 0.18 else { return nil }
      guideSample = point
      if segment.x*heading.x + segment.y*heading.y >= 0.55*segment.length { return nil }
      // A deliberate turn takes over from the automatic run on the same touch.
      if let playerPosition {
        movementOrigin = playerPosition
        self.start = previous
        delta = Vec(x: segment.x * movementGain, y: segment.y * movementGain)
      }
      guidedHeading = nil
      targetGuide = nil
      allowsApproach = false
      intent = .movement
    } else if lastTarget == nil, enough, intent != .slice {
      var command: MovementGuideKind?
      if let guide = targetGuide {
        let direction = Vec(x:guide.to.x-guide.from.x,y:guide.to.y-guide.from.y)
        if delta.x*direction.x+delta.y*direction.y >= 0.65*delta.length*direction.length {
          command = guide.kind
        }
      }
      if command == nil && intent == .movement && allowsApproach {
        let forward = delta.y*(side == 0 ? -1 : 1)
        if forward >= 0.55 && abs(delta.x) <= forward*0.75 { command = .approach }
      }
      if let command, delta.length > 0 {
        guidedHeading = Vec(x:delta.x/delta.length,y:delta.y/delta.length)
        guideSample = point
        previewDelta = nil
        return .guidedMove(command)
      }
    }
    if let origin = movementOrigin, intent == .movement, lastTarget != nil || enough {
      // Use an absolute destination anchored at touch-down. Repeated samples
      // or network packets must never add the same displacement twice.
      let target = PracticeEngine.own(side,Vec(x:origin.x+1.5*delta.x,y:origin.y+1.5*delta.y))
      if let lastTarget, target.distance(to:lastTarget) < (ended ? 0.001 : 0.08) { return nil }
      if !ended, let timestamp, let lastSent, timestamp-lastSent < 1.0/30 { return nil }
      lastTarget = target
      lastSent = timestamp
      return .move(target)
    }
    if circlePoints.last.map({ $0.distance(to: screen) >= 2 }) ?? true, circlePoints.count < 160 {
      circlePoints.append(screen)
    }
    if ended, allowsDrop, let timestamp, let startedAt,
      QuickCircle.matches(circlePoints, duration: timestamp - startedAt) { return .shot(.drop) }
    if intent == .slice {
      guard ended else { return nil }
      if travelled < 0.55 { return .courtTap(point) }
      return SlicePath.matches(from: start, to: point, side: side) ? .shot(.slice) : nil
    }
    if intent == .shot {
      let origin = screenStart!
      let facing = side == 0 ? 1.0 : -1.0
      previewDelta = Vec(x:(screen.x-origin.x)*facing,y:(screen.y-origin.y)*facing)
      guard ended else { return nil }
      if screenTravelled < 8 { return .courtTap(point) }
      let direction = side == 0 ? 1.0 : -1.0
      let delta = Vec(x: (screen.x - origin.x) * direction, y: (screen.y - origin.y) * direction)
      return delta.length >= 16 ? .shotSwipe(delta) : nil
    }
    guard ended else { return nil }
    if travelled * movementGain < 0.55 { return .courtTap(point) }
    return delta.length >= 0.55 ? .run(delta) : nil
  }
}

/// A local aiming cue starts on the accepted swipe, even before racket contact.
struct ShotDirection {
  let landing: Vec
  let length: Double
  let isForwardSwipe: Bool
  let lineWidth: Double
  let side, serial: Int
  let start: Double
  private var opponentContact: Double?
  private var strikePosition: Vec?

  init?(action: PracticeGestureAction, side: Int, epoch: Int?, game: PracticeEngine, time: Double, gestureDistance: Double? = nil) {
    guard game.canChooseShot(side), epoch == game.shotGestureEpoch(side) else { return nil }
    let distance: Double
    switch action {
    case .shotSwipe(let delta):
      guard let aim = game.swipeLanding(delta, side: side) else { return nil }
      landing = aim
      distance = delta.length
      isForwardSwipe = delta.y < 0
    case .shot(let kind) where kind == .slice || (kind == .drop && game.canDrawDrop(side)):
      landing = game.touchShotLanding(kind, side: side, distance: gestureDistance)
      distance = gestureDistance ?? 0
      isForwardSwipe = false
    default: return nil
    }
    let strength = ShotSwipe.strength(distance)
    lineWidth = isForwardSwipe ? 3 + 27 * strength : 3
    length = 3 + 6 * strength
    self.side = side
    serial = game.contactSerial
    start = time
  }

  /// Draw the last metres of the flight so the far tip marks the first bounce.
  func startPoint(in game: PracticeEngine) -> Vec {
    let contact: Vec
    if let strikePosition {
      contact = strikePosition
    } else if let flight = game.flight, flight.hitter == side, game.contactSerial > serial {
      contact = flight.launchPosition
    } else if let incoming = game.flight, incoming.hitter != side {
      let progress = game.contactWindow(side)?.entry ?? 1
      contact = incoming.courtPosition(at: max(incoming.progress, progress))
    } else {
      contact = game.players[side].pos
    }
    let distance = contact.distance(to: landing)
    guard distance > length else { return contact }
    return Vec(x: landing.x + (contact.x - landing.x) * length / distance,
               y: landing.y + (contact.y - landing.y) * length / distance)
  }

  mutating func opacity(at time: Double, serial current: Int, hitter: Int?, launchPosition: Vec? = nil) -> Double {
    guard current >= serial else { return 0 }
    if strikePosition == nil, current > serial, hitter == side { strikePosition = launchPosition }
    if opponentContact == nil && (current > serial + 1 || (current > serial && hitter == 1 - side)) {
      opponentContact = time
    }
    let remaining = clamp((start + 1 - time) / 0.28, 0, 1)
    let contactFade = opponentContact.map { clamp(1 - (time - $0) / 0.10, 0, 1) } ?? 1
    return min(remaining, contactFade)
  }
}

struct ShotSwipe: Equatable {
  let kind: ShotKind
  let lateral: Int

  /// A 16-point swipe is the shortest shot. At 148 points it reaches full depth.
  static func strength(_ distance: Double) -> Double {
    clamp((distance - 16) / 132, 0, 1)
  }

  /// Player-relative screen coordinates: toward the net is negative y.
  static func read(_ delta: Vec) -> ShotSwipe? {
    guard delta.length >= 16 else { return nil }
    let forward = -delta.y
    let sideways = abs(delta.x)
    let lateral = delta.x < 0 ? -1 : 1
    if delta.y > 12 && delta.y >= sideways * 0.7 {
      return ShotSwipe(kind: .lob, lateral: sideways > 16 ? lateral : 0)
    }
    if forward > 12 && sideways <= forward * 0.35 {
      return ShotSwipe(kind: .line, lateral: 0)
    }
    if forward > 12 && sideways < forward * 1.6 {
      return ShotSwipe(kind: .cross, lateral: lateral)
    }
    if sideways >= 16 { return ShotSwipe(kind: .angle, lateral: lateral) }
    return nil
  }
}

extension PracticeEngine {
  func canChooseShot(_ side: Int) -> Bool {
    guard side != 0 || queuedPower == nil else { return false }
    guard side == 0 || settings.local else { return false }
    if phase == .serving { return servePreparation?.server != side }
    return phase == .live && flight?.hitter == 1 - side && flight?.fault == nil
  }

  func shotGestureEpoch(_ side: Int) -> Int? {
    guard canChooseShot(side) else { return nil }
    return contactSerial + (phase == .serving ? 1 : 0)
  }

  mutating func selectShotSwipe(_ delta: Vec, side: Int, displayedLanding: Vec? = nil) {
    guard canChooseShot(side) else { return }
    if delta.length < 12 { beginSplit(side); return }
    guard let selection = ShotSwipe.read(delta) else { return }
    choose(side, selection.kind)
    // Distance inside the far baseline, in metres. A short angle stays shorter than a drive.
    guard let landing = displayedLanding ?? swipeLanding(delta, side:side) else { return }
    players[side].aim = landing
    players[side].swipeDepth = side == 0 ? landing.y : Self.length-landing.y
  }

  func swipeLanding(_ delta: Vec, side: Int) -> Vec? {
    guard let selection = ShotSwipe.read(delta) else { return nil }
    let reach = ShotSwipe.strength(delta.length)
    let deep = selection.kind == .angle ? 3.6 : 0.85
    let depth = 8.8 + (deep - 8.8) * reach
    let pos = players[side].pos
    var x = pos.x
    if selection.kind == .lob && selection.lateral == 0 { x = Self.width / 2 }
    if selection.kind == .line {
      let firstServe = phase == .serving ? servePreparation?.number == 1
                                        : flight?.serve == true && flight?.serveNumber == 1
      x = firstServe ? players[1-side].pos.x : intercept(side).x
    }
    if selection.lateral != 0 && selection.kind != .line {
      let lateral = side == 0 ? delta.x : -delta.x
      x = Self.width/2 + (Self.width/2 - 0.45) * clamp(lateral/72,-1,1)
    }
    return Self.aim(side,Vec(x:x,y:side == 0 ? depth : Self.length-depth))
  }

  mutating func tapCourt(_ side: Int, at point: Vec) {
    if dismissAffirmation() { return }
    guard side != 0 || queuedPower == nil else { return }
    guard acceptsCourtMovement else { return }
    if outBallChaseTarget(side) != nil { return }
    guard phase.isPlaying else { return }
    if phase == .serving && servePreparation?.server == side {
      requestServe(side)
      return
    }
    let farDepth = side == 0 ? point.y : Self.length - point.y
    if phase == .live, canChooseShot(side), demo == nil, (0...Self.width).contains(point.x),
       farDepth >= 0 && farDepth < Self.net - 0.5 {
      let target = Self.aim(side, point)
      let across = abs(target.x - players[side].pos.x)
      let kind: ShotKind = across < 1.4 ? .line : (farDepth > 5 && across > 3 ? .angle : .cross)
      choose(side, kind)
      players[side].aim = target
      players[side].tappedLanding = target
      return
    }
    if canTapNetShot(side) {
      choose(side, .line)
      players[side].aim = CourtTactics.openCourt(side: side, opponent: players[1 - side].pos,
        overhead: contactWindow(side)?.overhead == true)
      return
    }
    // A tap never starts or redirects a run, even when it lands on a guide.
    beginSplit(side)
  }

  func canTapNetShot(_ side: Int) -> Bool {
    guard canChooseShot(side), flight?.serve == false, let yellow = contactGuide(side),
      players[side].pos.distance(to: yellow) <= Self.contactRadius,
      players[side].pos.distance(to: players[side].destination) <= Self.contactRadius else { return false }
    return contactWindow(side)?.volley == true
  }

  mutating func receiveAtGuide(_ side: Int) {
    guard let yellow = contactGuide(side) else { return }
    if players[side].pos.distance(to: yellow) > Self.contactRadius
      || players[side].destination.distance(to: yellow) > Self.contactRadius {
      move(side, to: yellow)
    }
    dropGestureEpoch[side] = shotGestureEpoch(side)
  }

  func swipeMovementGuide(_ side: Int, onPlayer: Bool = false) -> MovementGuide? {
    let kind: MovementGuideKind, target: Vec
    if let yellow = contactGuide(side) { kind = .receive; target = yellow }
    else if let white = recoveryGuide(side) { kind = .recover; target = white }
    else { return nil }
    let player = players[side]
    if onPlayer && player.destination.distance(to: target) <= Self.contactRadius { return nil }
    guard player.pos.distance(to: target) > 0.15 else { return nil }
    return MovementGuide(kind: kind, from: player.pos, to: target)
  }

  mutating func swipeCourt(_ side: Int, delta: Vec) {
    // A deliberate forward court swipe keeps the existing approach command.
    // Short swipes captured against white use guidedMove(.recover) directly.
    let forward = delta.y * (side == 0 ? -1 : 1)
    if phase.isPlaying, flight?.hitter == side, flight?.fault == nil,
      forward >= 0.55, abs(delta.x) <= forward * 0.75 {
      followShot(side)
      return
    }
    if let guide = swipeMovementGuide(side), delta.length >= 0.2 {
      let path = Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y)
      let alignment = (delta.x * path.x + delta.y * path.y) / max(0.000001, delta.length * path.length)
      if alignment >= 0.65 {
        if guide.kind == .receive { receiveAtGuide(side) } else { recover(side) }
        return
      }
    }
    // You can still deliberately chase an out ball away from the net.
    if let target = outBallChaseTarget(side), delta.length >= 0.55,
      (target.y - players[side].pos.y) * (side == 0 ? 1 : -1) >= 0,
      delta.x * (target.x - players[side].pos.x) + delta.y * (target.y - players[side].pos.y) >= 0.65 * delta.length * target.distance(to: players[side].pos) {
      move(side, to: target)
      return
    }
    guard phase.isPlaying, flight?.fault == nil, delta.length >= 0.55,
      phase != .serving || servePreparation?.server != side else { return }
    if flight?.hitter == side && forward >= 0.55 && abs(delta.x) <= forward * 0.75 {
      followShot(side)
      return
    }
    let receiveTarget = outBallChaseTarget(side) ?? movementGuide(side).flatMap { $0.kind == .receive ? $0.to : nil }
    if let target = receiveTarget {
      let guide = MovementGuide(kind: .receive, from: players[side].pos, to: target)
      let path = Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y)
      let alignment = (delta.x * path.x + delta.y * path.y) / max(0.001, delta.length * path.length)
      if alignment >= 0.65 { receiveAtGuide(side); return }
    }
    // Off-player swipes can run to an incoming yellow target. Open-court forward
    // movement is reserved for the separate outgoing approach window.
    let receiving = canChooseShot(side) && outBallChaseTarget(side) == nil
    if receiving && forward > 0 && abs(delta.x) <= forward * 0.75 { return }
    let depth = receiving && forward > 0 ? 0 : delta.y
    let scale = min(1.5, 8 / delta.length)
    steer(side, to: Vec(x: players[side].pos.x + delta.x * scale,
      y: players[side].pos.y + depth * scale))
  }

  func recoveryGuide(_ side: Int) -> Vec? {
    guard phase == .live, let flight, flight.hitter == side, flight.fault == nil else { return nil }
    return Self.recovery(side, players[1-side].pos)
  }
}
