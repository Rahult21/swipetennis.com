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
  private var movementCommitted = false
  private var start: Vec?
  private var travelled = 0.0
  private var screenStart: Vec?
  private var screenTravelled = 0.0
  private var circlePoints: [Vec] = []
  private(set) var previewDelta: Vec?
  private(set) var runPace = 1.0
  private var startedAt: Double?

  mutating func update(at point: Vec, screenPoint: Vec? = nil, ended: Bool = false, timestamp: Double? = nil)
    -> PracticeGestureAction?
  {
    guard !movementCommitted else { return nil }
    if start == nil { start = point }
    guard let start else { return nil }
    travelled = max(travelled, start.distance(to: point))
    let screen = screenPoint ?? point
    if screenStart == nil { screenStart = screen }
    if startedAt == nil { startedAt = timestamp }
    if let timestamp, let startedAt, let screenStart, screenPoint != nil, timestamp > startedAt {
      let speed = screenStart.distance(to: screen) / max(1.0 / 120, timestamp - startedAt)
      runPace = clamp(1 + (speed - 340) / 1050, 0.75, 1.5)
    }
    if intent != .slice, let guide = targetGuide {
      let delta = Vec(x: point.x - start.x, y: point.y - start.y)
      let path = Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y)
      let enough = screenPoint == nil ? delta.length >= 0.2 : screen.distance(to: screenStart!) >= 8
      let alignment = (delta.x * path.x + delta.y * path.y) / max(0.000001, delta.length * path.length)
      if enough && alignment >= 0.65 {
        previewDelta = nil
        movementCommitted = true
        return .guidedMove(guide.kind)
      }
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
      screenTravelled = max(screenTravelled, origin.distance(to: screen))
      guard ended else { return nil }
      if screenTravelled < 8 { return .courtTap(point) }
      let direction = side == 0 ? 1.0 : -1.0
      let delta = Vec(x: (screen.x - origin.x) * direction, y: (screen.y - origin.y) * direction)
      return delta.length >= 16 ? .shotSwipe(delta) : nil
    }
    guard ended else { return nil }
    if travelled * movementGain < 0.55 { return .courtTap(point) }
    let delta = Vec(x: (point.x - start.x) * movementGain, y: (point.y - start.y) * movementGain)
    return delta.length >= 0.55 ? .run(delta) : nil
  }
}

struct ShotSwipe: Equatable {
  let kind: ShotKind
  let lateral: Int

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

  mutating func selectShotSwipe(_ delta: Vec, side: Int) {
    guard canChooseShot(side) else { return }
    if delta.length < 12 { beginSplit(side); return }
    guard let selection = ShotSwipe.read(delta) else { return }
    choose(side, selection.kind)
    // Distance inside the far baseline, in metres. A short angle stays shorter than a drive.
    guard let landing = swipeLanding(delta, side:side) else { return }
    players[side].aim = landing
    players[side].swipeDepth = side == 0 ? landing.y : Self.length-landing.y
  }

  func swipeLanding(_ delta: Vec, side: Int) -> Vec? {
    guard let selection = ShotSwipe.read(delta) else { return nil }
    let reach = clamp((delta.length - 16) / 132, 0, 1)
    let deep = selection.kind == .angle ? 3.6 : 0.85
    let depth = 8.8 + (deep - 8.8) * reach
    let pos = players[side].pos
    var x = pos.x
    if selection.kind == .lob && selection.lateral == 0 { x = Self.width / 2 }
    if selection.kind == .line && flight?.serve == true && flight?.serveNumber == 1 { x = players[1-side].pos.x }
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
