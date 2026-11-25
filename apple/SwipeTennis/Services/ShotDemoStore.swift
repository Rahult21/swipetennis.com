import SwiftUI

@MainActor final class ShotDemoStore: ObservableObject {
  @Published private(set) var progress = DemoProgress()
  @Published private(set) var profile = DemoProgressArchive.guest
  @Published private(set) var storageError: String?
  private var archive = DemoProgressArchive()
  private var readable = true
  private let url: URL

  init() {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SwipeTennis", isDirectory: true)
    url = directory.appendingPathComponent("shot-demo-progress.json")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: url.path) {
        archive = try JSONDecoder().decode(DemoProgressArchive.self, from: Data(contentsOf: url))
      }
    } catch {
      readable = false
      storageError = "Saved demo progress could not be read. The existing file has been kept."
    }
    progress = archive.profiles[profile] ?? DemoProgress()
  }
  func activate(userID: String?) {
    profile = DemoProgressArchive.profile(for: userID)
    if profile != DemoProgressArchive.guest, archive.guestClaimedBy == nil,
      archive.profiles[DemoProgressArchive.guest]?.lessons.isEmpty == false {
      archive.claimGuest(for: profile)
      save()
    }
    progress = archive.profiles[profile] ?? DemoProgress()
  }
  func progress(for owner: String) -> DemoProgress { archive.profiles[owner] ?? DemoProgress() }
  func record(_ result: DemoOutcome, lesson: DemoLesson, owner: String) {
    var value = progress(for: owner)
    guard value.record(result, lesson: lesson) else { return }
    archive.profiles[owner] = value
    if owner == profile { progress = value }
    save()
  }
  private func save() {
    guard readable else { return }
    do {
      try JSONEncoder().encode(archive).write(to: url, options: .atomic)
      storageError = nil
    } catch { storageError = "Demo progress could not be saved. Keep the app open and try again." }
  }
}

@MainActor final class ShotDemoSession: ObservableObject {
  let lesson: DemoLesson
  let owner: String
  let scene: TennisScene
  @Published private(set) var snapshot: PracticeEngine
  @Published private(set) var streak: Int
  @Published private(set) var mastered: Bool
  @Published private(set) var paused = false
  private let store: ShotDemoStore
  private var processed: UUID?
  private var retryTask: Task<Void, Never>?
  private var stopped = false

  init(lesson: DemoLesson, store: ShotDemoStore) {
    self.lesson = lesson
    self.store = store
    owner = store.profile
    let saved = store.progress.mastery(lesson)
    streak = saved.completedAttempts
    mastered = saved.isMastered
    scene = TennisScene(settings: .init())
    scene.engine.beginShotDemo(lesson, attempt: saved.attempts, demonstration: saved.attempts == 0)
    snapshot = scene.engine
    scene.publish = { [weak self] engine in self?.receive(engine) }
  }
  private func receive(_ engine: PracticeEngine) {
    snapshot = engine
    guard !stopped, let result = engine.demo?.result, processed != result.id else { return }
    processed = result.id
    store.record(result, lesson: lesson, owner: owner)
    let saved = store.progress(for: owner).mastery(lesson)
    streak = saved.completedAttempts
    mastered = saved.isMastered
    if !result.demonstration && !mastered { scheduleRetry() }
  }
  func begin(demonstration: Bool) {
    guard !stopped, !mastered else { return }
    retryTask?.cancel()
    processed = nil
    paused = false
    scene.suspended = false
    scene.engine.beginShotDemo(lesson, attempt: store.progress(for: owner).mastery(lesson).attempts,
      demonstration: demonstration)
    scene.resetRallyPresentation()
    scene.resetClock()
    snapshot = scene.engine
  }
  private func scheduleRetry() {
    retryTask?.cancel()
    guard !paused, !stopped, !mastered else { return }
    let attempt = snapshot.demo?.id
    retryTask = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 2_200_000_000) } catch { return }
      guard let self, !self.paused, !self.stopped, self.snapshot.demo?.id == attempt else { return }
      self.begin(demonstration: false)
    }
  }
  func pause() {
    paused = true
    scene.suspended = true
    scene.resetClock()
    retryTask?.cancel()
    Immersion.shared.stop()
  }
  func resume() {
    guard !stopped else { return }
    paused = false
    scene.suspended = false
    scene.resetClock()
    if snapshot.demo?.result?.demonstration == false && !mastered { scheduleRetry() }
  }
  func stop() {
    pause()
    stopped = true
    scene.publish = nil
  }
  func input(_ action: (inout PracticeEngine) -> Void) {
    guard !paused, !mastered, snapshot.demo?.demonstration == false else { return }
    action(&scene.engine)
    snapshot = scene.engine
  }
}
