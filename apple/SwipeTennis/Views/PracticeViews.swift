import SpriteKit
import SwiftUI

struct PracticeSetupView: View {
  @EnvironmentObject var store: AppStore
  @EnvironmentObject var account: CoachAccountStore
  @EnvironmentObject private var demos: ShotDemoStore
  @State private var training: TrainingExercise?
  @State private var settings = PracticeSettings()
  @EnvironmentObject private var slot: PracticeMatchSlot
  @State private var presentedMatch: SavedPracticeMatch?
  private var savedMatch: SavedPracticeMatch? { slot.match(for: account.identity?.userID ?? DemoProgressArchive.guest) }

  @State private var showGuide = false
  var body: some View {
    Form {
      if let savedMatch {
        Section {
          Button { presentedMatch = savedMatch } label: {
            Label {
              VStack(alignment: .leading, spacing: 4) {
                Text("Resume match").font(.headline)
                Text(resumeScore(savedMatch.engine)).font(.subheadline).foregroundStyle(.secondary)
              }
            } icon: { Image(systemName: "play.circle.fill") }
          }.accessibilityIdentifier("resumeSavedMatch")
        } footer: { Text("Starting a new match replaces this save.") }
      } else if let error = slot.loadError {
        Section { Text(error).foregroundStyle(.secondary) }
      }
      if !demos.progress.unlocksCourt {
        Section {
          Button("Quick play") {
            var quick = PracticeSettings(surface: settings.surface, allCourtTraining:false,scoring:.tiebreak,
              playerName:ApplePlayerName.display(account.identity?.emailMask))
            quick.venue = settings.matchVenue
            presentedMatch = SavedPracticeMatch(owner:account.identity?.userID ?? DemoProgressArchive.guest,
              engine:PracticeEngine(settings:quick))
          }.accessibilityIdentifier("quickGuestPlay")
        } footer: { Text("Play a seven-point tiebreak right away. Starting replaces the saved match on this device.") }
        Section {
          Label("Master the first five skills", systemImage: "lock.fill").font(.headline)
          Text("\(demos.progress.requiredMasteredCount)/5 complete. Complete the academy foundations to unlock custom match setup.")
            .font(.subheadline).foregroundStyle(.secondary)
          NavigationLink { ShotDemoHub() } label: {
            Label("Continue guided demo", systemImage: "figure.tennis")
          }.accessibilityIdentifier("unlockCourtDemo")
        }
      }
      Section("Tactics practice") {
        Button("Serve + 1", systemImage: "scope") { training = .servePlusOne }
        Button("Net positioning", systemImage: "figure.tennis") { training = .net }
      }
      Section {
        Picker("Play against", selection: $settings.local) {
          Text("Opponent").tag(false)
          Text("Local two-player").tag(true)
        }
        if !settings.local {
          Picker("Difficulty", selection: $settings.difficulty) {
            ForEach(Difficulty.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          Picker("Playing style", selection: $settings.style) {
            ForEach(BotStyle.allCases, id: \.self) { style in
              Label(style.rawValue, systemImage: style.symbol).tag(style)
            }
          }.pickerStyle(.navigationLink)
        }
      } header: { Text("Opponent") } footer: {
        Text(settings.local ? "Local two-player results stay off the public leaderboard."
          : "All difficulty levels count toward your Coachability personal bests. Playing style changes your opponent’s tactics.")
      }
      Section {
        Picker("Arena", selection: Binding(get: { settings.matchVenue }, set: { venue in
          settings.venue = venue; settings.surface = venue.surface
        })) {
          ForEach(TennisVenue.allCases, id: \.self) { Text("\($0.rawValue) · \($0.surface.rawValue)").tag($0) }
        }
        NavigationLink("Player & kit") { LockerRoom() }
        if !settings.local { Toggle("All-court training", isOn: $settings.allCourtTraining) }
      } header: { Text("Court") } footer: {
        Text("Swipe forward after your shot and before the far bounce to approach the net.")
      }
      Section {
        Picker("Scoring", selection: $settings.scoring) {
          ForEach(PracticeScoring.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("practiceScoring")
        LabeledContent("You", value: ApplePlayerName.display(account.identity?.emailMask))
          .accessibilityIdentifier("practicePlayerName")
        TextField("Opponent name (optional)", text: $settings.opponentName).textContentType(.name)
          .accessibilityIdentifier("practiceOpponentName")
      } header: { Text("Match") } footer: { Text(settings.scoring.detail) }
      Section {
        Button { showGuide = true } label: { Label("How to play", systemImage: "hand.draw") }
      } footer: { Text("Swipe toward yellow to receive and white to recover. A short swipe starts the run; use a fresh swipe from your moving player to choose a shot.") }
    }.navigationTitle("Play & practice")
      .fullScreenCover(item:$training) { TrainingCourtView($0,surface:settings.surface) }
      .safeAreaInset(edge: .bottom) {
        Button { takeCourt(using: settings) } label: {
          Label(savedMatch == nil ? "Take the court" : "Start new match", systemImage: demos.progress.unlocksCourt ? "play.fill" : "lock.fill").frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).controlSize(.large)
          .disabled(!demos.progress.unlocksCourt)
          .accessibilityHint(demos.progress.unlocksCourt ? "Start with your selected settings" : "Master the first five guided-demo skills to unlock")
          .accessibilityIdentifier("takeCourt").padding(.horizontal, 20).padding(.vertical, 10)
          .background(.bar)
      }
      .onAppear {
        settings = store.data.practice
        settings.playerName = ApplePlayerName.display(account.identity?.emailMask)
      }
      .onChange(of: account.identity?.emailMask) { _, mask in settings.playerName = ApplePlayerName.display(mask) }
      .onChange(of: demos.progress.unlocksCourt) { _, unlocked in if !unlocked { presentedMatch = nil } }
      .sensoryFeedback(.selection, trigger: settings.difficulty)
      .fullScreenCover(item: $presentedMatch) { match in
        PracticeGameView(match: match)
      }
      .sheet(isPresented: $showGuide) { CourtGuideView() }

  }
  private func resumeScore(_ engine: PracticeEngine) -> String {
    let score = engine.scoring
    if score.format == .tiebreak { return engine.scoreSummary }
    return "Games \(score.games[0])–\(score.games[1]) · Points \(score.pointLabel(0))–\(score.pointLabel(1))"
  }
  private func openNewMatch() {
    let owner = account.identity?.userID ?? DemoProgressArchive.guest
    presentedMatch = SavedPracticeMatch(owner: owner, engine: PracticeEngine(settings: settings))
  }
  private func takeCourt(using selected: PracticeSettings) {
    demos.activate(userID: account.identity?.userID)
    guard demos.progress.unlocksCourt else { return }
    settings = selected
    settings.playerName = ApplePlayerName.display(account.identity?.emailMask)
    store.data.practice = settings
    store.save()
    openNewMatch()
  }
}
struct PracticeGameView: View {
  @EnvironmentObject var account: CoachAccountStore
  @Environment(\.dismiss) var dismiss
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.verticalSizeClass) private var courtHeight
  @StateObject private var session: PracticeSession
  @State private var showCoach = false
  @State private var resumeAfterGuide = false
  @State private var showPointDetails = false
  @State private var training: TrainingExercise?
  @State private var replayReview: ReplayReview?
  @EnvironmentObject private var career: SoloCareerStore
  @EnvironmentObject private var slot: PracticeMatchSlot
  @State private var confirmingExit = false
  @State private var resumeAfterCancel = false
  @State private var saveError: String?
  let owner: String
  init(match: SavedPracticeMatch) {
    owner = match.owner
    _session = StateObject(wrappedValue: PracticeSession(engine: match.engine))
  }
  var game: PracticeEngine { session.snapshot }
  private var courtView: some View {
    LiveCourt(scene:session.scene,paused:session.paused || replayReview != nil)
    .accessibilityLabel("Practice court. \(game.isResolvingPoint ? game.pointResolution?.reaction?.affirmation?.text ?? game.feedback.title : game.feedback.title)")
    .accessibilityAction(named: "Show point result") { session.scene.dismissAffirmation() }
    .accessibilityAction(named: "Move to contact") {
      session.scene.engine.tapCourt(0, at: session.scene.engine.intercept(0))
    }
    .accessibilityAction(named: "Recover") { session.scene.engine.recover(0) }
    .accessibilityAction(named: "Approach the net") { session.scene.engine.followShot(0) }
    .accessibilityAction(named: "Split step") { session.scene.engine.beginSplit(0) }
    .accessibilityAction(named: "Serve") {
      session.scene.engine.requestServe(session.scene.engine.scoring.server)
      session.snapshot = session.scene.engine
    }
    .accessibilityAction(named: "Serve wide") { session.scene.engine.chooseServe(.wide, side: 0) }
    .accessibilityAction(named: "Serve center") { session.scene.engine.chooseServe(.center, side: 0) }
    .accessibilityAction(named: "Serve body") { session.scene.engine.chooseServe(.body, side: 0) }
  }
  var body: some View {
    let landscape = courtHeight == .compact
    let layout = landscape ? AnyLayout(HStackLayout(spacing:0)) : AnyLayout(VStackLayout(spacing:0))
    return VStack(spacing: 0) {
      layout {
        CourtBillboard(game: game, paused: session.paused, miss: session.coachMiss, onLeave: requestExit, onHelp: {
          resumeAfterGuide = !session.paused
          session.pause()
          showCoach = true
        }, onPause: {
          if session.paused { session.resume() } else { session.pause() }
        }).frame(width:landscape ? 180 : nil)
        ZStack {
          courtView
          .accessibilityAction(named: "Down the line") { session.scene.engine.selectShotSwipe(Vec(x: 0, y: -40), side: 0) }
          .accessibilityAction(named: "Crosscourt") {
            session.scene.engine.selectShotSwipe(Vec(x: game.players[0].pos.x < PracticeEngine.width / 2 ? 35 : -35, y: -35), side: 0)
          }
          .accessibilityAction(named: "Short angle") {
            session.scene.engine.selectShotSwipe(Vec(x: game.players[0].pos.x < PracticeEngine.width / 2 ? 40 : -40, y: 0), side: 0)
          }
          .accessibilityAction(named: "Lob") { session.scene.engine.selectShotSwipe(Vec(x: 0, y: 40), side: 0) }
          .accessibilityAction(named: "Drop shot") {
            if session.scene.engine.canChooseShot(0) { session.scene.engine.choose(0, .drop) }
          }
          .accessibilityAction(named: "Crosscourt slice") {
            if session.scene.engine.canChooseShot(0) { session.scene.engine.choose(0, .slice) }
          }
          if !session.paused, let serve = game.displayedServeGauges {
            GeometryReader { geometry in
              // The outer thirds leave room for the athlete and racket on both service sides.
              let width = min(144, geometry.size.width * 0.34)
              let editable = game.humanServing && serve.canTune
              HStack(spacing: 0) {
                ServeGauge(title: "Speed", level: serve.profile.speed, tint: TennisTheme.lime,
                  editable: editable) { setServe(speed: $0, side: serve.server) }
                  .frame(width: width)
                Spacer(minLength: 0)
                ServeGauge(title: "Spin", level: serve.profile.spin, tint: .mint,
                  editable: editable) { setServe(spin: $0, side: serve.server) }
                  .frame(width: width)
              }
              .environment(\.layoutDirection, .leftToRight)
              .padding(.horizontal, 12)
              .rotationEffect(.degrees(serve.server == 1 && game.settings.local ? 180 : 0))
              .frame(maxHeight: .infinity, alignment: serve.server == 0 ? .bottom : .top)
              .allowsHitTesting(game.humanServing)
            }
          }
          if let power = game.inventory.held, !game.settings.tournament, game.phase.isPlaying && !session.paused {
            Button {
              session.scene.engine.usePower()
              session.scene.publish?(session.scene.engine)
            } label: {
              Image(systemName: game.inventory.armed == true ? "checkmark" : power.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 30, height: 30)
                .background(Color.mint, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!game.canUsePower)
            .accessibilityLabel(power.rawValue).accessibilityValue(game.inventory.armed == true ? "Armed" : "Ready")
            .accessibilityHint(power.hint).accessibilityIdentifier("courtPower")
            .padding(.trailing, 2).padding(.bottom, game.displayedServeGauges?.server == 0 ? 35 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          }
          if let event = game.coach.events.last, event.success, game.phase.isPlaying && game.time - game.coach.lastEventAt < 1.5 {
            VStack {
              Text("\(event.success ? "+2" : "−1") CP · \(event.rule.title)")
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(event.success ? TennisTheme.green.opacity(0.94) : Color.black.opacity(0.8), in: Capsule())
                .padding(.top, 8)
              Spacer()
            }.allowsHitTesting(false)
          }
        }
      }.clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 4).padding(.bottom, 4)
    }.frame(maxWidth: 900).frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(TennisTheme.cream).foregroundStyle(TennisTheme.ink)
      .accessibilityHidden(game.showsPointResult && !session.paused && !showCoach)
      .overlay {
        if game.showsPointResult && !session.paused && !showCoach {
          PointResultOverlay(game: game, onContinue: advance, onDetails: { showPointDetails = true },
            onRetry: retrySeed == nil || game.coach.records.last?.winner != 1 || game.settings.local ? nil : { training = .retry },
            contact: session.scene.performance.replay.heights[0]?.label,
            onReplay: session.scene.performance.replay.canPlay ? {
              replayReview = ReplayReview(clip: session.scene.performance.replay, surface: game.settings.surface, venue:game.settings.matchVenue, handshake:game.phase == .finished,stadium:session.scene.stadium)
            } : nil)
        }
      }
      .onChange(of: game.showsPointResult) { _, visible in
        if visible && replayReview == nil && session.scene.performance.replay.canPlay {
          replayReview = ReplayReview(clip:session.scene.performance.replay,surface:game.settings.surface,
            venue:game.settings.matchVenue,automatic:true,handshake:game.phase == .finished,stadium:session.scene.stadium)
        }
      }
      .fullScreenCover(item:$training) { mode in
        if let seed = retrySeed { TrainingCourtView(mode,surface:game.settings.surface,original:seed,comparison:game.feedback.title + " " + game.feedback.reason) }
      }
      .sheet(item: $replayReview) { PointReplayView(review: $0).presentationDetents([.large]) }
      .sheet(isPresented: $showPointDetails) {
        NavigationStack {
          List {
            Section("Coachability \(game.coach.pointScore >= 0 ? "+" : "")\(game.coach.pointScore) CP") {
              CoachPointBreakdown(events: game.coach.events)
            }
          }.navigationTitle("Point details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPointDetails = false } } }
        }.presentationDragIndicator(.visible)
      }
      .onAppear {
        session.restoreInventory(owner: owner)
        if game.phase.isPlaying && !session.paused { session.scene.configureMotion() }
        session.scene.engine.settings.playerName = ApplePlayerName.display(account.identity?.emailMask)
        session.snapshot = session.scene.engine
        session.scene.reduceMotion = reduceMotion
        UIApplication.shared.isIdleTimerDisabled = true
      }
      .onDisappear {
        if training == nil { session.pause() }
        UIApplication.shared.isIdleTimerDisabled = false
      }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active {
          session.pause()
          checkpoint()
          UIApplication.shared.isIdleTimerDisabled = false
        } else {
          UIApplication.shared.isIdleTimerDisabled = true
        }
      }
      .onChange(of: reduceMotion) { _, value in session.scene.reduceMotion = value }
      .onChange(of: game.coach.records.last?.id) { _, id in
        if id != nil {
          if game.settings.pressureDay == nil, !game.settings.local, let point = game.coach.records.last { account.enqueue([point], owner: owner) }
          checkpoint()
        }
      }
      .onChange(of: game.scoring.winner) { _, winner in
        if let day = game.settings.pressureDay, let winner {
          DailyRival.record(day:day, won:winner == 0, owner:owner)
        }
      }
      .onChange(of: session.paused) { _, paused in
        if paused && game.settings.clubEncounter != nil && saveError == nil { checkpoint() }
      }
      .onChange(of: game.inventory) { _, _ in checkpoint() }
      .fullScreenCover(isPresented: $showCoach, onDismiss: {
        if resumeAfterGuide && scenePhase == .active { session.resume() }
      }) { CourtGuideView() }
      .sheet(isPresented: Binding(
        get: { !showCoach && (game.phase == .ready || session.paused) },
        set: { shown in if !shown && session.paused && !confirmingExit { session.resume() } }
      )) {
        PracticeSessionSheet(session: session, confirmingExit: confirmingExit, saveError: saveError,
          onStart: advance, onLeave: requestExit, onCancel: cancelExit,
          onSave: { leave(saving: true) }, onDiscard: { leave(saving: false) })
          .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
          .interactiveDismissDisabled(confirmingExit || !session.paused || game.phase == .ready)
      }
  }
  private var retrySeed: PracticeEngine? {
    let recording = session.scene.performance.replay
    if game.flight?.serve == true && game.flight?.hitter == 0 { return recording.serviceRetry }
    return recording.decisions[0]?.game ?? recording.serviceRetry
  }
  private func setServe(speed: ServeLevel? = nil, spin: ServeLevel? = nil, side: Int) {
    session.scene.engine.adjustServe(speed: speed, spin: spin, side: side)
    session.snapshot = session.scene.engine
  }
  private func advance() {
    do {
      if game.settings.clubEncounter != nil && game.phase == .finished {
        try career.checkpoint(session.scene.engine, owner: owner)
        dismiss()
        return
      }
      try session.start(save: saveMatch)
      saveError = nil
    } catch { showSaveError(error) }
  }
  private func saveMatch(_ engine: PracticeEngine) throws {
    if engine.settings.clubEncounter != nil { try career.checkpoint(engine, owner: owner) }
    else if engine.settings.pressureDay == nil { try slot.save(engine, owner: owner) }
  }
  private func checkpoint() {
    let engine = session.scene.engine
    do {
      if engine.settings.clubEncounter != nil { try career.checkpoint(engine, owner: owner); return }
      guard slot.match(for: owner)?.id == engine.coach.sessionID else { return }
      if engine.phase == .finished { try slot.discard(engine.coach.sessionID, owner: owner) }
      else { try slot.save(engine, owner: owner) }
    } catch { showSaveError(error) }
  }
  private func showSaveError(_ error: Error) {
    saveError = "Match storage is unavailable. \(error.localizedDescription)"
    session.pause()
  }
  private func requestExit() {
    resumeAfterCancel = game.phase != .ready && !session.paused
    if resumeAfterCancel { session.pause() }
    confirmingExit = true
  }
  private func cancelExit() {
    confirmingExit = false
    if resumeAfterCancel && scenePhase == .active { session.resume() }
    resumeAfterCancel = false
  }
  private func leave(saving: Bool) {
    let engine = session.scene.engine
    do {
      if engine.settings.clubEncounter != nil || saving { try saveMatch(engine) }
      else { try slot.discard(engine.coach.sessionID, owner: owner) }
      dismiss()
    } catch { showSaveError(error) }
  }
}

private struct ServeGauge: View {
  let title: String
  let level: ServeLevel
  let tint: Color
  let editable: Bool
  let select: (ServeLevel) -> Void

  @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 34

  var body: some View {
    GeometryReader { area in
      let labelSpace = min(labelWidth, area.size.width * 0.4)
      let start = labelSpace + 6
      let span = max(1, area.size.width - start - 6)
      ZStack(alignment: .leading) {
        Text(title)
          .font(.caption.weight(.semibold)).foregroundStyle(.white)
          .lineLimit(1).minimumScaleFactor(0.75)
          .frame(width: labelSpace, alignment: .leading)
        Canvas { context, size in
          let y = size.height / 2
          let marker = start + span * CGFloat(level.rawValue) / 2
          var track = Path()
          track.move(to: CGPoint(x: start, y: y))
          track.addLine(to: CGPoint(x: start + span, y: y))
          context.stroke(track, with: .color(.white.opacity(0.65)), lineWidth: 1.5)
          var ticks = Path()
          for stop in ServeLevel.allCases {
            let x = start + span * CGFloat(stop.rawValue) / 2
            ticks.move(to: CGPoint(x: x, y: y - 3))
            ticks.addLine(to: CGPoint(x: x, y: y + 3))
          }
          context.stroke(ticks, with: .color(.white.opacity(0.8)), lineWidth: 1)
          var needle = Path()
          needle.move(to: CGPoint(x: marker - 3, y: y - 6))
          needle.addLine(to: CGPoint(x: marker + 3, y: y - 6))
          needle.addLine(to: CGPoint(x: marker, y: y + 5))
          needle.closeSubpath()
          context.fill(needle, with: .color(tint))
        }
      }
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { touch in
        guard editable else { return }
        // Touching the label starts calibration without moving the needle.
        if touch.location.x < labelSpace { select(level); return }
        let fraction = min(1, max(0, (touch.location.x - start) / span))
        if let value = ServeLevel(rawValue: Int((fraction * 2).rounded())) { select(value) }
      })
    }.frame(height: 44)
    .accessibilityRepresentation {
      Slider(value: Binding(get: { Double(level.rawValue) }, set: { raw in
        if editable, let value = ServeLevel(rawValue: Int(raw.rounded())) { select(value) }
      }), in: 0...2, step: 1) { Text(title) }
        .accessibilityValue(level.label)
        .accessibilityIdentifier("serveGauge" + title)
        .disabled(!editable)
    }
  }
}

struct PracticeSessionSheet: View {
  @ObservedObject var session: PracticeSession
  let confirmingExit: Bool
  let saveError: String?
  let onStart: () -> Void
  let onLeave: () -> Void
  let onCancel: () -> Void
  let onSave: () -> Void
  let onDiscard: () -> Void
  @State private var confirmRestart = false
  @State private var showGuide = false
  var game: PracticeEngine { session.snapshot }
  private var canSave: Bool { game.settings.pressureDay == nil && game.phase != .ready && game.phase != .finished }
  private var title: String {
    confirmingExit ? "Leaving the court" : game.phase == .ready ? (game.settings.clubEncounter?.title ?? "Ready to play") : "Match paused"
  }
  private var primary: String {
    confirmingExit ? (canSave ? "Save & leave" : "Leave court") : game.phase == .ready ? "Start match" : "Resume match"
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 10) {
            Label("\(game.settings.surface.rawValue) court · \(game.settings.clubEncounter != nil ? "First to 10 · Win by two" : game.scoring.format == .tennis ? "One set" : "Tiebreak")",
              systemImage: "tennisball").font(.subheadline.weight(.semibold)).foregroundStyle(TennisTheme.lime)
            ForEach(0..<2) { side in
              HStack {
                Text(game.name(side)).font(.title3.weight(.semibold))
                if game.scoring.server == side {
                  Image(systemName: "tennisball.fill").font(.caption).foregroundStyle(TennisTheme.lime)
                    .accessibilityLabel("Serving")
                }
                Spacer()
                if game.phase != .ready || game.settings.clubEncounter != nil {
                  Text(game.scoring.format == .tennis ? "\(game.scoring.games[side])   \(game.scoring.pointLabel(side))" : game.scoring.pointLabel(side))
                    .font(.title3.monospacedDigit()).accessibilityLabel(game.scoring.format == .tennis
                      ? "\(game.scoring.games[side]) games, \(game.scoring.pointLabel(side)) points" : "\(game.scoring.points[side]) points")
                }
              }.foregroundStyle(.white)
            }
          }
          .padding(16).background(Color(red: 0.08,green: 0.23,blue: 0.19), in: RoundedRectangle(cornerRadius: 18))
          if let encounter = game.settings.clubEncounter, !confirmingExit {
            Label(encounter.cue, systemImage: "figure.tennis").font(.subheadline)
            if encounter == .debut && game.phase == .ready {
              Text("Swipe toward yellow to run. While moving, swipe diagonally from your player to aim crosscourt.")
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          if let saveError { Label(saveError, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
          if confirmingExit && canSave {
            Text(game.settings.clubEncounter == nil ? "Save this match to pick up from here in Play & practice." : "Continue Career will bring you back to this point.").font(.subheadline).foregroundStyle(.secondary)
          }
          Button {
            if confirmingExit { if canSave { onSave() } else { onDiscard() } }
            else if game.phase == .ready { onStart() } else { session.resume() }
          } label: {
            Label(primary, systemImage: confirmingExit ? (canSave ? "bookmark.fill" : "door.left.hand.open") : "play.fill")
              .font(.headline).frame(maxWidth: .infinity, minHeight: 32)
          }.buttonStyle(.borderedProminent).controlSize(.large).tint(Color(red: 0.10,green: 0.38,blue: 0.29))
            .accessibilityIdentifier(confirmingExit ? (canSave ? "saveAndLeave" : "leaveCourt") : "startPractice")
          if confirmingExit {
            Button("Stay on court", action: onCancel).buttonStyle(.bordered).controlSize(.large)
              .frame(maxWidth: .infinity).accessibilityIdentifier("stayOnCourt")
            if canSave && game.settings.clubEncounter == nil {
              Button("Leave without saving", role: .destructive, action: onDiscard)
                .font(.subheadline).frame(maxWidth: .infinity,minHeight: 44)
            }
          } else {
            HStack {
              Button("How to play", systemImage: "questionmark.circle") { showGuide = true }
              Spacer()
              Button("Leave court", systemImage: "door.left.hand.open", action: onLeave)
            }.font(.subheadline.weight(.medium)).buttonStyle(.borderless).frame(minHeight: 44)
          }
        }.padding(.horizontal,20).padding(.vertical,10)
      }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          if !confirmingExit && game.phase != .ready && game.settings.clubEncounter == nil {
            ToolbarItem(placement: .topBarTrailing) {
              Menu { Button("Restart session", role: .destructive) { confirmRestart = true } }
                label: { Label("Match options", systemImage: "ellipsis.circle") }
            }
          }
        }.sheet(isPresented: $showGuide) { CourtGuideView() }
        .confirmationDialog("Restart this practice session?", isPresented: $confirmRestart, titleVisibility: .visible) {
          Button("Restart", role: .destructive) { session.restart() }
        }
    }
  }
}

struct PointResultOverlay: View {
  let game: PracticeEngine
  let onContinue: () -> Void
  let onDetails: () -> Void
  var onRetry: (() -> Void)? = nil
  var contact: String?
  var onReplay: (() -> Void)? = nil
  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.black.opacity(0.42).ignoresSafeArea()
        ViewThatFits(in: .vertical) {
          card(compact: false)
          card(compact: true)
          // Only unusually large accessibility text needs a scroll fallback.
          ScrollView { card(compact: true) }
        }.frame(maxWidth: 460).padding(.horizontal, 16).padding(.vertical, 12)
          .frame(width: geometry.size.width, height: geometry.size.height)
      }
    }.accessibilityAddTraits(.isModal)
  }
  private func card(compact: Bool) -> some View {
    PointResultCard(game: game, compact: compact,
      onContinue: onContinue, onDetails: onDetails, onRetry:onRetry, contact:contact, onReplay: onReplay)
  }
}

/// A single-screen recap, with a bounded row per rule rather than a scrolling event log.
struct PointResultCard: View {
  let game: PracticeEngine
  var compact = false
  let onContinue: () -> Void
  let onDetails: () -> Void
  var onRetry: (() -> Void)? = nil
  var contact: String?
  var onReplay: (() -> Void)? = nil
  private var rows: [CoachPointSummary] { CoachPointSummary.rows(for: game.coach.events) }
  private var nextTitle: String {
    game.phase == .finished ? (game.settings.clubEncounter == nil ? "Play again" : "Career recap") : game.scoring.lastAward == .game ? "Next game" : "Next point"
  }
  var body: some View {
    VStack(spacing: compact ? 10 : 14) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 5) {
          Text(game.feedback.title)
            .font(.system(compact ? .title3 : .title2, design: .serif).weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
          if let power = game.powerEarnedThisPoint {
            Label("Power earned · \(power.rawValue)", systemImage: power.symbol)
              .font(.caption.bold()).foregroundStyle(.mint)
          }
          Text(game.feedback.reason).font(.caption).foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
          Text(game.pointSplitSummary).font(.caption.weight(.semibold)).foregroundStyle(.mint)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pointSplitBonus")
        }
        Spacer(minLength: 0)
        Button(action: onContinue) { Image(systemName: "xmark").frame(width: 44, height: 44) }
          .buttonStyle(.plain).accessibilityLabel(nextTitle).accessibilityIdentifier("closePointResult")
      }
      if let note = game.changeoverNote { Label(note,systemImage:"binoculars.fill").font(.caption) }
      if let contact { Text("Last contact · " + contact).font(.caption.monospacedDigit()) }
      if let onRetry { Button("Retry this ball",systemImage:"arrow.uturn.backward",action:onRetry).font(.subheadline).buttonStyle(.bordered) }
      VStack(spacing: 3) {
        Text(game.scoreSummary).font(.caption.weight(.semibold))
          .accessibilityIdentifier(game.scoring.format == .tiebreak ? "resultScore" : "resultGames")

        if game.scoring.format == .tennis && game.phase != .finished {
          Text("Points: \(game.name(0)) \(game.scoring.pointLabel(0)) · \(game.name(1)) \(game.scoring.pointLabel(1))")
            .font(.caption).accessibilityIdentifier("resultScore")
        }
      }.monospacedDigit().foregroundStyle(TennisTheme.lime).multilineTextAlignment(.center)
      Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
      HStack {
        Text("Coachability").font(.subheadline.weight(.semibold))
        if !rows.isEmpty {
          Button(action: onDetails) { Image(systemName: "info.circle").frame(width: 44,height: 44) }
            .buttonStyle(.plain).accessibilityLabel("All Coachability actions for this point")
        }
        Spacer()
        Text("\(game.coach.pointScore >= 0 ? "+" : "")\(game.coach.pointScore) CP")
          .font(.headline.monospacedDigit()).foregroundStyle(TennisTheme.lime)
      }
      VStack(alignment: .leading, spacing: compact ? 7 : 10) {
        if rows.isEmpty {
          Text("No CP opportunities this point.").font(.subheadline).foregroundStyle(.white.opacity(0.8))
        }
        ForEach(rows) { row in
          HStack(alignment: .top, spacing: 10) {
            Text(row.score).font((compact ? Font.caption : .subheadline).weight(.bold).monospacedDigit())
              .foregroundStyle(row.misses == 0 ? TennisTheme.lime : row.successes == 0 ? Color(red: 1, green: 0.66, blue: 0.62) : .white)
              .frame(width: 68, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
              Text(row.reason).font(compact ? .caption : .subheadline)
                .fixedSize(horizontal: false, vertical: true)
              if let tally = row.tally {
                Text(tally).font(.caption2).foregroundStyle(.white.opacity(0.7))
              }
            }
          }.accessibilityElement(children: .combine)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("pointCoachSummary")
      HStack(spacing: 10) {
        if let onReplay {
          Button(action: onReplay) {
            Label("Replay point", systemImage: "arrow.counterclockwise.circle.fill")
              .font(.headline).foregroundStyle(Color(red: 0.06,green: 0.16,blue: 0.27))
              .frame(maxWidth: .infinity,minHeight: 46)
              .background(Color(red: 0.55,green: 0.83,blue: 1), in: RoundedRectangle(cornerRadius: 14))
          }.buttonStyle(.plain).accessibilityHint("Watch this point at half speed from three angles.")
            .accessibilityIdentifier("replayPracticePoint")
        }
        Button(action: onContinue) {
          Text(nextTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Color(red: 0.1, green: 0.22, blue: 0.17))
            .background(TennisTheme.lime, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("nextPracticePoint")
      }
    }.foregroundStyle(.white).padding(compact ? 16 : 20)
      .background(Color(red: 0.09, green: 0.22, blue: 0.16), in: RoundedRectangle(cornerRadius: 24))
      .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 1) }
      .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
  }
}

struct CoachPointBreakdown: View {
  let events: [CoachEvent]
  var body: some View {
    if events.isEmpty {
      Text("No Coachability opportunities on this point.").font(.subheadline).foregroundStyle(.secondary)
    } else {
      ForEach(events) { event in
        HStack(alignment: .top, spacing: 12) {
          Text(event.success ? "+2" : "−1").font(.headline.monospacedDigit())
            .foregroundStyle(event.success ? TennisTheme.accent : .red).frame(width: 30)
          Text(event.reason).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 3).accessibilityElement(children: .combine)
      }.accessibilityIdentifier("pointCoachReasons")
    }
  }
}

private enum DailyRival {
  static let rivals: [TourRival] = [.casey, .morgan, .jules]
  static func index(_ day: Int) -> Int { (day + day / 3) % rivals.count }
  static func results(_ owner: String) -> [String:Bool] {
    UserDefaults.standard.dictionary(forKey:"pressure.results."+owner) as? [String:Bool] ?? [:]
  }
  static func record(day: Int, won: Bool, owner: String) {
    var saved = results(owner)
    guard saved[String(day)] == nil else { return }
    saved[String(day)] = won
    UserDefaults.standard.set(saved,forKey:"pressure.results."+owner)
  }
}
struct DailyPressureSection: View {
  @EnvironmentObject private var account: CoachAccountStore
  @State private var match: SavedPracticeMatch?
  @State private var results: [String:Bool] = [:]
  private var owner: String { account.identity?.userID ?? DemoProgressArchive.guest }
  var body: some View {
    TimelineView(.periodic(from:.now,by:60)) { time in
      let day = Int(time.date.timeIntervalSince1970 / 86400)
      let rival = DailyRival.index(day)
      let opponent = DailyRival.rivals[rival]
      let name = opponent.rawValue
      let past = results.compactMap { key, won -> (Int,Bool)? in
        guard let date = Int(key), date < day, DailyRival.index(date) == rival else { return nil }
        return (date,won)
      }.sorted { $0.0 > $1.0 }
      Section("Daily pressure challenge") {
        let start = ["5–6","6–5","6–6"][day % 3]
        Button {
          var settings = PracticeSettings(style:opponent.style,scoring:.tiebreak,opponentName:name)
          settings.pressureDay = day
          match = SavedPracticeMatch(owner:owner,engine:PracticeEngine(settings:settings))
        } label: {
          Label(results[String(day)] == nil ? "Play \(name) from \(start)" : "Play \(name) again from \(start)",systemImage:"tennisball.fill")
        }
        if let today = results[String(day)] { Text(today ? "Today’s challenge won" : "Today’s challenge lost") }
        if let last = past.first {
          Text(last.1 ? "\(name) returns for a rematch after your last win. You won \(past.filter { $0.1 }.count) of your \(past.count) past meetings." : "\(name) won your last meeting. Read the \(opponent.style.rawValue.lowercased()) pattern and turn the result around.").font(.caption)
        } else { Text("First meeting with \(name). \(opponent.style.detail)").font(.caption) }
      }
    }.task(id:owner) { results = DailyRival.results(owner) }
      .fullScreenCover(item:$match,onDismiss:{ results = DailyRival.results(owner) }) { PracticeGameView(match:$0) }
  }
}
