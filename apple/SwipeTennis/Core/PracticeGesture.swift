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

/// Intent is fixed at touch-down: on the receiving player selects a shot; elsewhere moves.
struct PracticeGesture {
  let side: Int
  var intent: CourtTouchIntent = .movement
  var movementEpoch: Int?
  var shotEpoch: Int?
  var allowsDrop = false
  var movementGain = 1.0
  private var start: Vec?
  private var travelled = 0.0
  private var screenStart: Vec?
  private var screenTravelled = 0.0
  private var circlePoints: [Vec] = []
  private var startedAt: Double?

  mutating func update(at point: Vec, screenPoint: Vec? = nil, ended: Bool = false, timestamp: Double? = nil)
    -> PracticeGestureAction?
  {
    if start == nil { start = point }
    guard let start else { return nil }
    travelled = max(travelled, start.distance(to: point))
    let screen = screenPoint ?? point
    if screenStart == nil { screenStart = screen }
    if startedAt == nil { startedAt = timestamp }
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
    if selection.kind == .lob && selection.lateral == 0 {
      players[side].aim?.x = Self.width / 2
    }
    if selection.kind == .line && flight?.serve == true && flight?.serveNumber == 1 {
      players[side].aim = Self.aim(side, players[1 - side].pos)
    }
    if selection.lateral != 0 && selection.kind != .line {
      let right = selection.lateral * (side == 0 ? 1 : -1) > 0
      let margin = selection.kind == .angle ? 0.55 : 1.4
      players[side].aim!.x = right ? Self.width - margin : margin
    }
  }

  mutating func tapCourt(_ side: Int, at point: Vec) {
    if dismissAffirmation() { return }
    guard acceptsCourtMovement else { return }
    if let target = outBallChaseTarget(side) {
      if point.distance(to: target) <= 1.15 || point.distance(to: ball) <= 1.15 { move(side, to: target) }
      return
    }
    guard phase.isPlaying else { return }
    if phase == .serving && servePreparation?.server == side {
      requestServe(side)
      return
    }
    if let yellow = contactGuide(side), point.distance(to: yellow) <= 1.15 {
      move(side, to: yellow)
      dropGestureEpoch[side] = shotGestureEpoch(side)
    } else if let white = recoveryGuide(side), point.distance(to: white) <= 1.15 {
      recover(side)
    }
    // Target taps keep their movement command and also prepare for the next ball.
    beginSplit(side)
  }

  mutating func swipeCourt(_ side: Int, delta: Vec) {
    // You can still deliberately chase an out ball away from the net.
    if let target = outBallChaseTarget(side), delta.length >= 0.55,
      (target.y - players[side].pos.y) * (side == 0 ? 1 : -1) >= 0,
      delta.x * (target.x - players[side].pos.x) + delta.y * (target.y - players[side].pos.y) >= 0.65 * delta.length * target.distance(to: players[side].pos) {
      move(side, to: target)
      return
    }
    guard phase.isPlaying, flight?.fault == nil, delta.length >= 0.55,
      phase != .serving || servePreparation?.server != side else { return }
    let forward = delta.y * (side == 0 ? -1 : 1)
    if flight?.hitter == side && forward >= 0.55 && abs(delta.x) <= forward * 0.75 {
      followShot(side)
      return
    }
    let receiveTarget = outBallChaseTarget(side) ?? movementGuide(side).flatMap { $0.kind == .receive ? $0.to : nil }
    if let target = receiveTarget {
      let guide = MovementGuide(kind: .receive, from: players[side].pos, to: target)
      let path = Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y)
      let alignment = (delta.x * path.x + delta.y * path.y) / max(0.001, delta.length * path.length)
      if alignment >= 0.65 { move(side, to: guide.to); return }
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
    return Self.recovery(side, flight.contact)
  }
}
