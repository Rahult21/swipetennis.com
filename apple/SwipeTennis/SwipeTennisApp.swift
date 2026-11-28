import SwiftUI

@main struct SwipeTennisApp: App {
  @StateObject private var store = AppStore()
  @StateObject private var coachAccount = CoachAccountStore()
  @StateObject private var demos = ShotDemoStore()
  @StateObject private var career = SoloCareerStore()
  @StateObject private var practiceSlot = PracticeMatchSlot()
  @StateObject private var cups = CupStore()
  init() { CourtVisualAids.register() }
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).environmentObject(coachAccount).environmentObject(demos)
        .environmentObject(practiceSlot).environmentObject(cups).environmentObject(career)
        .onChange(of: coachAccount.identity?.userID, initial: true) { _, id in demos.activate(userID: id) }
        .onChange(of: coachAccount.identity?.userID, initial: true) { _, id in cups.reset(owner: id) }
        .onOpenURL { url in
          if let code = QuickCup.inviteCode(from: url.absoluteString) { cups.pendingInvite = code }
          else if url.scheme == "swipetennis" && url.host == "cups" { cups.pendingInvite = "" }
        }
        .task { await coachAccount.restore() }.tint(TennisTheme.accent)
    }
  }
}
struct RootView: View {
  @State private var dismissedStorageError = false
  @EnvironmentObject var store: AppStore
  @EnvironmentObject private var cups: CupStore
  var body: some View {
    TabView {
      NavigationStack { HomeView() }.tabItem { Label("Court", systemImage: "tennisball") }
      NavigationStack { MatchHub() }.tabItem { Label("Score", systemImage: "list.number") }
      NavigationStack { HistoryView() }.tabItem { Label("Journal", systemImage: "book.closed") }
      NavigationStack { SettingsView() }.tabItem {
        Label("Settings", systemImage: "gearshape")
      }
    }
    .sheet(isPresented: Binding(get: { cups.pendingInvite != nil }, set: { if !$0 { cups.pendingInvite = nil } })) {
      NavigationStack {
        CupHubView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { cups.pendingInvite = nil } } }
      }
    }
    .alert(
      "Saved data needs attention",
      isPresented: Binding(
        get: { store.storageError != nil && !dismissedStorageError },
        set: { if !$0 { dismissedStorageError = true } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(store.storageError ?? "")
    }
  }
}
struct SettingsView: View {
  @AppStorage("haptics") var haptics = true
  @AppStorage("sound") var sound = true
  @AppStorage("courtVolume") var courtVolume = 0.3
  @AppStorage("voice") var voice = false
  @AppStorage("tilt") var tilt = false
  @AppStorage(CourtVisualAids.yellowKey) private var showHittingZone = true
  @AppStorage(CourtVisualAids.whiteKey) private var showRecovery = true
  @AppStorage(CourtVisualAids.blueKey) private var showServePosition = true
  @AppStorage("matchViewpoint") private var matchViewpoint = MatchViewpoint.baseline.rawValue
  @EnvironmentObject var store: AppStore
  var body: some View {
    Form {
      Section("Feel the game") {
        Toggle("Racket & bounce haptics", isOn: $haptics)
        Toggle("Court sounds", isOn: $sound)
        LabeledContent("Court volume", value: "\(Int((courtVolume * 10).rounded())) / 10")
        Slider(value: $courtVolume, in: 0...1, step: 0.1).accessibilityLabel("Court volume")
        Text("Racket contact during play, applause after each point, and a standing ovation at the handshake. Starts at 3 / 10. Your device volume buttons also control loudness.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Spoken scores for manual scoring", isOn: $voice)
      }
      Section {
        Toggle("Tilt to move", isOn: $tilt).disabled(!Immersion.shared.motionAvailable)
        Toggle("Yellow hitting zone", isOn: $showHittingZone)
        Toggle("White recovery position", isOn: $showRecovery)
        Toggle("Blue serve position", isOn: $showServePosition)
        Picker("Match camera",selection:$matchViewpoint) {
          ForEach(MatchViewpoint.allCases,id:\.self) { Text($0.rawValue).tag($0.rawValue) }
        }.accessibilityIdentifier("matchViewpoint")
      } header: {
        Text("Controls")
      } footer: {
        Text(
          "Hiding a guide keeps automatic footwork and touch controls active. Tilt is optional. Hold your phone comfortably when a rally starts to calibrate. Touch controls remain available. A connected controller uses its left stick to move and A/B/X/Y for crosscourt, line, angle, and lob."
        )
      }
      Section("Coachability account") {
        CoachAccountView()
      }
      Section("Player profile") {
        if let player = store.data.player {
          LabeledContent(
            player.name, value: "Default player")
          Button("Clear default player") {
            store.data.player = nil
            store.save()
          }
        } else {
          Text("Save a default player when setting up a match.").foregroundStyle(.secondary)
        }
      }
      Section("Made for the court") {
        Text(
          "Matches and reports are saved on this device. Sign in with Apple for practice and Coachability records. Completed results queue on this device if you go offline, then sync when you reconnect."
        )
        Text(
          "Reduce Motion and VoiceOver are respected. Hardware feedback is available on supported devices."
        )
      }
    }.navigationTitle("Settings")
  }
}
