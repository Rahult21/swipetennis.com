import SwiftUI

private enum WarmupFeed: Int, CaseIterable {
  case serve, forehand, backhand
  var title: String {
    switch self { case .serve: "Place your serve"; case .forehand: "Deep forehand"; case .backhand: "Short backhand" }
  }
  var cue: String {
    switch self {
    case .serve: "Drag on your half to aim blue at the wide target, then swipe toward blue during the toss."
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
    ZStack {
      LiveCourt(scene: session.scene, paused: session.paused)
        .ignoresSafeArea().accessibilityLabel(feed.cue)
      if !session.paused {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 2) {
            Text(feed.title).font(.caption.bold()).accessibilityIdentifier("warmupFeed")
            Text(feed.cue).font(.caption2).fixedSize(horizontal: false, vertical: true)
          }.frame(maxWidth: 230, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(.white).background(.black.opacity(0.43), in: RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8).allowsHitTesting(false)
          Spacer()
          Button { session.pause() } label: { CourtControlIcon(symbol: "pause.fill") }
            .buttonStyle(.plain).accessibilityLabel("Pause warm up")
        }.padding(.horizontal, 7).frame(maxHeight: .infinity, alignment: .top)
      }
      if session.paused || session.snapshot.demo?.result != nil {
        ViewThatFits(in: .vertical) {
          warmupOptions
          ScrollView { warmupOptions }
        }
        .frame(maxWidth: 430).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(12)
      }
    }.statusBarHidden(true)
    .onAppear { session.scene.reduceMotion = reduceMotion; feed.load(into: session) }
    .onDisappear { session.pause() }
    .onChange(of: phase) { _, newPhase in
      if newPhase != .active { session.pause() }
    }
  }
  private var warmupOptions: some View {
    VStack(spacing: 10) {
      Text(session.snapshot.demo?.result?.message ?? feed.title).font(.headline)
      Text(feed.cue).font(.subheadline)
      if session.paused && session.snapshot.demo?.result == nil {
        Button("Resume warm up", systemImage: "play.fill") { session.resume() }
          .buttonStyle(.borderedProminent)
      }
      HStack {
        Button("Try again") { feed.load(into: session) }.buttonStyle(.bordered)
        Button(feed == .backhand ? "Quick match" : "Next shot") {
          if let next = WarmupFeed(rawValue: feed.rawValue + 1) {
            feed = next; next.load(into: session)
          } else { quickMatch() }
        }.buttonStyle(.borderedProminent).accessibilityIdentifier("warmupNext")
      }
      Button("Close warm up") { dismiss() }
    }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
  }
}
