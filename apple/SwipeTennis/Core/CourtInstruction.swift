import Foundation

struct CourtInstruction: Equatable {
  let title: String
  let detail: String
  let symbol: String
}

extension PracticeEngine {
  var instruction: CourtInstruction {
    if phase == .ready {
      return CourtInstruction(
        title: "Build the point. Finish at net.",
        detail: "Make a short swipe toward yellow, then a fresh swipe from your moving player to choose a shot.", symbol: "figure.tennis")
    }
    if isResolvingPoint {
      if let impact = pointResolution?.impact {
        return CourtInstruction(title: impact.isNet ? "Net" : "Out",
          detail: "The red circle marks the impact. Watch the ball finish before the point result.", symbol: "eye")
      }
      return CourtInstruction(title: "Point over", detail: "The point result follows in a moment.", symbol: "eye")
    }
    if phase == .point || phase == .finished {
      return CourtInstruction(
        title: feedback.title,
        detail: feedback.reason, symbol: "flag.checkered")
    }
    if phase == .serving, let serve = servePreparation {
      if serve.requested || serve.isTossing {
        return CourtInstruction(title: "\(name(serve.server)) serving",
          detail: "Watch the toss. Receiver: tap to split step as the racket meets the ball.", symbol: "hand.tap")
      }
      return CourtInstruction(title: humanServing ? "Drag blue. Tap to serve." : "Read the opponent's serve",
        detail: humanServing
          ? "Place blue, then touch a gauge within one second. Speed is on your left and spin on your right. Tap your side to serve."
          : "The blue bounce target is moving into place. Make a short swipe toward yellow to prepare your return.",
        symbol: "scope")
    }
    if settings.local {
      return CourtInstruction(
        title: "Yellow: receive. White: recover.",
        detail: "Swipe from your player to aim; swipe elsewhere on your half to move.", symbol: "person.2.fill")
    }
    guard let flight else {
      return CourtInstruction(
        title: "Read the ball", detail: "Move early to yellow.", symbol: "tennisball")
    }
    if let fault = flight.fault {
      return CourtInstruction(
        title: fault == "net" ? "Into the net" : "Watch the bounce",
        detail: fault == "net"
          ? "Watch the ball reach the net. The red circle will mark the impact."
          : flight.hitter == 1
            ? "The opponent's ball is heading out. Let it land."
            : "Your shot is heading out. Reset for the next point.", symbol: "eye")
    }
    if splitProgress(0) != nil {
      return CourtInstruction(
        title: "Split step. Read the reply.",
        detail: splitTimed[0] ? "Good timing. Move toward the next ball."
          : "Ready for the next ball. Move toward yellow.", symbol: "figure.walk")
    }
    if inSplitWindow(0) {
      return CourtInstruction(
        title: "Tap for a split step",
        detail: "Tap anywhere on court, including white, to split.", symbol: "hand.tap")
    }
    if flight.hitter == 0, movementGuide(0)?.kind == .approach {
      return CourtInstruction(
        title: "Swipe in along the yellow line",
        detail: "Start a new forward swipe now. Finish it before the far bounce.",
        symbol: "hand.point.up.fill")
    }
    if attacking[0] && flight.hitter == 0 && followingApproach[0] {
      return CourtInstruction(
        title: "Follow your shot to the net",
        detail: "Your swipe started the approach. Prepare for the reply.",
        symbol: "arrow.up.forward")
    }
    if attacking[0] && flight.hitter == 0 {
      return CourtInstruction(
        title: "Hold your net position",
        detail: "Read the reply, then swipe toward the next yellow target.", symbol: "eye")
    }
    if attacking[0] && flight.hitter == 1 && flight.loft >= 2 {
      if let target = BallContactWindow.overheadTarget(flight: flight, side: 0),
        flight.progress <= target.progress
      {
        return CourtInstruction(
          title: "Get under the lob",
          detail: "Swipe toward yellow to get under it, then tap in position to smash into open space.", symbol: "arrow.up.to.line"
        )
      }
      return CourtInstruction(
        title: "Let it drop. Keep moving.",
        detail: "Swipe toward the new yellow target for the lower ball.",
        symbol: "arrow.down.forward")
    }
    if attacking[0] && flight.hitter == 1 {
      return CourtInstruction(
        title: "Racket up. Volley forward.",
        detail: "Swipe toward yellow if you need to move, then tap in position to volley into open space.", symbol: "hand.tap")
    }
    if flight.hitter == 0 {
      return CourtInstruction(
        title: "Recover to white",
        detail: "Make a short swipe toward white. Your player runs all the way to the circle.",
        symbol: "arrow.uturn.backward")
    }
    if movementGuide(0)?.kind == .receive {
      return CourtInstruction(
        title: "Move to yellow first",
        detail: settings.allCourtTraining
          ? "Swipe toward yellow. Once running, use a fresh swipe from your player to aim."
          : "Arrive early. Choose your shot before the ball reaches you.", symbol: "figure.run")
    }
    if players[0].aim != nil {
      return CourtInstruction(
        title: players[0].kind == .line ? "Line shot ready" : "Aim set. Meet the ball.",
        detail: settings.allCourtTraining && players[0].kind == .line
          ? "After contact, swipe forward on the court to move in."
          : "Stay inside yellow. Your swing is automatic.", symbol: "checkmark.circle.fill")
    }
    return CourtInstruction(
      title: settings.allCourtTraining
        ? "Swipe up from your player" : "Swipe from your player",
      detail: settings.allCourtTraining
        ? "Start on your player: up selects Line. Start elsewhere to move."
        : "Up: line. Diagonal: crosscourt. Sideways: angle. Down: lob.", symbol: "hand.draw.fill")
  }
}
