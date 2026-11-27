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

/// Elapsed presentation time is independent of the simulation clock. The
/// contact window runs in half time. Longer flights use the remaining screen
/// time to reach their first bounce without cutting across a racket contact.
struct PointBroadcast {
  static let reactionDuration = 2.0
  static let shotDuration = 3.0
  static let duration = reactionDuration + shotDuration
  let start, contactEnd, end: Double
  init(_ shot: PointReplay) {
    let contact = shot.strikes.last?.time ?? 0
    start = max(0,contact-0.49)
    let landing = shot.lastShotBounceTime.map { $0+0.13 } ?? 0
    end = min(shot.duration,max(start+Self.shotDuration*PointReplay.speed,landing))
    contactEnd = min(end,contact+0.19)
  }
  func sourceTime(at elapsed: Double) -> Double {
    let u = clamp((elapsed-Self.reactionDuration)/Self.shotDuration,0,1)
    let length = max(0,end-start)
    // Linear half-speed through the swing. When a long lob needs more time,
    // accelerate smoothly only in its flight; a short net fault slows to fit.
    let base = min(length,Self.shotDuration*PointReplay.speed)
    let extra = length-base
    let onset = min(0.80,(contactEnd-start)/max(base,PointReplay.tick))
    let after = max(0,(u-onset)/(1-onset))
    return start+base*u+extra*after*after*(3-2*after)
  }
}
