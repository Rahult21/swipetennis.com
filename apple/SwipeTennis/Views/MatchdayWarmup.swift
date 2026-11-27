import SwiftUI

private enum WarmupFeed: Int, CaseIterable {
  case serve, forehand, backhand
  var title: String {
    switch self { case .serve: "Place your serve"; case .forehand: "Deep forehand"; case .backhand: "Short backhand" }
  }
  var cue: String {
    switch self {
    case .serve: "Drag on your half to aim blue at the wide target, then tap to serve."
    case .forehand: "Swipe toward yellow on your right. As you move, swipe long and diagonally left across the net."
    case .backhand: "Swipe toward yellow on your left. As you move, swipe a short diagonal right across the net."
    }
  }
  @MainActor func load(into session: PracticeSession) {
    session.scene.engine.beginShotDemo(self == .serve ? .serveWide : .crosscourt,
      attempt: self == .forehand ? 1 : 0, demonstration: false)
    session.scene.resetRallyPresentation()
    session.snapshot = session.scene.engine
    session.resume()
  }
}

/// Free rehearsal uses academy feeds without recording mastery, scores, or a match checkpoint.
struct MatchdayWarmup: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var phase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var feed: WarmupFeed = .serve
  @StateObject private var session = PracticeSession(engine: PracticeEngine(settings: .init(surface: .hard)))
  let quickMatch: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading) {
          Text("Warm up · \(feed.rawValue + 1) of 3").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          Text(feed.title).font(.headline).accessibilityIdentifier("warmupFeed")
        }
        Spacer()
        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).frame(width:44,height:44) }
          .accessibilityLabel("Close warm up")
      }.padding(.horizontal)
      Text(session.snapshot.demo?.result?.message ?? feed.cue)
        .font(.subheadline).padding(.horizontal).padding(.bottom, 8)
      LiveCourt(scene: session.scene, paused: session.paused)
        .accessibilityLabel(feed.cue)
      HStack {
        Button("Try again", systemImage: "arrow.counterclockwise") { feed.load(into: session) }
        Spacer()
        Button(feed == .backhand ? "Quick match" : "Next shot") {
          if let next = WarmupFeed(rawValue: feed.rawValue + 1) {
            feed = next; next.load(into: session)
          } else { quickMatch() }
        }.buttonStyle(.borderedProminent).accessibilityIdentifier("warmupNext")
      }.padding(.horizontal).padding(.vertical, 6)
    }
    .onAppear { session.scene.reduceMotion = reduceMotion; feed.load(into: session) }
    .onDisappear { session.pause() }
    .onChange(of: phase) { _, newPhase in
      if newPhase == .active { session.resume() } else { session.pause() }
    }
  }
}
