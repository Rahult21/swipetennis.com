import SwiftUI

@main struct SwipeTennisApp: App {
  @StateObject private var store = AppStore()
  @StateObject private var coachAccount = CoachAccountStore()
  @StateObject private var demos = ShotDemoStore()
  @StateObject private var practiceSlot = PracticeMatchSlot()
  @StateObject private var cups = CupStore()
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).environmentObject(coachAccount).environmentObject(demos)
        .environmentObject(practiceSlot).environmentObject(cups)
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
struct HomeView: View {
  @EnvironmentObject var store: AppStore
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("Every point. A little more felt.").font(.title2.bold())
          Text("Read the ball. Find your rhythm. Make the court your own.")
            .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
          .listRowBackground(Color.clear)
      }
      Section {
        NavigationLink { PracticeSetupView() } label: {
          Label {
            VStack(alignment: .leading, spacing: 4) {
              Text("Play & practice").font(.headline)
              Text("Take the court with your opponent").font(.subheadline).foregroundStyle(.secondary)
            }
          } icon: { Image(systemName: "figure.tennis").foregroundStyle(TennisTheme.accent) }
          .padding(.vertical, 5)
        }.accessibilityIdentifier("playPractice")
      }
      Section {
        NavigationLink { CupHubView() } label: {
          Label {
            VStack(alignment: .leading, spacing: 4) {
              Text("Quick Cup").font(.headline)
              Text("Friends, four players, one trophy").font(.subheadline).foregroundStyle(.secondary)
            }
          } icon: { Image(systemName: "trophy.fill").foregroundStyle(TennisTheme.accent) }
          .padding(.vertical, 5)
        }.accessibilityIdentifier("quickCup")
      }
      Section("Learn & improve") {
        ShotDemoLink()
        CourtGuideCard()
        CoachRulesCard()
      }
      Section("Your progress") {
        CoachLeaderboardCard()
        NavigationLink { HistoryView() } label: {
          HStack {
            Label("Journal", systemImage: "book.closed")
            Spacer()
            Text("\(store.data.history.count)").foregroundStyle(.secondary)
          }
        }
      }
      Section {
        NavigationLink { MatchHub() } label: {
          Label("Score a match", systemImage: "list.number")
        }
      }
    }.listStyle(.insetGrouped).navigationTitle("SwipeTennis")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NavigationLink { CoachLeaderboardView() } label: {
            Image(systemName: "trophy")
          }.accessibilityLabel("Coachability leaderboard")
          NavigationLink { CoachAccountScreen() } label: {
            Image(systemName: "person.crop.circle")
          }.accessibilityLabel("Apple account")
        }
      }
  }
}
struct SettingsView: View {
  @AppStorage("haptics") var haptics = true
  @AppStorage("sound") var sound = true
  @AppStorage("courtVolume") var courtVolume = 0.3
  @AppStorage("voice") var voice = false
  @AppStorage("tilt") var tilt = false
  @AppStorage("guides") var guides = true
  @EnvironmentObject var store: AppStore
  var body: some View {
    Form {
      Section("Feel the game") {
        Toggle("Racket & bounce haptics", isOn: $haptics)
        Toggle("Tennis ball hits", isOn: $sound)
        LabeledContent("Hit volume", value: "\(Int((courtVolume * 10).rounded())) / 10")
        Slider(value: $courtVolume, in: 0...1, step: 0.1).accessibilityLabel("Hit volume")
        Text("A recorded tennis-ball impact for every shot. Starts at 3 / 10. Your device volume buttons also control loudness. Plays even in Silent Mode.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Spoken score announcements", isOn: $voice)
      }
      Section {
        Toggle("Tilt to move", isOn: $tilt).disabled(!Immersion.shared.motionAvailable)
        Toggle("Contact & recovery guides", isOn: $guides)
      } header: {
        Text("Controls")
      } footer: {
        Text(
          "Tilt is optional. Hold your phone comfortably when a rally starts to calibrate. Touch controls remain available. A connected controller uses its left stick to move and A/B/X/Y for crosscourt, line, angle, and lob."
        )
      }
      Section("Coachability account") {
        CoachAccountView()
      }
      Section("Player profile") {
        if let player = store.data.player {
          LabeledContent(
            player.name, value: player.utr.isEmpty ? "Default player" : "UTR \(player.utr)")
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
