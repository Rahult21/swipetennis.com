import Foundation
import Combine

/// One on-device slot shared by the court screens. Only the owning account can resume it.
struct SavedPracticeMatch: Codable, Identifiable {
  let owner: String
  let engine: PracticeEngine
  var id: UUID { engine.coach.sessionID }
}

@MainActor final class PracticeMatchSlot: ObservableObject {
  @Published private(set) var saved: SavedPracticeMatch?
  @Published private(set) var loadError: String?
  private let file: URL

  init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SwipeTennis/practice-match.json")) {
    self.file = file
    do {
      let data = try Data(contentsOf: file)
      saved = try JSONDecoder().decode(SavedPracticeMatch.self, from: data)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      // First launch, or the previous match finished.
    } catch {
      loadError = "Your saved match could not be opened. Starting a new match will replace it."
    }
  }

  func match(for owner: String?) -> SavedPracticeMatch? {
    guard let owner, let saved, saved.owner == owner else { return nil }
    return saved
  }

  func save(_ engine: PracticeEngine, owner: String) throws {
    guard engine.phase != .ready, engine.phase != .finished, engine.demo == nil else { return }
    let match = SavedPracticeMatch(owner: owner, engine: engine)
    let data = try JSONEncoder().encode(match)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    saved = match
    loadError = nil
  }

  func discard(_ id: UUID, owner: String) throws {
    guard match(for: owner)?.id == id else { return }
    do { try FileManager.default.removeItem(at: file) }
    catch let error as CocoaError where error.code == .fileNoSuchFile { }
    saved = nil
  }
}
