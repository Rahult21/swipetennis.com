import Foundation

enum PracticeScoring: String, Codable, CaseIterable {
  case tennis = "Tennis"
  case tiebreak = "Tiebreak"

  var detail: String {
    self == .tennis
      ? "One set. 0, 15, 30, 40, deuce and advantage. First to six games, win by two. No automatic tiebreak."
      : "One tiebreak. First to seven points, win by two."
  }
}

enum PracticeAward: String, Codable { case point, game, set, tiebreak }

struct PracticeScore: Codable {
  let format: PracticeScoring
  let firstServer: Int
  private(set) var points = [0, 0]
  private(set) var games = [0, 0]
  private(set) var server: Int
  private(set) var winner: Int?
  private(set) var lastAward: PracticeAward = .point

  init(format: PracticeScoring, firstServer: Int = 1) {
    self.format = format
    self.firstServer = firstServer == 0 ? 0 : 1
    server = self.firstServer
  }

  func pointLabel(_ side: Int) -> String {
    if format == .tiebreak { return String(points[side]) }
    if points.min()! >= 3, points[0] != points[1] {
      return points[side] > points[1 - side] ? "AD" : "40"
    }
    return ["0", "15", "30", "40"][min(3, points[side])]
  }

  var deuce: Bool { format == .tennis && points[0] == points[1] && points[0] >= 3 }
  var advantage: Int? {
    guard format == .tennis, points.min()! >= 3, points[0] != points[1] else { return nil }
    return points[0] > points[1] ? 0 : 1
  }
  var serveFromRight: Bool { points.reduce(0, +).isMultiple(of: 2) }

  mutating func award(_ side: Int) {
    guard winner == nil else { return }
    points[side] += 1
    lastAward = .point
    if format == .tiebreak {
      if points[side] >= 7 && points[side] - points[1 - side] >= 2 {
        winner = side
        lastAward = .tiebreak
      } else {
        server = TieBreak.server(first: firstServer, played: points.reduce(0, +))
      }
      return
    }
    guard points[side] >= 4 && points[side] - points[1 - side] >= 2 else { return }
    games[side] += 1
    points = [0, 0]
    lastAward = .game
    if games[side] >= 6 && games[side] - games[1 - side] >= 2 {
      winner = side
      lastAward = .set
    } else {
      server = 1 - server
    }
  }
}

extension PracticeEngine {
  var scoreSummary: String {
    if scoring.format == .tiebreak {
      return "\(name(0)) \(scoring.points[0]) · \(name(1)) \(scoring.points[1]) points"
    }
    return "Games: \(name(0)) \(scoring.games[0]) · \(name(1)) \(scoring.games[1])"
  }

  var scoreSituation: String {
    if let winner = scoring.winner { return "\(name(winner)) won the \(scoring.lastAward.rawValue)." }
    if scoring.deuce { return "Deuce" }
    if let side = scoring.advantage { return "Advantage: \(name(side))" }
    return "\(name(scoring.server)) serving · \(scoring.serveFromRight ? "Deuce" : "Ad") court"
  }

  var scoreAnnouncement: String {
    let points = scoring.format == .tennis && scoring.winner == nil
      ? " Points: \(name(0)) \(scoring.pointLabel(0)), \(name(1)) \(scoring.pointLabel(1))." : ""
    return "\(feedback.title) \(scoreSummary).\(points)"
  }
}
