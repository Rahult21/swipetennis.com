import Foundation

enum ApproachReply: String { case volley, miss, lob, passing }

extension Difficulty {
  var shortBallChance: Double { self == .easy ? 1 / 3 : self == .medium ? 1 / 5 : 1 / 7.5 }
  func approachReply(random: () -> Double) -> ApproachReply {
    let roll = clamp(random(), 0, 0.999999)
    switch self {
    case .easy: return roll < 1 / 3 ? .miss : .volley
    case .medium: return roll < 0.15 ? .miss : roll < 0.5 ? .volley : roll < 0.75 ? .lob : .passing
    case .tough: return roll < 0.05 ? .miss : roll < 0.25 ? .volley : roll < 0.625 ? .lob : .passing
    }
  }
}

extension PracticeEngine {
  static let shortBallDepth = 5.0
  static func isShortBall(_ flight: BallFlight, receiving side: Int) -> Bool {
    guard flight.hitter != side, !flight.serve, flight.fault == nil else { return false }
    let depth = side == 0 ? length - flight.landing.y : flight.landing.y
    return depth >= shortBallDepth - 0.000001 && depth < net
  }
  func showsGoldenContact(_ side: Int) -> Bool {
    phase == .live && flight.map { Self.isShortBall($0, receiving: side) } == true
  }
  var playerIsApproaching: Bool {
    followingApproach[0] || (attacking[0] && players[0].pos.y < Self.net + 5.5)
  }

  mutating func prepareApproachReply(random: () -> Double) -> Bool {
    guard let incoming = flight, incoming.hitter == 0, incoming.fault == nil,
      incoming.kind != .drop, playerIsApproaching else { return false }
    guard incoming.approachReply == nil else { return true }
    let reply = settings.difficulty.approachReply(random: random)
    flight!.approachReply = reply
    flight!.opponentReplyPrepared = true
    flight!.opponentError = nil
    flight!.missedChaseTarget = nil
    if reply == .miss {
      let distance = players[1].pos.distance(to: incoming.contact)
      let errors: [OpponentError] = distance > 2.2 ? [.net, .wide, .long, .unreachable] : [.net, .wide, .long]
      let error = errors[Int(clamp(random(), 0, 0.999999) * Double(errors.count))]
      flight!.opponentError = error
      if error == .unreachable {
        let from = players[1].pos, contact = incoming.contact
        flight!.missedChaseTarget = Self.own(1, Vec(
          x: contact.x + (from.x - contact.x) / distance * 1.9,
          y: contact.y + (from.y - contact.y) / distance * 1.9))
      }
    }
    return true
  }
}
