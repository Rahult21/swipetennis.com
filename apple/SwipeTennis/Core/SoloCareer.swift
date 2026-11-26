import Foundation
import Combine

enum TourRival: String, Codable, CaseIterable, Identifiable {
  case morgan = "Morgan", jules = "Jules", casey = "Casey"
  var id: Self { self }
  var style: BotStyle {
    switch self { case .morgan: return .retriever; case .jules: return .aggressive; case .casey: return .volley }
  }
}

enum ClubEncounter: String, Codable, CaseIterable, Identifiable {
  case debut, returnGame, netRusher, morganRematch, julesRematch, clubFinal
  var id: Self { self }
  var rival: TourRival {
    switch self {
    case .debut, .morganRematch: return .morgan
    case .returnGame, .julesRematch: return .jules
    case .netRusher, .clubFinal: return .casey
    }
  }
  var isTrial: Bool { self == .morganRematch || self == .julesRematch || self == .clubFinal }
  var title: String {
    switch self {
    case .debut: return "Club debut"
    case .returnGame: return "Under pressure"
    case .netRusher: return "At the net"
    case .morganRematch: return "Selection round one"
    case .julesRematch: return "Selection round two"
    case .clubFinal: return "Club final"
    }
  }
  var cue: String {
    switch self {
    case .debut: return "Morgan runs down deep balls. Rally crosscourt and wait for a short one."
    case .returnGame: return "Jules attacks early. Send the first serve back toward the server’s feet."
    case .netRusher: return "Casey closes the net. Look for space down the side or lift a lob over the racket."
    case .morganRematch: return "When Morgan leaves one short, step inside the baseline and follow your approach."
    case .julesRematch: return "On Jules’s second serve, move inside the baseline and take the return early."
    case .clubFinal: return "Watch Casey’s position. Pass into space when it opens. Lob when Casey crowds the net."
    }
  }
  var stakes: String {
    if self == .clubFinal { return "Win to earn the club’s regional entry." }
    if self == .netRusher { return "Finish this match to enter the club selection rounds." }
    return isTrial ? "Win to advance. If you lose, you can play this rival again." : "Finish this match to meet your next opponent."
  }
  var practiceLesson: DemoLesson {
    switch self {
    case .debut: return .crosscourt
    case .morganRematch: return .approachVolley
    case .returnGame: return .firstReturn
    case .julesRematch: return .secondReturn
    case .netRusher, .clubFinal: return .centerLob
    }
  }
  func review(_ game: PracticeEngine) -> String? {
    if rival == .casey {
      let volleys = game.tactics[1].volleys
      return volleys > 0 ? "Casey reached the net for \(volleys == 1 ? "one volley" : "\(volleys) volleys")." : nil
    }
    let rule: CoachRule = rival == .morgan ? .shortBallApproach : self == .returnGame ? .firstServeBody : .secondServeRise
    let chances = game.coach.records.flatMap(\.events).filter { $0.rule == rule }
    guard !chances.isEmpty else { return nil }
    let count = "\(chances.filter(\.success).count) of \(chances.count)"
    switch rule {
    case .shortBallApproach: return "You followed \(count) short balls to the net."
    case .firstServeBody: return "You aimed \(count) first-serve returns back at Jules."
    default: return "You stepped inside for \(count) second-serve returns."
    }
  }
  func makeGame() -> PracticeEngine {
    var settings = PracticeSettings(difficulty: rival == .morgan && !isTrial ? .easy : .medium,
      style: rival.style, surface: .hard, allCourtTraining: false, scoring: .tiebreak, opponentName: rival.rawValue)
    settings.tournament = true
    settings.clubEncounter = self
    return PracticeEngine(settings: settings)
  }
  var openingScore: PracticeScore {
    PracticeScore(format: .tiebreak, firstServer: self == .morganRematch || self == .netRusher ? 0 : 1,
      tiebreakTarget: 10)
  }
}

struct ClubResult: Identifiable, Codable {
  let id: UUID
  let encounter: ClubEncounter
  let won: Bool
  let coachPoints: Int
  let review: String?
  var advanced: Bool { won || !encounter.isTrial }
}

struct SoloCareer: Codable {
  var results: [ClubResult] = []
  var active: PracticeEngine?
  var completedCount: Int { results.filter(\.advanced).count }
  var next: ClubEncounter? { ClubEncounter.allCases.dropFirst(completedCount).first }
  var started: Bool { active != nil || !results.isEmpty }
  func meetings(with rival: TourRival) -> [ClubResult] { results.filter { $0.encounter.rival == rival } }
  mutating func record(_ game: PracticeEngine, encounter: ClubEncounter) {
    if let winner = game.scoring.winner {
      results.append(ClubResult(id: game.coach.sessionID, encounter: encounter, won: winner == 0,
        coachPoints: game.coach.records.reduce(0) { $0 + $1.points }, review: encounter.review(game)))
      active = nil
    } else { active = game }
  }

  mutating func upgradeScoring() -> Bool {
    guard var game = active, let encounter = game.settings.clubEncounter,
          game.scoring.format == .tennis else { return false }
    var score = encounter.openingScore
    // Build 11 seeded games at 30–30, 15–30 or 30–15. Count only rallies actually played.
    for point in game.coach.records { score.award(point.winner) }
    if game.phase.isPlaying || game.phase == .serveFault { score.keepCurrentServe(from: game.scoring) }
    game.settings.scoring = .tiebreak
    game.scoring = score
    record(game, encounter: encounter)
    return true
  }

}

@MainActor final class SoloCareerStore: ObservableObject {
  @Published private var saves: [String: SoloCareer] = [:]
  @Published private(set) var loadError: String?
  private let file: URL
  init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SwipeTennis/solo-careers.json")) {
    self.file = file
    do {
      var loaded = try JSONDecoder().decode([String: SoloCareer].self, from: Data(contentsOf: file))
      var upgraded = false
      for owner in Array(loaded.keys) where loaded[owner]?.upgradeScoring() == true { upgraded = true }
      if upgraded { try write(loaded) } else { saves = loaded }
    }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile { }
    catch { loadError = "Your career save could not be opened. \(error.localizedDescription)" }
  }
  func progress(for owner: String) -> SoloCareer { saves[owner] ?? SoloCareer() }
  private func write(_ updated: [String: SoloCareer]) throws {
    if let loadError { throw NSError(domain: "SoloCareer", code: 1, userInfo: [NSLocalizedDescriptionKey: loadError]) }
    let data = try JSONEncoder().encode(updated)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    saves = updated
  }
  func claimGuest(for owner: String) throws {
    let guest = DemoProgressArchive.guest
    guard owner != guest, saves[owner] == nil, let career = saves[guest] else { return }
    var updated = saves
    updated.removeValue(forKey: guest)
    updated[owner] = career
    try write(updated)
  }
  func enter(owner: String) throws -> SavedPracticeMatch? {
    var career = progress(for: owner)
    if let active = career.active { return SavedPracticeMatch(owner: owner, engine: active) }
    guard let next = career.next else { return nil }
    let game = next.makeGame()
    career.active = game
    var updated = saves
    updated[owner] = career
    try write(updated)
    return SavedPracticeMatch(owner: owner, engine: game)
  }
  func checkpoint(_ game: PracticeEngine, owner: String) throws {
    let sessionID = game.coach.sessionID
    var saveOwner = owner
    if owner == DemoProgressArchive.guest, saves[owner]?.active?.coach.sessionID != sessionID,
       let claimed = saves.first(where: { $0.value.active?.coach.sessionID == sessionID }) {
      // The player signed in while this guest match was on court.
      saveOwner = claimed.key
    }
    guard var career = saves[saveOwner], career.active?.coach.sessionID == sessionID,
      let encounter = game.settings.clubEncounter, career.next == encounter else { return }
    career.record(game, encounter: encounter)
    var updated = saves
    updated[saveOwner] = career
    try write(updated)
  }
}
