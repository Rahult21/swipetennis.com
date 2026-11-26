import Foundation

struct STRating: Codable, Equatable {
  static let tentativeMatchCount = 3
  var points: Double = 4
  var humanMatches: Int = 0
  var wins: Int = 0
  // Derive this from the count so cached profiles also adopt the three-match rule.
  var tentative: Bool { humanMatches < Self.tentativeMatchCount }
  var label: String { Self.label(points, tentative: tentative) }
  static func label(_ points: Double, tentative: Bool) -> String {
    let number = points.formatted(.number.precision(.fractionLength(0...2)))
    return "ST \(number)\(tentative ? "t" : "")"
  }
}
struct STRatingChange: Codable {
  let userID: String
  let before: Double
  let after: Double
  let humanMatches: Int
  let tentative: Bool
  var beforeTentative: Bool?
  var summary: String {
    // Old receipts used five matches; new receipts include their historical state.
    "\(STRating.label(before, tentative: beforeTentative ?? (humanMatches <= 5))) → \(STRating.label(after, tentative: tentative))"
  }
}

enum CupLevel: String, Codable, CaseIterable, Identifiable {
  case easy, medium, hard
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var difficulty: Difficulty { self == .easy ? .easy : self == .medium ? .medium : .tough }
  init(_ difficulty: Difficulty) { self = difficulty == .easy ? .easy : difficulty == .medium ? .medium : .hard }
}
struct CupPlayer: Codable, Identifiable {
  let id: String
  let name: String
  let kind: String
  let ready: Bool
  var level: CupLevel?
  var botST: Double?
  var style: String?
  var stRating: STRating?
  var isBot: Bool { kind == "bot" }
  var botStyle: BotStyle {
    switch style {
    case "aggressive": return .aggressive
    case "volley": return .volley
    case "allcourt": return .allcourt
    case "retriever": return .retriever
    default: return .baseline
    }
  }
}
struct CupMatch: Codable, Identifiable {
  let id: String
  let playerIDs: [String]
  let authorityID: String?
  let status: String
  let score: [Int]
  let winnerID: String?
  let reason: String?
  var rematchRequestedBy: String?
  var ratingChanges: [STRatingChange]?
  var title: String { id == "final" ? "Final" : id.hasPrefix("quarter-") ? "Quarterfinal " + id.suffix(1) : "Semifinal " + id.suffix(1) }
  var complete: Bool { status == "complete" }
}
struct QuickCup: Codable, Identifiable {
  let code: String
  let title: String
  var size: Int?
  var division: String?
  var adaptive: Bool?
  var eventWeek: Double?
  var capacity: Int { size ?? 4 }
  let hostID: String
  let status: String
  let level: CupLevel
  let surface: String
  let createdAt: Double
  let expiresAt: Double
  let participants: [CupPlayer]
  let matches: [CupMatch]
  let championID: String?
  let version: Int
  var id: String { code }
  var inviteURL: URL { URL(string: "https://swipetennis.com/cup/\(code)")! }
  var isLobby: Bool { status == "lobby" }
  var isClosed: Bool { ["complete", "cancelled", "expired"].contains(status) }
  var surfaceValue: CourtSurface { surface == "grass" ? .grass : surface == "clay" ? .clay : .hard }
  func player(_ id: String?) -> CupPlayer? { participants.first { $0.id == id } }
  func nextMatch(for userID: String) -> CupMatch? {
    guard status == "playing" else { return nil }
    return matches.first { !$0.complete && $0.playerIDs.contains(userID) }
  }
  func engine(for match: CupMatch) -> PracticeEngine {
    let near = player(match.playerIDs.first), far = player(match.playerIDs.last)
    var settings = PracticeSettings(local: far?.isBot == false, difficulty: (far?.level ?? level).difficulty,
      style: far?.botStyle ?? .baseline, surface: surfaceValue, allCourtTraining: false,
      scoring: .tiebreak, playerName: near?.name ?? "Player", opponentName: far?.name ?? "Opponent")
    settings.botST = far?.botST
    settings.tournament = true
    return PracticeEngine(settings: settings)
  }
  static func inviteCode(from text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate: String
    if let url = URL(string: text), url.scheme != nil {
      if url.scheme == "swipetennis", url.host == "cup" { candidate = url.lastPathComponent }
      else if url.scheme == "https", url.host == "swipetennis.com", url.pathComponents.count == 3,
        url.pathComponents[1] == "cup" { candidate = url.lastPathComponent }
      else { return nil }
    } else { candidate = text }
    let normalized = candidate.uppercased()
    return normalized.range(of: "^[A-HJ-NP-Z2-9]{8}$", options: .regularExpression) == nil ? nil : normalized
  }
}

// A small typed command preserves the same gesture epochs used by local play.
// The room assigns the side; clients can never choose their opponent's side.
struct CupInput: Codable {
  var kind: String
  var point: Vec?
  var shot: ShotKind?
  var shotEpoch: Int?
  var movementEpoch: Int?
  var runPace: Double?
  var speed: ServeLevel?
  var spin: ServeLevel?
  var finished: Bool?
  init(kind: String, point: Vec? = nil, shot: ShotKind? = nil, shotEpoch: Int? = nil,
    movementEpoch: Int? = nil, speed: ServeLevel? = nil, spin: ServeLevel? = nil, finished: Bool? = nil) {
    self.kind = kind; self.point = point; self.shot = shot; self.shotEpoch = shotEpoch
    self.movementEpoch = movementEpoch; self.speed = speed; self.spin = spin; self.finished = finished
  }
  init(_ action: PracticeGestureAction, shotEpoch: Int?, movementEpoch: Int?, runPace: Double? = nil) {
    self.init(kind: "", shotEpoch: shotEpoch, movementEpoch: movementEpoch)
    self.runPace = runPace
    switch action {
    case .move(let p): kind = "move"; point = p
    case .aim(let p): kind = "aim"; point = p
    case .shot(let s): kind = "shot"; shot = s
    case .guidedMove(let guide): kind = guide == .receive ? "receive" : guide == .recover ? "recover" : "approach"
    case .courtTap(let p): kind = "tap"; point = p
    case .run(let p): kind = "run"; point = p
    case .shotSwipe(let p): kind = "swipe"; point = p
    }
  }
  func apply(to engine: inout PracticeEngine, side: Int) {
    guard side == 0 || (side == 1 && engine.settings.local) else { return }
    if let point, !point.x.isFinite || !point.y.isFinite || abs(point.x) > 10000 || abs(point.y) > 10000 { return }
    var action: PracticeGestureAction?
    switch kind {
    case "move": if let point { action = .move(point) }
    case "aim": if let point { action = .aim(point) }
    case "shot": if let shot { action = .shot(shot) }
    case "tap": if let point { action = .courtTap(point) }
    case "run": if let point { action = .run(point) }
    case "swipe": if let point { action = .shotSwipe(point) }
    case "receive": action = .guidedMove(.receive)
    case "recover": action = .guidedMove(.recover)
    case "approach": action = .guidedMove(.approach)
    case "split": engine.beginSplit(side)
    case "serve": engine.requestServe(side)
    case "serveAim": if let point { engine.aimServe(at: point, side: side, finished: finished ?? true) }
    case "serveTune": engine.adjustServe(speed: speed, spin: spin, side: side)
    default: break
    }
    if let action { engine.apply(action, side: side, shotEpoch: shotEpoch, movementEpoch: movementEpoch, runPace: runPace) }
  }
}

enum CupPerspective {
  static func court(_ point: Vec, side: Int) -> Vec {
    side == 0 ? point : Vec(x: PracticeEngine.width - point.x, y: PracticeEngine.length - point.y)
  }
  static func screen(_ point: Vec, side: Int) -> Vec {
    side == 0 ? point : Vec(x: -point.x, y: -point.y)
  }
}
