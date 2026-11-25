import Foundation

struct CourtPoint: Codable, Equatable {
  var x: Double
  var y: Double
}
struct TennisPlayer: Codable, Equatable {
  var name: String
  var utr = ""
}
enum ScoringMode: String, Codable, CaseIterable {
  case swipe = "Swipe"
  case manual = "Manual"
}
enum ShotPosition: String, Codable, CaseIterable {
  case behind = "Behind baseline"
  case baseline = "On baseline"
  case inside = "Inside baseline"
  case net = "At net"
}
struct PointEntry: Codable, Identifiable {
  var id = UUID()
  var winner: Int
  var server: Int
  var serve: Int
  var outcome: String
  var position: ShotPosition
  var mode: ScoringMode
  var date = Date()
  var path: [CourtPoint] = []
  var landings: [CourtPoint] = []
  var callout = ""
  var event = ""
}
struct TieBreak: Codable {
  var isMatch = false
  var points = [0, 0]
  var firstServer: Int
  static func server(first: Int, played: Int) -> Int {
    played == 0 ? first : ((played - 1) / 2) % 2 == 0 ? 1 - first : first
  }
}
struct TennisMatch: Codable, Identifiable {
  var id = UUID()
  var createdAt = Date()
  var players: [TennisPlayer]
  var mode: ScoringMode = .swipe
  var bestOfThree = true
  var gamesPerSet = 6
  // Missing in older saved matches, which used automatic set tiebreaks.
  var useSetTiebreak: Bool? = false
  var firstServer = 0
  var server = 0
  var serveAttempt = 1
  var points = [0, 0]
  var games = [0, 0]
  var sets: [[Int]] = []
  var setWins = [0, 0]
  var tiebreak: TieBreak?
  var winner: Int?
  var log: [PointEntry] = []  // Chronological, retained in full for lossless undo/replay.

  var score: String {
    var chunks = sets.map { "\($0[0])–\($0[1])" }
    if let t = tiebreak, t.isMatch { chunks.append("[\(t.points[0])–\(t.points[1])]") }
    if chunks.isEmpty || (winner == nil && tiebreak?.isMatch != true) {
      chunks.append("\(games[0])–\(games[1])")
    }
    return chunks.joined(separator: "  ")
  }
  func pointLabel(_ player: Int) -> String {
    if let t = tiebreak { return String(t.points[player]) }
    if points.min()! >= 3 {
      return points[0] == points[1] ? "40" : points[player] > points[1 - player] ? "AD" : "–"
    }
    return ["0", "15", "30", "40"][min(3, points[player])]
  }
  var situation: String {
    if let winner { return "\(players[winner].name) won the match" }
    if tiebreak?.isMatch == true { return "10-point match tiebreak · win by two" }
    for p in 0...1 {
      var next = self
      next.advance(p)
      let label =
        next.winner != nil
        ? "MATCH POINT"
        : next.sets.count > sets.count
          ? "SET POINT"
          : next.games[p] > games[p] ? (p == server ? "GAME POINT" : "BREAK POINT") : ""
      if !label.isEmpty { return "\(players[p].name) · \(label)" }
    }
    return points[0] == points[1] && points[0] >= 3
      ? "Deuce"
      : tiebreak != nil
        ? "Set tiebreak · first to 7, win by two"
        : "Set \(sets.count + 1) · \(serveAttempt == 1 ? "First" : "Second") serve"
  }
  mutating func finishSet(_ p: Int, nextServer: Int) {
    sets.append(games)
    setWins[p] += 1
    games = [0, 0]
    points = [0, 0]
    server = nextServer
    tiebreak = nil
    if setWins[p] == 2 {
      winner = p
    } else if !bestOfThree && sets.count == 2 {
      tiebreak = TieBreak(isMatch: true, firstServer: nextServer)
    }
  }
  mutating func advance(_ p: Int) {
    guard winner == nil else { return }
    serveAttempt = 1
    if var t = tiebreak {
      t.points[p] += 1
      tiebreak = t
      if t.points[p] >= (t.isMatch ? 10 : 7) && t.points[p] - t.points[1 - p] >= 2 {
        if t.isMatch {
          winner = p
        } else {
          games[p] += 1
          finishSet(p, nextServer: 1 - t.firstServer)
        }
      } else {
        server = TieBreak.server(first: t.firstServer, played: t.points.reduce(0, +))
      }
      return
    }
    points[p] += 1
    guard points[p] >= 4 && points[p] - points[1 - p] >= 2 else { return }
    points = [0, 0]
    games[p] += 1
    let nextServer = 1 - server
    if games[p] >= gamesPerSet && games[p] - games[1 - p] >= 2 {
      finishSet(p, nextServer: nextServer)
    } else {
      server = nextServer
      if (useSetTiebreak ?? true) && games == [gamesPerSet, gamesPerSet] {
        tiebreak = TieBreak(firstServer: nextServer)
      }
    }
  }
  mutating func record(
    winner p: Int, outcome: String, position: ShotPosition = .baseline, path: [CourtPoint] = [],
    landings: [CourtPoint] = [], serve: Int? = nil
  ) {
    guard winner == nil else { return }
    var entry = PointEntry(
      winner: p, server: server, serve: serve ?? serveAttempt, outcome: outcome, position: position,
      mode: mode, path: path, landings: landings, callout: situation)
    let oldSets = sets.count
    let oldGames = games.reduce(0, +)
    advance(p)
    entry.event =
      winner != nil
      ? "MATCH"
      : sets.count > oldSets
        ? "SET"
        : games.reduce(0, +) > oldGames ? (games.reduce(0, +) % 2 == 1 ? "CHANGEOVER" : "GAME") : ""
    log.append(entry)
  }
  mutating func fault() {
    guard winner == nil else { return }
    if serveAttempt == 1 {
      serveAttempt = 2
    } else {
      record(winner: 1 - server, outcome: "Double fault")
    }
  }
  mutating func undo() {
    if serveAttempt == 2 {
      serveAttempt = 1
      return
    }
    guard !log.isEmpty else { return }
    let entries = Array(log.dropLast())
    points = [0, 0]
    games = [0, 0]
    sets = []
    setWins = [0, 0]
    tiebreak = nil
    winner = nil
    server = firstServer
    serveAttempt = 1
    for entry in entries { advance(entry.winner) }
    log = entries
  }
  func stats(_ p: Int) -> [String: Int] {
    let won = log.filter { $0.winner == p }
    let errors = log.filter { entry in
      let name = entry.outcome.lowercased()
      return (name.contains("error") || name.contains("fault")) && entry.winner != p
    }
    return [
      "Points won": won.count, "Aces": won.filter { $0.outcome == "Ace" }.count,
      "Winners": won.filter { $0.outcome.lowercased().contains("winner") }.count,
      "First serve points won": won.filter { $0.serve == 1 }.count,
      "Second serve points won": won.filter { $0.serve == 2 }.count,
      "Unforced errors": errors.filter { $0.outcome.lowercased().contains("unforced") }.count,
      "Forced errors": errors.filter {
        $0.outcome.lowercased().contains("forced") && !$0.outcome.lowercased().contains("unforced")
      }.count,
      "Double faults": errors.filter { $0.outcome == "Double fault" }.count,
    ]
  }
  var report: String {
    var text =
      "SWIPETENNIS\n\(players[0].name) vs \(players[1].name)\n\(createdAt.formatted(date: .abbreviated, time: .shortened))\nScore: \(score)\n\(situation)\n"
    for p in 0...1 {
      text +=
        "\n\(players[p].name)\(players[p].utr.isEmpty ? "" : " · UTR " + players[p].utr)\n"
        + stats(p).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(
          separator: "\n") + "\n"
    }
    return text
  }
}

enum TraceResult {
  case retry(String)
  case fault(String)
  case point(Int, String)
}
enum TraceRules {
  static func inCourt(_ p: CourtPoint) -> Bool {
    (10.75...89.25).contains(p.x) && (6.75...153.25).contains(p.y)
  }
  static func analyze(match: TennisMatch, path: [CourtPoint], landings: [CourtPoint]) -> TraceResult
  {
    guard let start = path.first, let end = path.last, path.count >= 2, start.y >= 125 else {
      return .retry("Begin at the server’s baseline, then trace across the net.")
    }
    var spots = landings
    if spots.isEmpty { spots = [end] }
    if spots.count == 1 && end.y < 80 && end.y >= 43.75 { spots = [end] }
    let serve = spots[0]
    let right = (match.tiebreak?.points ?? match.points).reduce(0, +) % 2 == 0
    let half = right ? (10.75...51.25) : (48.75...89.25)
    if serve.y >= 80 || serve.y < 43.75 || !half.contains(serve.x) {
      return .fault("Serve outside the diagonal service box")
    }
    if spots.count == 1 { return .point(match.server, "Ace") }
    let index = spots.count - 1
    let final = spots[index]
    let hitter = index % 2 == 0 ? match.server : 1 - match.server
    if inCourt(final) { return .point(hitter, index == 1 ? "Return winner" : "Winner") }
    if index == 1 { return .point(1 - hitter, "Return error") }
    let previous = spots[index - 1]
    let forced =
      previous.x <= 22 || previous.x >= 78 || previous.y <= 18 || previous.y >= 142
      || (index > 1 && abs(previous.x - spots[index - 2].x) >= 42)
    return .point(
      1 - hitter, "\(match.players[hitter].name) \(forced ? "forced" : "unforced") error")
  }
  static func position(path: [CourtPoint], bottom: Bool) -> ShotPosition {
    let visits = path.filter { ($0.y >= 80) == bottom }
    let depth = visits.suffix(12).map { bottom ? $0.y : 160 - $0.y }.max() ?? 145
    return depth >= 152 ? .behind : depth >= 132 ? .baseline : depth >= 96 ? .inside : .net
  }
}
