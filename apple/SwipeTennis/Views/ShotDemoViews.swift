import SpriteKit
import SwiftUI

struct ShotDemoLink: View {
  @EnvironmentObject private var demos: ShotDemoStore
  var body: some View {
    NavigationLink { ShotDemoHub() } label: {
      Label {
        VStack(alignment: .leading, spacing: 3) {
          Text("Tennis academy").font(.headline)
          Text(demos.progress.remaining.isEmpty ? "All skills mastered"
            : demos.progress.unlocksCourt ? "Watch, try, and master each skill" : "Master the first five skills to take the court")
            .font(.subheadline).foregroundStyle(.secondary)
        }
      } icon: { Image(systemName: "figure.tennis").foregroundStyle(TennisTheme.accent) }
    }.accessibilityIdentifier("guidedShotDemo")
  }
}

struct ShotDemoHub: View {
  @EnvironmentObject private var demos: ShotDemoStore
  @State private var selected: DemoLesson?
  private var count: Int { DemoLesson.allCases.count - demos.progress.remaining.count }
  var body: some View {
    List {
      Section {
        Label("Learn every skill", systemImage: "figure.tennis").font(.title2.bold())
        Text("Watch, then try. \(DemoMastery.target) clean attempts in a row master a skill. For the first two skills, one attempt is a \(ShotDemoRun.exchangesPerAttempt)-exchange rally with recovery after every return. A miss restarts that skill's streak.")
          .font(.subheadline).foregroundStyle(.secondary)
        ProgressView(value: Double(count), total: Double(DemoLesson.allCases.count))
        Text("\(count) of \(DemoLesson.allCases.count) skills mastered").font(.subheadline.weight(.semibold))
      } footer: {
        Text("Mastered skills disappear from this demo. Progress saves on this iPhone. Ball pace builds toward match speed as you advance. Feeds alternate sides for forehand and backhand practice. Demo drills do not earn leaderboard CP.")
      }
      Section {
        Label(demos.progress.unlocksCourt ? "Take the court is unlocked" : "Unlock Take the court",
          systemImage: demos.progress.unlocksCourt ? "lock.open.fill" : "lock.fill").font(.headline)
        Text("\(demos.progress.requiredMasteredCount) of 5 required skills mastered")
          .font(.subheadline).foregroundStyle(.secondary)
        if !demos.progress.unlocksCourt {
          Text("Complete skills 1–5: rally and recovery, recover and split step, crosscourt, down the line, and short angle.")
            .font(.subheadline)
        }
      }
      AcademyRecommendation(owner:demos.profile) { selected = $0 }.id(demos.profile)
      if let error = demos.storageError { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) } }
      if let next = demos.progress.next {
        Section {
          Button { selected = next } label: {
            Label("Continue with \(next.title.lowercased())", systemImage: "play.fill").font(.headline)
          }.accessibilityIdentifier("continueShotDemo")
        }
        Section("Still to master") {
          ForEach(demos.progress.remaining) { lesson in
            Button { selected = lesson } label: {
              HStack(spacing: 12) {
                Image(systemName: lesson.symbol).frame(width: 26).foregroundStyle(TennisTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                  Text("\(lesson.number). \(lesson.title)").foregroundStyle(.primary)
                  if DemoLesson.courtEntrySkills.contains(lesson) {
                    Text("Required to take the court").font(.caption).foregroundStyle(.secondary)
                  }
                }
                Spacer()
                Text("\(demos.progress.mastery(lesson).completedAttempts)/\(DemoMastery.target)").monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
              }.padding(.vertical, 4)
            }.accessibilityIdentifier("demoLesson_\(lesson.rawValue)")
          }
        }
      } else {
        Section {
          ContentUnavailableView("Every skill mastered", systemImage: "checkmark.seal.fill",
            description: Text("You're ready to put them together in Play & practice. Your mastered skills will stay out of this demo."))
        }
      }
    }.listStyle(.insetGrouped).navigationTitle("Tennis academy")
      .onChange(of: demos.profile) { _, _ in selected = nil }
      .fullScreenCover(item: $selected) { lesson in
        ShotDemoFlowView(first: lesson)
      }
  }
}

struct ShotDemoFlowView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var demos: ShotDemoStore
  @State private var flow: DemoLessonFlow
  init(first: DemoLesson) { _flow = State(initialValue: DemoLessonFlow(first: first)) }
  var body: some View {
    NavigationStack {
      if let lesson = flow.current {
        ShotDemoLessonView(lesson: lesson, store: demos, onNext: { [completed = lesson] in
          guard flow.advance(after: completed, progress: demos.progress) else { return }
          if flow.current == nil { dismiss() }
        }).id(lesson.id)
      }
    }
  }
}

struct ShotDemoLessonView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var demos: ShotDemoStore
  @StateObject private var session: ShotDemoSession
  let onNext: () -> Void
  init(lesson: DemoLesson, store: ShotDemoStore, onNext: @escaping () -> Void) {
    _session = StateObject(wrappedValue: ShotDemoSession(lesson: lesson, store: store))
    self.onNext = onNext
  }
  private var run: ShotDemoRun? { session.snapshot.demo }
  private var watching: Bool { run?.demonstration == true }
  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Label(watching ? "Watch the motion" : session.mastered ? "Mastered" : "Your turn",
            systemImage: watching ? "eye" : session.mastered ? "checkmark.seal.fill" : "hand.draw")
            .font(.subheadline.weight(.semibold)).foregroundStyle(TennisTheme.accent)
          Spacer()
          HStack(spacing: 5) {
            ForEach(0..<DemoMastery.target) { index in
              Image(systemName: index < session.streak ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(index < session.streak ? TennisTheme.accent : .secondary)
            }
          }.accessibilityElement(children: .ignore).accessibilityLabel("\(session.streak) of \(DemoMastery.target) consecutive clean attempts")
        }
        Text(run?.instruction ?? session.lesson.instruction).font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
        if session.lesson.isFootwork {
          Text("\(run?.completedExchanges ?? 0)/\(ShotDemoRun.exchangesPerAttempt) exchanges · \(ShotDemoRun.exchangesPerAttempt) exchanges = one clean attempt")
            .font(.caption.weight(.semibold)).monospacedDigit()
            .accessibilityIdentifier("demoExchangeProgress")
        }
        if watching { Text("Watch only — this attempt doesn't count.").font(.caption).foregroundStyle(.secondary) }
        if let error = demos.storageError { Text(error).font(.caption).foregroundStyle(.red) }
      }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
      ZStack {
        LiveCourt(scene:session.scene,paused:session.paused)
          .accessibilityLabel("Demo court. \(run?.instruction ?? "")")
          .accessibilityAction(named: "Move to yellow") {
            session.input { engine in if let point = engine.contactGuide(0) { engine.tapCourt(0, at: point) } }
          }
          .accessibilityAction(named: "Return to white") {
            session.input { engine in if let point = engine.recoveryGuide(0) { engine.tapCourt(0, at: point) } }
          }
          .accessibilityAction(named: "Split step") { session.input { $0.beginSplit(0) } }
          .accessibilityAction(named: "Select the lesson shot") { selectAccessibleShot() }
          .accessibilityAction(named: "Follow the ball to the net") { session.input { $0.swipeCourt(0, delta: Vec(x: 0, y: -3)) } }
          .accessibilityAction(named: "Aim serve at the target") {
            session.input { engine in if let target = engine.demo?.target { engine.aimServe(at: target, side: 0) } }
          }
          .accessibilityAction(named: "Set blue target") { session.input { $0.requestServe(0) } }
          .accessibilityAction(named: "Swing toward blue") {
            session.input { $0.swingServe(Vec(x: 0, y: 82), side: 0, tossID: $0.servePreparation?.tossID) }
          }
        if session.paused {
          Color.black.opacity(0.3)
          Button("Resume demo", systemImage: "play.fill") { session.resume() }
            .buttonStyle(.borderedProminent).controlSize(.large)
        } else if let result = run?.result {
          VStack {
            Spacer()
            VStack(spacing: 6) {
              Label(session.mastered ? "Skill mastered!" : result.message,
                systemImage: session.mastered || result.success ? "checkmark.circle.fill" : "arrow.clockwise")
                .font(.headline).multilineTextAlignment(.center)
              Text(session.mastered ? (demos.progress.next == nil ? "All skills mastered. Returning to your progress."
                : "Saved. Your next unfinished skill starts shortly.")
                : watching ? "Try the same moves yourself."
                : result.success ? "\(session.streak)/\(DemoMastery.target) clean attempts. \(session.lesson.isFootwork ? "Another rally" : "Another ball") is coming."
                : "Streak restarted. Try the same skill again.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(16).frame(maxWidth: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
              .padding(16).accessibilityElement(children: .combine)
          }.allowsHitTesting(false)
        }
      }
    }.background(TennisTheme.cream).navigationTitle(session.lesson.title).navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 12) {
          if !session.mastered {
            Button("Watch demo", systemImage: "eye") { session.begin(demonstration: true) }
              .buttonStyle(.bordered).accessibilityIdentifier("watchShotDemo")
          }
          if session.mastered {
            Button(demos.progress.next == nil ? "Finish demo" : "Next skill", systemImage: "arrow.right") { onNext() }
              .buttonStyle(.borderedProminent).accessibilityIdentifier("nextDemoLesson")
          } else if watching || run?.result != nil {
            Button(watching ? "Your turn" : "Try again", systemImage: "play.fill") { session.begin(demonstration: false) }
              .buttonStyle(.borderedProminent).accessibilityIdentifier("tryDemoShot")
          } else {
            Text("\(session.streak)/\(DemoMastery.target) in a row").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
          }
        }.controlSize(.large).frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 10).background(.bar)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
          Button(session.paused ? "Resume" : "Pause", systemImage: session.paused ? "play.fill" : "pause.fill") {
            if session.paused { session.resume() } else { session.pause() }
          }.labelStyle(.iconOnly)
        }
      }
      .onAppear {
        session.scene.reduceMotion = reduceMotion
        UIApplication.shared.isIdleTimerDisabled = true
      }
      .onDisappear { session.stop(); UIApplication.shared.isIdleTimerDisabled = false }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active { session.pause(); UIApplication.shared.isIdleTimerDisabled = false }
        else { UIApplication.shared.isIdleTimerDisabled = true }
      }
      .onChange(of: reduceMotion) { _, value in session.scene.reduceMotion = value }
      .task(id: session.mastered && !session.paused) {
        guard session.mastered, !session.paused else { return }
        do { try await Task.sleep(nanoseconds: 1_800_000_000) } catch { return }
        guard !Task.isCancelled else { return }
        onNext()
      }
      .sensoryFeedback(.success, trigger: session.mastered)
  }
  private func selectAccessibleShot() {
    session.input { engine in
      let opposite = engine.players[0].pos.x < PracticeEngine.width / 2 ? 1.0 : -1.0
      switch session.lesson.shot {
      case .cross: engine.selectShotSwipe(Vec(x: 40 * opposite, y: -40), side: 0)
      case .line: engine.selectShotSwipe(Vec(x: 0, y: -50), side: 0)
      case .angle: engine.selectShotSwipe(Vec(x: 50 * opposite, y: 0), side: 0)
      case .lob: engine.selectShotSwipe(Vec(x: 0, y: 50), side: 0)
      case .drop, .slice: engine.selectTouchShot(session.lesson.shot, side: 0, epoch: engine.shotGestureEpoch(0))
      }
    }
  }
}

private struct AcademyRecommendation: View {
  @AppStorage private var strength: String
  @AppStorage private var style: String
  let launch: (DemoLesson) -> Void
  init(owner: String, launch: @escaping (DemoLesson) -> Void) {
    _strength = AppStorage(wrappedValue:"Choose", "academy.strength."+owner)
    _style = AppStorage(wrappedValue:"Choose", "academy.style."+owner)
    self.launch = launch
  }
  private var drills: [DemoLesson] {
    let strengthDrill: DemoLesson
    switch strength {
    case "Serve": strengthDrill = .serveWide
    case "Return": strengthDrill = .secondReturn
    case "Split step": strengthDrill = .recoverySplit
    case "Backhand": strengthDrill = .downLine
    default: strengthDrill = .crosscourt
    }
    let styleDrill: DemoLesson = style == "Net play" ? .approachVolley : style == "Patient rallies" ? .rallyRecovery : .shortAngle
    return [strengthDrill,styleDrill]
  }
  var body: some View {
    Section("Practice for your game") {
      Picker("Strongest skill",selection:$strength) {
        ForEach(["Choose","Serve","Return","Split step","Forehand","Backhand"],id:\.self) { Text($0) }
      }
      Picker("Preferred style",selection:$style) {
        ForEach(["Choose","Net play","Patient rallies","Attacking baseline"],id:\.self) { Text($0) }
      }
      if strength != "Choose" && style != "Choose" {
        ForEach(drills) { drill in Button("Practice " + drill.title.lowercased()) { launch(drill) } }
      }
    }
  }
}
