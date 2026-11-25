import Foundation

enum CoachCue: Equatable {
  case move(Vec, MovementGuideKind)
  case tapTarget(MovementGuideKind)
  case shot(ShotKind, Double)
  case split(Bool)
  case ready
  case watch
  case aimServe
  case hitServe
}

extension PracticeEngine {
  var coachCue: CoachCue {
    if phase == .serving, let serve = servePreparation {
      if serve.server == 0 {
        if serve.requested || serve.isTossing { return .watch }
        return canBeginServe(0) ? .hitServe : .aimServe
      }
      if splitProgress(0) != nil && players[0].pos.distance(to: players[0].destination) <= Self.contactRadius {
        return .split(splitTimed[0])
      }
      if let due = opponentContactDue(0), due <= 0.4 { return .split(false) }
      if let guide = movementGuide(0), players[0].destination.distance(to: guide.to) > Self.contactRadius {
        return .move(Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y), .receive)
      }
      if players[0].aim != nil { return .ready }
      return serve.number == 1 ? .shot(.line, 0) : .ready
    }
    guard phase == .live, let flight, flight.fault == nil else { return .watch }
    if splitProgress(0) != nil && players[0].pos.distance(to: players[0].destination) <= Self.contactRadius {
      return .split(splitTimed[0])
    }
    if inSplitWindow(0) { return .split(false) }
    if let guide = movementGuide(0) {
      if guide.kind == .recover { return .tapTarget(.recover) }
      // Once the run is queued, teach the shot before contact instead of repeating the run cue.
      if guide.kind != .receive || players[0].destination.distance(to: guide.to) > Self.contactRadius {
        return .move(Vec(x: guide.to.x - guide.from.x, y: guide.to.y - guide.from.y), guide.kind)
      }
    }
    if flight.hitter == 0 { return .watch }
    if players[0].aim != nil {
      return players[0].kind == .drop || players[0].kind == .slice
        ? .shot(players[0].kind, players[0].pos.x < Self.width / 2 ? 1 : -1) : .ready
    }
    if coach.receiving?.serveNumber == 1 { return .shot(.line, 0) }
    if coach.receiving?.serveNumber == 2 { return .ready }
    if coach.receiving?.deepBall == true { return .shot(.lob, 0) }
    if coach.receiving?.wideServe == true {
      return .shot(.cross, players[0].pos.x < Self.width / 2 ? 1 : -1)
    }
    return .shot(settings.allCourtTraining ? .line : players[0].kind,
      players[0].pos.x < Self.width / 2 ? 1 : -1)
  }
}
