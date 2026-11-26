import SwiftUI
import SpriteKit

private struct CupCourt: Identifiable {
  let cup: QuickCup
  let match: CupMatch
  let identity: CoachIdentity
  var id: String { cup.code + match.id }
}

struct CupHubView: View {
  @EnvironmentObject private var cups: CupStore
  @EnvironmentObject private var account: CoachAccountStore
  @EnvironmentObject private var store: AppStore
  @State private var title = "Quick Cup"
  @State private var name = ""
  @State private var invite = ""
  @State private var level: CupLevel = .medium
  @State private var surface: CourtSurface = .hard
  @State private var court: CupCourt?
  @State private var leaving = false
  @State private var showingCreate = false

  var body: some View {
    List {
      if let cup = cups.selected {
        cupDetail(cup)
      } else {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(TennisTheme.accent)
            Text("Four players. One trophy.").font(.title2.bold())
            Text("Invite your friends. AI opponents fill the open spots when you start. Win a semifinal and the final to take the cup.")
              .foregroundStyle(.secondary)
          }.padding(.vertical, 8)
        }.listRowBackground(Color.clear)
        if account.isSignedIn {
          Section {
            TextField("Your court name", text: $name).textContentType(.nickname)
              .onChange(of: name) { _, value in name = String(value.prefix(24)) }
          } header: { Text("Your player") } footer: { Text("Your court name is visible to the friends in your cup.") }
          Section {
            TextField("Invite code or link", text: $invite).textInputAutocapitalization(.characters)
              .autocorrectionDisabled().accessibilityIdentifier("cupInviteCode")
            Button("Join a friend's cup") {
              Task { await cups.join(account, text: invite, name: name) }
            }.disabled(cups.busy || QuickCup.inviteCode(from: invite) == nil)
              .accessibilityIdentifier("joinCup")
          } header: { Text("Got an invite?") }
          Section {
            DisclosureGroup("Create a four-player cup", isExpanded: $showingCreate) {
              TextField("Cup name", text: $title).onChange(of: title) { _, value in title = String(value.prefix(24)) }
              Picker("Playing level", selection: $level) {
                ForEach(CupLevel.allCases) { Text($0.title).tag($0) }
              }
              Picker("Surface", selection: $surface) {
                ForEach(CourtSurface.allCases, id: \.self) { Text($0.rawValue).tag($0) }
              }
              Text("Start with your usual practice level. Every AI player uses this level for the whole cup.")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("Create cup") {
                Task { await cups.create(account, title: title, name: name, level: level, surface: surface) }
              }.disabled(cups.busy).accessibilityIdentifier("createCup")
            }
          }
          if !cups.cups.isEmpty {
            Section("Your cups") {
              ForEach(cups.cups) { cup in
                Button { cups.selectedCode = cup.code } label: {
                  HStack {
                    Image(systemName: cup.status == "complete" ? "trophy.fill" : "tennisball")
                    VStack(alignment: .leading, spacing: 4) {
                      Text(cup.title).font(.headline)
                      Text("\(cup.level.title) · \(cup.status.capitalized)").font(.subheadline).foregroundStyle(.secondary)
                    }
                  }.padding(.vertical, 4)
                }
              }
            }
          }
        } else {
          Section {
            NavigationLink { CoachAccountScreen() } label: { Label("Sign in with Apple", systemImage: "person.crop.circle") }
          } footer: { Text("Sign in to create or join a cup. Your invite will stay here while you sign in.") }
          if !invite.isEmpty { Section("Your invite") { Text(invite).textSelection(.enabled) } }
        }
        Section {
          Text("First to seven points, win by two. Standard tennis, with no match powers. Cups have their own trophies and do not affect Coachability standings.")
          Text("Play together while the cup is open. Join or reconnect within 60 seconds of your opponent entering the court. Cups close after 24 hours.")
        }.font(.subheadline).foregroundStyle(.secondary)
      }
      if let error = cups.error {
        Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityIdentifier("cupError") }
      }
      if cups.busy { Section { ProgressView("Updating cup…") } }
    }
    .navigationTitle(cups.selected?.title ?? "Quick Cup")
    .listStyle(.insetGrouped)
    .toolbar {
      if cups.selected != nil {
        ToolbarItem(placement: .topBarTrailing) { Button("All cups") { cups.selectedCode = nil } }
      }
    }
    .onAppear {
      if name.isEmpty { name = store.data.player?.name ?? ApplePlayerName.display(account.identity?.emailMask) }
      level = CupLevel(store.data.practice.difficulty)
      if let code = cups.pendingInvite { invite = code; cups.selectedCode = nil }
    }
    .onChange(of: cups.pendingInvite) { _, code in if let code { invite = code; cups.selectedCode = nil } }
    .task(id: account.identity?.userID) {
      while !Task.isCancelled {
        if court == nil { await cups.refresh(account) }
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
      }
    }
    .refreshable { await cups.refresh(account) }
    .fullScreenCover(item: $court, onDismiss: { Task { await cups.refresh(account) } }) { context in
      CupMatchView(cup: context.cup, match: context.match, identity: context.identity, onCup: cups.update)
    }
    .confirmationDialog("Leave this cup?", isPresented: $leaving, titleVisibility: .visible) {
      if let cup = cups.selected {
        Button(cup.isLobby && cup.hostID == account.identity?.userID ? "Cancel cup" : "Leave cup", role: .destructive) {
          Task { await cups.action("leave", cup: cup, account: account) }
        }
      }
    } message: { Text("Leaving an active match gives your opponent the win. If you are hosting a lobby, leaving cancels the cup.") }
  }

  @ViewBuilder private func cupDetail(_ cup: QuickCup) -> some View {
    Section {
      HStack {
        Label(cup.level.title, systemImage: "figure.tennis")
        Spacer()
        Text("\(cup.surface.capitalized) court").foregroundStyle(.secondary)
      }
      Text("First to 7 · Win by 2 · No powers").font(.subheadline).foregroundStyle(.secondary)
    }
    if cup.isLobby {
      Section("Invite your friends") {
        LabeledContent("Cup code", value: cup.code).font(.headline).textSelection(.enabled)
        ShareLink(item: cup.inviteURL, subject: Text("Join my SwipeTennis cup"),
          message: Text("Four players, one trophy. Join \(cup.title) with code \(cup.code).")) {
          Label("Share invite", systemImage: "square.and.arrow.up")
        }.accessibilityIdentifier("shareCupInvite")
        Text("Friends open the link in SwipeTennis on iPhone or iPad, then tap Ready. You can also share the code.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Section("The draw · \(cup.participants.count)/4 players") {
        ForEach(cup.participants) { player in
          HStack {
            Label(player.name, systemImage: "person.fill")
            Spacer()
            Text(player.ready ? "Ready" : "Not ready").font(.subheadline)
              .foregroundStyle(player.ready ? TennisTheme.accent : .secondary)
          }
        }
        ForEach(0..<(4 - cup.participants.count), id: \.self) { _ in
          Label("Open spot · \(cup.level.title) AI at start", systemImage: "person.badge.plus")
            .foregroundStyle(.secondary)
        }
      }
      if let me = cup.player(account.identity?.userID) {
        Section {
          Button(me.ready ? "Mark me not ready" : "I'm ready") {
            Task { await cups.action("ready", cup: cup, account: account, ready: !me.ready) }
          }.disabled(cups.busy).accessibilityIdentifier("cupReady")
          if cup.hostID == me.id {
            Button("Start cup\(cup.participants.count < 4 ? " with \(4 - cup.participants.count) AI" : "")") {
              Task { await cups.action("start", cup: cup, account: account) }
            }.disabled(cups.busy || cup.participants.contains { !$0.ready })
              .font(.headline).accessibilityIdentifier("startCup")
          } else { Text("The host starts once everyone is ready.").foregroundStyle(.secondary) }
        } footer: { Text("Starting locks the draw. Open spots become clearly labeled AI players at \(cup.level.title.lowercased()) level.") }
      }
    } else {
      if let champion = cup.player(cup.championID) {
        Section {
          VStack(spacing: 8) {
            Image(systemName: "trophy.fill").font(.system(size: 42)).foregroundStyle(TennisTheme.accent)
            Text(champion.id == account.identity?.userID ? "You won the cup!" : "\(champion.name) wins the cup!")
              .font(.title2.bold()).multilineTextAlignment(.center)
            Text(champion.isBot ? "AI champion · Try another cup" : "Two rounds. One champion.").foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity).padding(.vertical, 12)
        }
      } else if ["expired", "cancelled"].contains(cup.status) {
        Section { Label("Cup \(cup.status)", systemImage: "clock.badge.xmark") }
      }
      Section("Semifinals") {
        ForEach(cup.matches.filter { $0.id != "final" }) { bracketMatch($0, cup: cup) }
      }
      Section("Final") {
        if let final = cup.matches.first(where: { $0.id == "final" }) { bracketMatch(final, cup: cup) }
        else { Text("The semifinal winners meet here.").foregroundStyle(.secondary) }
      }
      if let identity = account.identity, let next = cup.nextMatch(for: identity.userID) {
        Section {
          Button { court = CupCourt(cup: cup, match: next, identity: identity) } label: {
            Label("Play \(next.title.lowercased())", systemImage: "play.fill").font(.headline)
          }.accessibilityIdentifier("playCupMatch")
        } footer: { Text("Enter the court together. A missing player has 60 seconds to join or reconnect.") }
      } else if cup.status == "playing" {
        Section {
          Text(cup.matches.contains(where: { $0.complete && $0.playerIDs.contains(account.identity?.userID ?? "") && $0.winnerID != account.identity?.userID })
            ? "Your run ends here. Follow the draw to see who takes the trophy."
            : "Waiting for the other semifinal to finish. The draw updates automatically.")
            .foregroundStyle(.secondary)
        }
      }
    }
    if !cup.isClosed { Section { Button("Leave cup", role: .destructive) { leaving = true } } }
  }
  private func bracketMatch(_ match: CupMatch, cup: QuickCup) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(match.title).font(.subheadline).foregroundStyle(.secondary)
      ForEach(Array(match.playerIDs.enumerated()), id: \.element) { index, id in
        HStack {
          if let player = cup.player(id) {
            Image(systemName: player.isBot ? "cpu" : "person.fill").foregroundStyle(TennisTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
              Text(player.name).fontWeight(match.winnerID == id ? .bold : .regular)
              if player.isBot { Text("\(cup.level.title) AI · \(player.botStyle.rawValue)").font(.caption).foregroundStyle(.secondary) }
            }
          }
          Spacer()
          if match.winnerID == id { Image(systemName: "checkmark.circle.fill").foregroundStyle(TennisTheme.accent) }
          Text(match.score.indices.contains(index) ? "\(match.score[index])" : "–").monospacedDigit()
        }
      }
      if let reason = match.reason, reason != "played" {
        Text(reason == "simulated" ? "AI match simulated" : "Won by \(reason)").font(.caption).foregroundStyle(.secondary)
      } else if match.status == "live" { Text("On court").font(.caption).foregroundStyle(TennisTheme.accent) }
    }.padding(.vertical, 5)
  }
}

struct CupMatchView: View {
  @StateObject private var session: CupMatchSession
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var leaving = false
  let title: String
  init(cup: QuickCup, match: CupMatch, identity: CoachIdentity, onCup: @escaping (QuickCup) -> Void) {
    title = match.title
    _session = StateObject(wrappedValue: CupMatchSession(cup: cup, match: match, identity: identity, onCup: onCup))
  }
  private var game: PracticeEngine { session.game }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button { leaving = true } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Leave cup match")
        Spacer()
        VStack(spacing: 2) {
          Text(title).font(.headline)
          Text(session.connection).font(.caption)
        }
        Spacer()
        Image(systemName: "trophy").frame(width: 44, height: 44)
      }.foregroundStyle(.white).padding(.horizontal, 8)
      HStack {
        scorePlayer(session.side)
        Spacer()
        Text("First to 7").font(.caption).foregroundStyle(.white.opacity(0.75))
        Spacer()
        scorePlayer(1 - session.side)
      }.padding(.horizontal, 20).padding(.bottom, 10)
      ZStack {
        SpriteView(scene: session.scene, preferredFramesPerSecond: ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 120)
          .accessibilityLabel("Tournament court. \(game.scoreSummary)")
          .accessibilityAction(named: "Move to contact") { session.input(CupInput(kind: "receive")) }
          .accessibilityAction(named: "Recover") { session.input(CupInput(kind: "recover")) }
          .accessibilityAction(named: "Split step") { session.input(CupInput(kind: "split")) }
          .accessibilityAction(named: "Serve") { session.input(CupInput(kind: "serve")) }
          .accessibilityAction(named: "Crosscourt") { session.input(CupInput(kind: "shot", shot: .cross)) }
          .accessibilityAction(named: "Down the line") { session.input(CupInput(kind: "shot", shot: .line)) }
          .accessibilityAction(named: "Lob") { session.input(CupInput(kind: "shot", shot: .lob)) }
          .accessibilityAction(named: "Approach the net") { session.input(CupInput(kind: "approach")) }
        if let result = session.result {
          courtCard {
            Image(systemName: result.winnerID == gamePlayerID ? "trophy.fill" : "tennisball").font(.largeTitle)
            Text(result.winnerID == gamePlayerID ? "You win!" : "Match complete").font(.title2.bold())
            Text("\(result.score[0])–\(result.score[1])\(result.reason == "disconnect" ? " · Disconnection" : result.reason == "forfeit" ? " · Forfeit" : "")")
            Button("Return to draw") { dismiss() }.buttonStyle(.borderedProminent)
          }
        } else if !session.ready {
          courtCard {
            ProgressView().tint(TennisTheme.accent)
            Text(session.connection).font(.headline)
            if let deadline = session.reconnectDeadline {
              Text("Join or reconnect by \(deadline.formatted(date: .omitted, time: .standard)).")
            } else { Text("The rally starts when both players are connected.") }
            if session.error != nil { Button("Return to draw") { dismiss() }.buttonStyle(.bordered) }
          }
        } else if game.phase == .ready || game.showsPointResult {
          courtCard {
            Text(game.phase == .ready ? "Ready for the \(title.lowercased())?" : game.feedback.title).font(.title3.bold())
            if game.phase != .ready { Text(game.feedback.reason).font(.subheadline) }
            Text(game.phase == .ready ? "Tap yellow to receive, white to recover. Swipe from your player to choose a shot." : game.scoreSummary)
              .font(.subheadline).foregroundStyle(.secondary)
            Button(session.waitingForNext ? "Waiting for opponent…" : game.phase == .ready ? "I'm ready to play" : "Next point") { session.next() }
              .buttonStyle(.borderedProminent).disabled(session.waitingForNext || game.phase == .finished)
          }
        }
      }
      if let error = session.error { Text(error).font(.subheadline).foregroundStyle(.white).padding(10) }
      if game.phase == .serving && game.scoring.server == session.side && session.ready {
        HStack {
          Button("Serve") { session.input(CupInput(kind: "serve")) }.buttonStyle(.borderedProminent)
          if let serve = game.servePreparation, serve.canTune {
            Menu("Speed: \(serve.profile.speed.label)") {
              ForEach(ServeLevel.allCases, id: \.self) { value in Button(value.label) { session.input(CupInput(kind: "serveTune", speed: value)) } }
            }
            Menu("Spin: \(serve.profile.spin.label)") {
              ForEach(ServeLevel.allCases, id: \.self) { value in Button(value.label) { session.input(CupInput(kind: "serveTune", spin: value)) } }
            }
          } else { Text("Aim with blue, then serve.").font(.subheadline).foregroundStyle(.white) }
        }.padding(8)
      } else { Text("\(game.name(game.scoring.server)) serving · Win by two").font(.caption).foregroundStyle(.white).padding(8) }
    }
    .background(TennisTheme.green).tint(TennisTheme.accent)
    .onAppear { session.scene.reduceMotion = reduceMotion; session.connect(); UIApplication.shared.isIdleTimerDisabled = true }
    .onDisappear { session.close(); UIApplication.shared.isIdleTimerDisabled = false }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { session.resume(); UIApplication.shared.isIdleTimerDisabled = true }
      else { session.suspend(); UIApplication.shared.isIdleTimerDisabled = false }
    }
    .onChange(of: reduceMotion) { _, value in session.scene.reduceMotion = value }
    .confirmationDialog("Leave this match?", isPresented: $leaving, titleVisibility: .visible) {
      Button("Forfeit match", role: .destructive) { session.forfeit() }
      Button("Return to draw") { dismiss() }
    } message: { Text("Forfeiting gives your opponent the win. If you leave the court, you have 60 seconds to reconnect.") }
  }
  private var gamePlayerID: String? { session.result?.playerIDs[session.side] }
  private func scorePlayer(_ side: Int) -> some View {
    VStack(spacing: 4) {
      Text(game.name(side)).font(.subheadline).lineLimit(1)
      Text("\(game.scoring.points[side])").font(.title.bold()).monospacedDigit()
    }.foregroundStyle(.white).frame(maxWidth: .infinity)
  }
  private func courtCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 16, content: content).multilineTextAlignment(.center)
      .padding(24).frame(maxWidth: 340)
      .background(TennisTheme.cream, in: RoundedRectangle(cornerRadius: 22))
      .foregroundStyle(TennisTheme.ink).padding(20)
  }
}
