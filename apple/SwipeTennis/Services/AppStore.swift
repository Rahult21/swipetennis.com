import SwiftUI

struct SavedData: Codable {
  var match: TennisMatch?
  var history: [TennisMatch] = []
  var player: TennisPlayer?
  var practice: PracticeSettings = .init()
}
@MainActor final class AppStore: ObservableObject {
  @Published var data = SavedData()
  @Published var storageError: String?
  private let url: URL
  init() {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
        "SwipeTennis", isDirectory: true)
    url = directory.appendingPathComponent("matches.json")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: url.path) {
        data = try JSONDecoder().decode(SavedData.self, from: Data(contentsOf: url))
      }
    } catch {
      storageError =
        "Could not load saved matches. Your existing file has been kept. \(error.localizedDescription)"
    }
  }
  func save() {
    // Do not overwrite an unreadable archive until the user has recovered it.
    guard storageError == nil else { return }
    do { try JSONEncoder().encode(data).write(to: url, options: .atomic) } catch {
      storageError = "Could not save matches: \(error.localizedDescription)"
    }
  }
  func update(_ match: TennisMatch) {
    data.match = match
    data.history.removeAll { $0.id == match.id }
    if match.winner != nil { data.history.insert(match, at: 0) }
    save()
  }
  func edit(_ action: (inout TennisMatch) -> Void) {
    guard var match = data.match else { return }
    action(&match)
    update(match)
  }
}
