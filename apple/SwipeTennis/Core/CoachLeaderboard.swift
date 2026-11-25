import Foundation

enum CoachMetric: String, CaseIterable, Identifiable, Codable {
  case point, game, set
  var id: String { rawValue }
  var title: String { "Per " + rawValue }
}
struct CoachLeader: Codable, Identifiable {
  let id: String
  let emailMask: String
  let score: Int
}
struct CoachLeaderboard: Codable {
  let metric: CoachMetric
  let isDemo: Bool
  let entries: [CoachLeader]
  static func example(_ metric: CoachMetric) -> Self {
    let names = ["alice", "benny", "carla", "diego", "elena", "finns", "ginaa", "harry", "ivory", "joann"]
    let scores = metric == .point ? [4,4,3,3,3,2,2,2,1,1]
      : metric == .game ? [10,10,9,9,8,8,7,7,6,6] : [31,30,29,28,27,26,25,24,22,21]
    return Self(metric: metric, isDemo: true, entries: names.enumerated().map {
      CoachLeader(id: "example-\($0.offset)", emailMask: $0.element, score: scores[$0.offset])
    })
  }
}
