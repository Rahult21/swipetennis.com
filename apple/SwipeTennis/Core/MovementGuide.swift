import Foundation

enum MovementGuideKind: Hashable { case receive, approach, recover }

struct MovementGuide: Equatable {
  let kind: MovementGuideKind
  let from: Vec
  let to: Vec
}

/// One demonstration per action, at most three during the lifetime of a practice screen.
struct SwipeCoach {
  private(set) var shown: Set<MovementGuideKind> = []
  private(set) var active: MovementGuide?
  private(set) var elapsed = 0.0
  let duration = 2.4

  mutating func update(guide: MovementGuide?, delta: Double) {
    if let active {
      elapsed += max(0, delta)
      if guide?.kind != active.kind || elapsed >= duration { self.active = nil }
    }
    guard active == nil, let guide, shown.count < 3, !shown.contains(guide.kind) else { return }
    shown.insert(guide.kind)
    active = guide
    elapsed = 0
  }

  mutating func dismiss() { active = nil }
}

extension PracticeEngine {
  func movementGuide(_ side: Int) -> MovementGuide? {
    if let to = serveReceiveTarget(side) {
      let from = players[side].pos
      return from.distance(to: to) > Self.contactRadius
        || players[side].destination.distance(to: to) > Self.contactRadius
        ? MovementGuide(kind: .receive, from: from, to: to) : nil
    }
    guard phase == .live, let flight, flight.fault == nil else { return nil }
    let from = players[side].pos
    if flight.hitter != side {
      let to = intercept(side)
      // A player crossing yellow still needs a movement command if their old route would carry
      // them out again before the ball arrives (especially after a fast opponent volley).
      return from.distance(to: to) > Self.contactRadius
        || players[side].destination.distance(to: to) > Self.contactRadius
        ? MovementGuide(kind: .receive, from: from, to: to) : nil
    }
    if followingApproach[side] { return nil }
    if canFollowShot(side) && flight.returnedShortBall == true && approachAvailable[side] {
      let to = CourtTactics.netCoverage(side: side, opponentContact: flight.contact)
      return from.distance(to: to) > 0.5
        ? MovementGuide(kind: .approach, from: from, to: to) : nil
    }
    let to = Self.recovery(side, flight.contact)
    return from.distance(to: to) > 0.5
      ? MovementGuide(kind: .recover, from: from, to: to) : nil
  }

  func canFollowShot(_ side: Int) -> Bool {
    guard phase == .live, let flight, flight.hitter == side, !flight.serve, flight.fault == nil,
      flight.progress < 0.8, side == 0 || settings.local else { return false }
    // A successful approach split closes this exchange, even just before the bounce.
    return !(splitTimed[side] && splitStarted[side] >= time - flight.elapsed && attacking[side])
  }

  mutating func followShot(_ side: Int) {
    guard canFollowShot(side), let flight else { return }
    if side == 0 { demo?.approached = true }
    if !followingApproach[side] { tactics[side].approaches += 1 }
    approachAvailable[side] = false
    attacking[side] = true
    followingApproach[side] = true
    if side == 0 {
      for index in coach.approaches.indices { coach.approaches[index].commanded = true }
    }
    players[side].destination = Self.own(
      side, CourtTactics.netCoverage(side: side, opponentContact: flight.contact))
  }

  mutating func apply(_ action: PracticeGestureAction, side: Int, shotEpoch: Int? = nil, movementEpoch: Int? = nil) {
    if case .shotSwipe = action, shotEpoch != shotGestureEpoch(side) { return }
    switch action {
    case .move(let point): steer(side, to: point)
    case .aim(let point): if canChooseShot(side) { players[side].aim = point }
    case .shot(let kind):
      if kind == .drop || kind == .slice { selectTouchShot(kind, side: side, epoch: shotEpoch) }
      else if canChooseShot(side) { choose(side, kind) }
    case .courtTap(let point): tapCourt(side, at: point)
    case .run(let delta):
      guard movementEpoch == nil || movementEpoch == contactSerial else { return }
      swipeCourt(side, delta: delta)
    case .shotSwipe(let delta): selectShotSwipe(delta, side: side)
    case .guidedMove(let kind):
      // Resolve against the live target: the ball may have moved since the swipe began.
      guard let guide = movementGuide(side), guide.kind == kind else { return }
      switch kind {
      case .receive: move(side, to: guide.to)
      case .approach: followShot(side)
      case .recover: recover(side)
      }
    }
  }
}
