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
    let to = Self.recovery(side, players[1-side].pos)
    return from.distance(to: to) > 0.5
      ? MovementGuide(kind: .recover, from: from, to: to) : nil
  }

  func canFollowShot(_ side: Int) -> Bool {
    guard side != 0 || queuedPower == nil else { return false }
    guard phase == .live, let flight, flight.hitter == side, !flight.serve, flight.fault == nil,
      flight.progress < 0.8, side == 0 || settings.local else { return false }
    // A successful approach split closes this exchange, even just before the bounce.
    return !(splitTimed[side] && splitStarted[side] >= time - flight.elapsed && attacking[side])
  }

  mutating func followShot(_ side: Int) {
    guard canFollowShot(side), let flight else { return }
    if side == 0 { demo?.approached = true }
    if !followingApproach[side] {
      tactics[side].approaches += 1
      if side == 0 && settings.clubEncounter != nil {
        var reads = rivalReads ?? RivalReads()
        reads.observeApproach(flight.landing.x < Self.width/2 ? 0 : 1)
        rivalReads = reads
      }
    }
    approachAvailable[side] = false
    players[side].recoveryFlight = nil
    attacking[side] = true
    followingApproach[side] = true
    if side == 0 {
      for index in coach.approaches.indices { coach.approaches[index].commanded = true }
    }
    players[side].destination = Self.own(
      side, CourtTactics.netCoverage(side: side, opponentContact: flight.contact))
  }

  /// Human receivers hold depth on ordinary balls. A short-ball call opens
  /// only the space between the player's feet and the receiving ring.
  func receivingDepth(_ proposed: Double, side: Int) -> Double {
    guard phase == .live, let flight, flight.hitter != side,
      side == 0 || settings.local else { return proposed }
    let feet = players[side].pos.y
    if players[side].receiveFlight == contactSerial { return proposed }
    let ring = showsGoldenContact(side) ? intercept(side).y : feet
    return side == 0 ? max(proposed, min(feet, ring)) : min(proposed, max(feet, ring))
  }

  private mutating func positionDuringRally(_ side: Int, target: Vec, epoch: Int?, pace: Double?) {
    guard phase == .live, epoch == contactSerial, let flight, flight.fault == nil, flight.power == nil,
          committedRun(side) == nil else { return }
    let receiver = 1 - flight.hitter
    let contact = contactWindow(receiver)?.entry ?? 1
    guard flight.time(at: contact) - flight.elapsed > 0.16 else { return }
    let to = Self.own(side, Vec(x: target.x, y: receivingDepth(target.y, side: side)))
    let forward = (to.y - players[side].pos.y) * (side == 0 ? -1 : 1)
    if canFollowShot(side) && forward >= 0.55 && abs(to.x - players[side].pos.x) <= forward {
      if !followingApproach[side] { followShot(side) }
      players[side].destination = to
    } else {
      move(side, to: to)
    }
    players[side].runPace = clamp(pace ?? 0.8, 0.6, 1.2)
  }

  mutating func apply(_ action: PracticeGestureAction, side: Int, shotEpoch: Int? = nil, movementEpoch: Int? = nil, runPace: Double? = nil, shotDistance: Double? = nil, displayedLanding: Vec? = nil) {
    guard !phase.isPlaying || side != 0 || (queuedPower == nil && flight?.power == nil) else { return }
    if case .shotSwipe = action, shotEpoch != shotGestureEpoch(side) { return }
    switch action {
    case .position(let point): positionDuringRally(side, target: point, epoch: movementEpoch, pace: runPace)
    case .move(let point):
      guard committedRun(side) == nil else { return }
      if let movementEpoch {
        guard movementEpoch == contactSerial, acceptsCourtMovement,
              flight?.fault == nil || outBallChaseTarget(side) != nil else { return }
        players[side].runPace = clamp(runPace ?? 1,0.75,1.5)
        move(side,to:point)
      } else { steer(side,to:point) }
    case .aim(let point): if canChooseShot(side) { players[side].aim = point }
    case .shot(let kind):
      if kind == .drop || kind == .slice { selectTouchShot(kind, side: side, epoch: shotEpoch, distance: shotDistance, displayedLanding: displayedLanding) }
      else if canChooseShot(side) { choose(side, kind) }
    case .courtTap(let point):
      guard movementEpoch == nil || movementEpoch == contactSerial else { return }
      tapCourt(side, at: point)
    case .run(let delta):
      guard committedRun(side) == nil else { return }
      guard movementEpoch == nil || movementEpoch == contactSerial else { return }
      players[side].runPace = clamp(runPace ?? 1, 0.75, 1.5)
      swipeCourt(side, delta: delta)
    case .shotSwipe(let delta): selectShotSwipe(delta, side: side, displayedLanding: displayedLanding)
    case .guidedMove(let kind):
      // Resolve against the live target: the ball may have moved since the swipe began.
      guard movementEpoch == nil || movementEpoch == contactSerial else { return }
      players[side].runPace = clamp(runPace ?? 1, 0.75, 1.5)
      switch kind {
      case .receive: receiveAtGuide(side)
      case .approach: followShot(side)
      case .recover: if recoveryGuide(side) != nil { recover(side) }
      }
    }
  }
}
