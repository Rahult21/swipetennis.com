import SpriteKit
import SwiftUI

struct PracticeSetupView: View {
  @EnvironmentObject var store: AppStore
  @EnvironmentObject var account: CoachAccountStore
  @EnvironmentObject private var demos: ShotDemoStore
  @State private var settings = PracticeSettings()
  @EnvironmentObject private var slot: PracticeMatchSlot
  @State private var presentedMatch: SavedPracticeMatch?
  private var savedMatch: SavedPracticeMatch? { slot.match(for: account.identity?.userID) }
  @State private var signingIn = false
  @State private var showGuide = false
  var body: some View {
    Form {
      if let savedMatch, demos.progress.unlocksCourt {
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
          Label("Master the first five skills", systemImage: "lock.fill").font(.headline)
          Text("\(demos.progress.requiredMasteredCount)/5 complete. Finish the required guided-demo skills to unlock Take the court.")
            .font(.subheadline).foregroundStyle(.secondary)
          NavigationLink { ShotDemoHub() } label: {
            Label("Continue guided demo", systemImage: "figure.tennis")
          }.accessibilityIdentifier("unlockCourtDemo")
        }
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
        Picker("Surface", selection: $settings.surface) {
          ForEach(CourtSurface.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
        if !settings.local { Toggle("All-court training", isOn: $settings.allCourtTraining) }
      } header: { Text("Court") } footer: {
        Text("You choose when to move in. Swipe forward after your shot to approach the net.")
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
      } footer: { Text("Tap yellow to receive, white to recover. Swipe from your player to choose a shot.") }
    }.navigationTitle("Play & practice")
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
      .sheet(isPresented: $signingIn, onDismiss: {
        demos.activate(userID: account.identity?.userID)
        if demos.progress.unlocksCourt { openNewMatch() }
      }) {
        NavigationStack {
          CoachAccountScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { signingIn = false } } }
            .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { signingIn = false } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
      }
  }
  private func resumeScore(_ engine: PracticeEngine) -> String {
    let score = engine.scoring
    if score.format == .tiebreak { return engine.scoreSummary }
    return "Games \(score.games[0])–\(score.games[1]) · Points \(score.pointLabel(0))–\(score.pointLabel(1))"
  }
  private func openNewMatch() {
    guard let owner = account.identity?.userID else { return }
    presentedMatch = SavedPracticeMatch(owner: owner, engine: PracticeEngine(settings: settings))
  }
  private func takeCourt(using selected: PracticeSettings) {
    demos.activate(userID: account.identity?.userID)
    guard demos.progress.unlocksCourt else { return }
    settings = selected
    settings.playerName = ApplePlayerName.display(account.identity?.emailMask)
    store.data.practice = settings
    store.save()
    if account.isSignedIn { openNewMatch() } else { signingIn = true }
  }
}
struct PracticeGameView: View {
  @EnvironmentObject var account: CoachAccountStore
  @Environment(\.dismiss) var dismiss
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @StateObject private var session: PracticeSession
  @State private var showCoach = false
  @State private var resumeAfterGuide = false
  @State private var showPointDetails = false
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
    SpriteView(
      scene: session.scene, isPaused: session.paused,
      preferredFramesPerSecond: ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 120
    )
    .accessibilityLabel("Practice court. \(game.isResolvingPoint ? game.pointResolution?.reaction?.affirmation?.text ?? game.feedback.title : game.feedback.title)")
    .accessibilityAction(named: "Show point result") { session.scene.dismissAffirmation() }
    .accessibilityAction(named: "Move to contact") {
      session.scene.engine.tapCourt(0, at: session.scene.engine.intercept(0))
    }
    .accessibilityAction(named: "Recover") { session.scene.engine.recover(0) }
    .accessibilityAction(named: "Approach the net") { session.scene.engine.followShot(0) }
    .accessibilityAction(named: "Split step") { session.scene.engine.beginSplit(0) }
    .accessibilityAction(named: "Serve") { session.scene.engine.requestServe(0) }
    .accessibilityAction(named: "Serve wide") { session.scene.engine.chooseServe(.wide, side: 0) }
    .accessibilityAction(named: "Serve center") { session.scene.engine.chooseServe(.center, side: 0) }
    .accessibilityAction(named: "Serve body") { session.scene.engine.chooseServe(.body, side: 0) }
  }
  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        CourtBillboard(game: game, paused: session.paused, miss: session.coachMiss, onLeave: requestExit, onHelp: {
          resumeAfterGuide = !session.paused
          session.pause()
          showCoach = true
        }, onPause: {
          if session.paused { session.resume() } else { session.pause() }
        })
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
          if game.humanServing, !session.paused, let serve = game.servePreparation, !serve.isTossing {
            ServeMeters(serve: serve, adjust: { speed, spin in
              session.scene.engine.adjustServe(speed: speed, spin: spin, side: serve.server)
              session.snapshot = session.scene.engine
            })
            .padding(.leading, 8).padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          }
          if let power = game.inventory.held, game.phase.isPlaying && !session.paused {
            VStack(alignment: .trailing, spacing: 4) {
              Button {
                session.scene.engine.usePower()
                session.snapshot = session.scene.engine
              } label: {
                Image(systemName: power.symbol).font(.title2.bold())
                  .frame(width: 54, height: 54)
                  .foregroundStyle(game.canUsePower ? Color.black : .white)
                  .background(game.canUsePower ? Color.mint : Color.black.opacity(0.8), in: Circle())
                  .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
              }
              .buttonStyle(.plain)
              .disabled(!game.canUsePower)
              .accessibilityLabel(power.rawValue)
              .accessibilityHint(power.hint)
              Text(power.rawValue).font(.caption2.bold())
              Text(game.queuedPower != nil ? "In motion" : game.canUsePower ? "Tap to use" : power.prompt)
                .font(.caption2)
            }
            .foregroundStyle(.white).shadow(radius: 2)
            .padding(.trailing, 10).padding(.bottom, 9)
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
          PointResultOverlay(game: game, onContinue: advance, onDetails: { showPointDetails = true })
        }
      }
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
        session.pause()
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
          if !game.settings.local, let point = game.coach.records.last { account.enqueue([point], owner: owner) }
          checkpoint()
        }
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
  private func advance() {
    do {
      try session.start(owner: owner, slot: slot)
      saveError = nil
    } catch { showSaveError(error) }
  }
  private func checkpoint() {
    let engine = session.scene.engine
    guard slot.match(for: owner)?.id == engine.coach.sessionID else { return }
    do {
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
      if saving { try slot.save(engine, owner: owner) }
      else { try slot.discard(engine.coach.sessionID, owner: owner) }
      dismiss()
    } catch { showSaveError(error) }
  }
}

private struct ServeMeters: View {
  let serve: ServePreparation
  let adjust: (ServeLevel?, ServeLevel?) -> Void
  private var hint: String {
    if !serve.pickedBlue { return "Place blue to adjust" }
    if serve.canTune { return serve.customProfile == nil ? "Adjust now" : "Tap court to serve" }
    return serve.tuningDeadline == nil ? "Release blue to adjust" : "Tap court to serve"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      meter("Speed", value: serve.profile.speed) { adjust($0, nil) }
      meter("Topspin", value: serve.profile.spin) { adjust(nil, $0) }
      Text(hint).font(.caption2).foregroundStyle(.secondary)
    }
    .padding(8).frame(width: 170)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
  }

  private func meter(_ title: String, value: ServeLevel, set: @escaping (ServeLevel) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.caption2.bold())
      ServeLevelControl(title: title, value: value, enabled: serve.canTune,
        begin: { if serve.customProfile == nil { set(value) } }, select: set)
        .frame(height: 32)
    }
  }
}

private struct ServeLevelControl: UIViewRepresentable {
  let title: String
  let value: ServeLevel
  let enabled: Bool
  let begin: () -> Void
  let select: (ServeLevel) -> Void

  final class Control: UISegmentedControl {
    var begin: (() -> Void)?
    var select: ((ServeLevel) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      // A finger down inside the window reserves both meters until the toss.
      if isEnabled { begin?() }
      super.touchesBegan(touches, with: event)
    }

    @objc func selectionChanged() {
      if let level = ServeLevel(rawValue: selectedSegmentIndex) { select?(level) }
    }
  }

  func makeUIView(context: Context) -> Control {
    let control = Control(items: ServeLevel.allCases.map(\.label))
    control.addTarget(control, action: #selector(Control.selectionChanged), for: .valueChanged)
    control.accessibilityLabel = title
    control.accessibilityIdentifier = "serveMeter" + title
    return control
  }

  func updateUIView(_ control: Control, context: Context) {
    control.begin = begin
    control.select = select
    control.isEnabled = enabled
    control.selectedSegmentIndex = value.rawValue
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
  var title: String { confirmingExit ? "Leave the court?" : session.paused ? "Paused" : "Ready to play" }
  var actionTitle: String { game.phase == .ready ? "Start practice" : "Resume rally" }
  var body: some View {
    NavigationStack {
      List {
        if let saveError { Section { Text(saveError).foregroundStyle(.red) } }
        if confirmingExit {
          Section {
            if game.phase != .ready && game.phase != .finished {
              Button("Save & leave", systemImage: "bookmark", action: onSave)
                .accessibilityIdentifier("saveAndLeave")
              Button("Leave without saving", role: .destructive, action: onDiscard)
            } else {
              Button("Leave court", role: .destructive, action: onDiscard)
            }
            Button("Cancel", role: .cancel, action: onCancel)
          } footer: {
            if game.phase != .ready && game.phase != .finished {
              Text("Save this match on your iPhone to pick up at this point from Play & practice.")
            }
          }
        } else {
          Section {
            Label(session.paused ? "Take a breath." : "Make the court your own.",
              systemImage: session.paused ? "pause.circle" : "tennisball")
              .font(.title2.bold()).padding(.vertical, 4)
            Text(session.paused ? "Your rally is paused."
              : "Swipe from your player to choose a shot. Swipe elsewhere to move. Tap yellow to receive and white to recover.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          if session.paused && game.phase != .ready {
            Section { Button("Restart session", role: .destructive) { confirmRestart = true } }
          }
        }
      }.listStyle(.insetGrouped).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
          if !confirmingExit {
            Button(actionTitle) {
              if game.phase == .ready { onStart() }
              else { session.resume() }
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
              .accessibilityIdentifier("startPractice").padding(.horizontal, 20).padding(.vertical, 10)
              .background(.bar)
          }
        }
        .toolbar {
          if !confirmingExit {
            ToolbarItem(placement: .cancellationAction) { Button("Leave", action: onLeave) }
            ToolbarItem(placement: .topBarTrailing) {
              Button("How to play", systemImage: "questionmark.circle") { showGuide = true }.labelStyle(.iconOnly)
            }
          }
        }
        .sheet(isPresented: $showGuide) { CourtGuideView() }
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
      onContinue: onContinue, onDetails: onDetails)
  }
}

/// A single-screen recap, with a bounded row per rule rather than a scrolling event log.
struct PointResultCard: View {
  let game: PracticeEngine
  var compact = false
  let onContinue: () -> Void
  let onDetails: () -> Void
  private var rows: [CoachPointSummary] { CoachPointSummary.rows(for: game.coach.events) }
  private var nextTitle: String {
    game.phase == .finished ? "Play again" : game.scoring.lastAward == .game ? "Next game" : "Next point"
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
        }
        Spacer(minLength: 0)
        Button(action: onContinue) { Image(systemName: "xmark").frame(width: 44, height: 44) }
          .buttonStyle(.plain).accessibilityLabel(nextTitle).accessibilityIdentifier("closePointResult")
      }
      VStack(spacing: 3) {
        Text(game.scoreSummary).font(.caption.weight(.semibold))
        if game.scoring.format == .tennis && game.phase != .finished {
          Text("Points: \(game.name(0)) \(game.scoring.pointLabel(0)) · \(game.name(1)) \(game.scoring.pointLabel(1))")
            .font(.caption)
        }
      }.monospacedDigit().foregroundStyle(TennisTheme.lime).multilineTextAlignment(.center)
      Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
      HStack {
        Text("Coachability").font(.subheadline.weight(.semibold))
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
      HStack(spacing: 12) {
        if !rows.isEmpty {
          Button("Details", action: onDetails).font(.subheadline)
            .frame(minHeight: 44).foregroundStyle(.white)
            .accessibilityLabel("All Coachability actions for this point")
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
