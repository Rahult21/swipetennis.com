import Foundation

enum TennisVenue: String, Codable, CaseIterable {
  case harbor = "Harbor Glass", mesa = "Copper Terraces", lawn = "Linden Gardens", night = "Midnight Pier"
  var surface: CourtSurface {
    switch self { case .harbor, .night: return .hard; case .mesa: return .clay; case .lawn: return .grass }
  }
  static func standard(_ surface: CourtSurface) -> Self {
    switch surface { case .grass: return .lawn; case .clay: return .mesa; case .hard: return .harbor }
  }
}

enum AthleteModel: String, CaseIterable { case man = "Man", woman = "Woman" }
enum TennisKit: String, CaseIterable { case crew = "Crew neck", polo = "Polo", sleeveless = "Sleeveless" }
enum KitColor: String, CaseIterable { case tide = "Lagoon", ember = "Ember", violet = "Iris", white = "Chalk" }
enum KitProp: String, CaseIterable { case band = "Headband", visor = "Visor", plain = "None" }

extension PracticeSettings {
  var matchVenue: TennisVenue { venue.flatMap { $0.surface == surface ? $0 : nil } ?? .standard(surface) }
}

extension PointReplay {
  var finishingShot: PointReplay {
    guard let hit = strikes.last else { return self }
    // Keep the wind-up, but stop the clip from including an earlier contact.
    let lead = hit.power == .ace ? 1.05 : 0.55
    let afterPrevious = strikes.dropLast().last.map { $0.time + Self.tick } ?? 0
    let first = min(frames.count - 1, max(0, Int(ceil(max(afterPrevious, hit.time - lead) / Self.tick))))
    return suffix(from: first)
  }
}
