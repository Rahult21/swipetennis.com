import SwiftUI

private enum MatchdayRoute: Identifiable {
  case film, warmup, court(SavedPracticeMatch)
  var id: String {
    switch self {
    case .film: "film"
    case .warmup: "warmup"
    case .court(let match): match.id.uuidString
    }
  }
}

struct HomeView: View {
  @EnvironmentObject private var store: AppStore
  @EnvironmentObject private var account: CoachAccountStore
  @EnvironmentObject private var slot: PracticeMatchSlot
  @EnvironmentObject private var cups: CupStore
  @Environment(\.scenePhase) private var phase
  @Environment(\.verticalSizeClass) private var heightClass
  @Environment(\.dynamicTypeSize) private var textSize
  @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 48.0
  @State private var music = false
  @AppStorage("sound") private var sound = true
  @AppStorage("courtVolume") private var volume = 0.3
  @State private var visible = false
  @State private var playingDaily = false
  @State private var route: MatchdayRoute?
  @State private var startAfterWarmup = false
  private var owner: String { account.identity?.userID ?? DemoProgressArchive.guest }
  private var saved: SavedPracticeMatch? { slot.match(for: owner) }
  private let lime = Color(red: 0.84, green: 0.98, blue: 0.33)
  private let mint = Color(red: 0.61, green: 0.91, blue: 0.77)
  private let felt = Color(red: 0.035, green: 0.11, blue: 0.085)
  private var gain: Float {
    visible && phase == .active && route == nil && !startAfterWarmup && !playingDaily && cups.pendingInvite == nil && music && sound
      ? Float(min(volume, 0.1)) : 0
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 4) {
          Image(systemName: "tennisball.fill").foregroundStyle(lime)
          Text("SwipeTennis").font(.title3.bold().italic())
          Spacer()
          Button { music.toggle() } label: {
            icon(music && sound ? "speaker.wave.2" : "speaker.slash")
          }.accessibilityLabel("Lobby beat").accessibilityValue(music && sound ? "On" : "Off")
            .accessibilityIdentifier("lobbyBeat")

          NavigationLink { CoachLeaderboardView() } label: { icon("trophy") }.accessibilityLabel("Coachability leaderboard")
          NavigationLink { CoachAccountScreen() } label: { icon("person.crop.circle") }.accessibilityLabel("Apple account")
        }
        let lead = heightClass == .compact && !textSize.isAccessibilitySize
          ? AnyLayout(HStackLayout(alignment: .center, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
        lead {
          hero
          VStack(alignment: .leading, spacing: 10) {
            heading("Take the court")
            let cards = textSize.isAccessibilitySize ? AnyLayout(VStackLayout()) : AnyLayout(HStackLayout(spacing: 10))
            cards {
              Button { route = .warmup } label: {
                actionCard("Warm up", "Serve & groundstrokes", "tennis.racket", lime)
              }.accessibilityIdentifier("matchdayWarmup")
              Button { quickMatch() } label: {
                actionCard("Quick match", "Seven-point tiebreak", nil, mint)
              }.accessibilityIdentifier("matchdayQuickMatch")
            }
            NavigationLink { LockerRoom() } label: {
              row("Player & outfits", "tshirt")
            }.accessibilityIdentifier("playerOutfits")
            NavigationLink { PracticeSetupView() } label: {
              row("Play & practice setup", "slider.horizontal.3")
            }.accessibilityIdentifier("playPractice")
          }
        }
        heading("Competition")
        HStack(alignment: .top, spacing: 10) {
          SoloCareerLink()
          NavigationLink { CupHubView() } label: {
            MatchdayCompetitionCard(title: "Quick Cup", subtitle: "Play with friends", symbol: "trophy.fill")
          }.accessibilityIdentifier("quickCup")
        }
        VStack(alignment: .leading, spacing: 8) {
          DailyPressureSection { playingDaily = $0 }
        }.panel()
        heading("Learn & improve")
        VStack(alignment: .leading, spacing: 14) {
          ShotDemoLink()
          Divider()
          CourtGuideCard()
          Divider()
          CoachRulesCard()
        }.panel()
        heading("Your progress")
        VStack(alignment: .leading, spacing: 14) {
          CoachLeaderboardCard()
          Divider()
          NavigationLink { HistoryView() } label: { Label("Journal", systemImage: "book.closed") }
          Divider()
          NavigationLink { MatchHub() } label: { Label("Score a match", systemImage: "list.number") }
        }.panel()
      }.padding(.horizontal, 16).padding(.bottom, 22)
        .frame(maxWidth: 850).frame(maxWidth: .infinity)
    }
    .background(felt.ignoresSafeArea()).foregroundStyle(.white).tint(mint)
    .environment(\.colorScheme, .dark).buttonStyle(.plain)
    .toolbar(.hidden, for: .navigationBar)
    .toolbarBackground(felt, for: .tabBar).toolbarBackground(.visible, for: .tabBar)
    .toolbarColorScheme(.dark, for: .tabBar)
    .onAppear { visible = true }
    .onDisappear { visible = false; Immersion.shared.setLobbyGain(0) }
    .onChange(of: gain, initial: true) { _, gain in Immersion.shared.setLobbyGain(gain) }
    .fullScreenCover(item: $route, onDismiss: {
      if startAfterWarmup { startAfterWarmup = false; quickMatch() }
    }) { item in
      switch item {
      case .film: QuickStartFilm()
      case .warmup: MatchdayWarmup { startAfterWarmup = true; route = nil }
      case .court(let match): PracticeGameView(match: match, startImmediately: true)
      }
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(saved == nil ? "Quick start film" : "Saved match").textCase(.uppercase)
        Spacer()
        Text(saved?.engine.scoreSummary ?? "0:20").monospacedDigit()
      }.font(.caption.bold()).shadow(radius: 2)
      Spacer(minLength: 36)
      Text(saved == nil ? "First serve." : "Back in play.")
        .font(.system(size: titleSize, weight: .bold, design: .serif).italic()).tracking(-1.7)
        .foregroundStyle(Color(red: 1, green: 0.98, blue: 0.88))
      HStack {
        Button {
          if let saved { route = .court(saved) } else { route = .film }
        } label: {
          HStack {
            Text(saved == nil ? "Watch quick start" : "Resume match")
            Image(systemName: "play.fill").font(.caption2)
          }.font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 44)
            .background(lime, in: Capsule()).foregroundStyle(felt)
        }.accessibilityIdentifier(saved == nil ? "matchdayFilm" : "matchdayResume")
        if saved != nil {
          Button { route = .film } label: {
            Label("Quick start", systemImage: "film").font(.caption.bold())
              .padding(.horizontal, 12).frame(minHeight: 44).background(.black.opacity(0.55), in: Capsule())
          }.accessibilityIdentifier("matchdayFilm")
        }
      }
    }.padding(16).frame(maxWidth: .infinity, minHeight: 214, alignment: .leading)
      .background {
        GeometryReader { geo in
          ZStack(alignment: .trailing) {
            felt
            Image(saved == nil ? "MatchdayServe" : "MatchdayReturn").resizable().scaledToFill()
              .frame(width: geo.size.width * 0.73, height: geo.size.height, alignment: .center).clipped()
            LinearGradient(stops: [.init(color: felt, location: 0.24), .init(color: felt.opacity(0.42), location: 0.5),
                                    .init(color: .clear, location: 0.77)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [felt.opacity(0.82), .clear], startPoint: .bottom, endPoint: .center)
          }
        }
      }.clipShape(RoundedRectangle(cornerRadius: 18))
  }

  private func quickMatch() {
    route = .court(.quickPlay(owner: owner, name: ApplePlayerName.display(account.identity?.emailMask),
                             preferences: store.data.practice))
  }
  private func heading(_ text: String) -> some View {
    Text(text).font(.title3.bold()).accessibilityAddTraits(.isHeader)
  }
  private func icon(_ name: String) -> some View {
    Image(systemName: name).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
  }
  private func actionCard(_ title: String, _ detail: String, _ symbol: String?, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        if let symbol { Image(systemName: symbol).font(.title) }
        else {
          Canvas { context, size in
            let court = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let singles = court.insetBy(dx: 0, dy: court.height / 8)
            let service = singles.insetBy(dx: singles.width * 0.23, dy: 0)
            var lines = Path(court)
            lines.addRect(singles); lines.addRect(service)
            lines.move(to: CGPoint(x: court.midX, y: court.minY))
            lines.addLine(to: CGPoint(x: court.midX, y: court.maxY))
            lines.move(to: CGPoint(x: service.minX, y: service.midY))
            lines.addLine(to: CGPoint(x: service.maxX, y: service.midY))
            context.stroke(lines, with: .color(felt), lineWidth: 1.7)
          }.frame(width: 36, height: 22).frame(height: 32).accessibilityHidden(true)
        }
        Spacer()
        Image(systemName: "arrow.up.right").font(.subheadline.bold())
      }.padding(.bottom, 6)
      Text(title).font(.title3.bold())
      Text(detail).font(.caption.weight(.medium))
    }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .foregroundStyle(felt).background(color, in: RoundedRectangle(cornerRadius: 15))
      .accessibilityElement(children: .combine)
  }
  private func row(_ text: String, _ symbol: String) -> some View {
    HStack { Label(text, systemImage: symbol); Spacer(); Image(systemName: "chevron.right").font(.caption) }
      .font(.subheadline.weight(.semibold)).panel()
  }
}

private extension View {
  func panel() -> some View {
    padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
  }
}

struct MatchdayCompetitionCard: View {
  let title: String, subtitle: String, symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Image(systemName: symbol).foregroundStyle(.mint)
      Text(title).font(.headline)
      Text(subtitle).font(.caption).foregroundStyle(.secondary)
    }.frame(maxHeight: .infinity, alignment: .topLeading).panel()
  }
}
