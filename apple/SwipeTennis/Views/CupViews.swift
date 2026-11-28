import SwiftUI
import SpriteKit
import Charts

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
  @State private var size = 4
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
            Text("Play a tournament").font(.title2.bold())
            Text("Invite your friends. AI opponents fill the open spots when you start. Advance through the draw to take the cup.")
              .foregroundStyle(.secondary)
          }.padding(.vertical, 8)
        }.listRowBackground(Color.clear)
        if account.isSignedIn {
          Section {
            TextField("Your court name", text: $name).textContentType(.nickname)
              .onChange(of: name) { _, value in name = String(value.prefix(24)) }
            Label("Player emblem",systemImage:UserDefaults.standard.string(forKey:"tour.emblem." + (account.identity?.userID ?? "guest")) ?? "tennisball.fill").labelStyle(.iconOnly)
            STRankingSummary(rating: account.identity?.stRating ?? STRating())
          } header: { Text("Your player") } footer: { Text("Your court name is visible to the friends in your cup.") }
          Section {
            TextField("Invite code or link", text: $invite).textInputAutocapitalization(.characters)
              .autocorrectionDisabled().accessibilityIdentifier("cupInviteCode")
            Button("Join a friend's cup") {
              Task { await cups.join(account, text: invite, name: name) }
            }.disabled(cups.busy || QuickCup.inviteCode(from: invite) == nil)
              .accessibilityIdentifier("joinCup")
          } header: { Text("Got an invite?") }
          Section("Tour") {
            Button("Find an ST opponent") { Task { await cups.find(account,weekly:false,name:name) } }
            Button("Enter this week’s Open") { Task { await cups.find(account,weekly:true,name:name) } }
            NavigationLink("Career, trophies and club") { TourCareerView() }
          }.disabled(cups.busy)
          Section {
            DisclosureGroup("Create a cup", isExpanded: $showingCreate) {
              TextField("Cup name", text: $title).onChange(of: title) { _, value in title = String(value.prefix(24)) }
              Picker("Draw size", selection: $size) { Text("4 players").tag(4); Text("8 players").tag(8) }
              Picker("Surface", selection: $surface) {
                ForEach(CourtSurface.allCases, id: \.self) { Text($0.rawValue).tag($0) }
              }
              Text("AI opponents play near the entrants’ ST ratings.")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("Create cup") {
                Task { await cups.create(account, title: title, name: name, level: level, surface: surface, size: size) }
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
                      Text("\(cup.division ?? cup.level.title) · \(cup.status.capitalized)").font(.subheadline).foregroundStyle(.secondary)
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
          Text("Human matches update ST ranking. AI matches never change ST. Yellow appears from the incoming ball's path after your human opponent makes contact; swipe toward it to receive, and toward white to recover.")
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
      await account.refreshRanking()
      while !Task.isCancelled {
        if court == nil { await cups.refresh(account) }
        do { try await Task.sleep(for: .seconds(3)) } catch { return }
      }
    }
    .refreshable { await cups.refresh(account) }
    .fullScreenCover(item: $court, onDismiss: { Task { await cups.refresh(account); await account.refreshRanking() } }) { context in
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
        Label(cup.division ?? cup.level.title, systemImage: "figure.tennis")
        Spacer()
        Text("\(cup.surface.capitalized) court").foregroundStyle(.secondary)
      }
      Text("First to 7 · Win by 2 · No powers").font(.subheadline).foregroundStyle(.secondary)
    }
    if cup.isLobby {
      Section("Invite your friends") {
        LabeledContent("Cup code", value: cup.code).font(.headline).textSelection(.enabled)
        ShareLink(item: cup.inviteURL, subject: Text("Join my SwipeTennis cup"),
          message: Text("Join \(cup.title) with code \(cup.code).")) {
          Label("Share invite", systemImage: "square.and.arrow.up")
        }.accessibilityIdentifier("shareCupInvite")
        Text("Friends open the link in SwipeTennis on iPhone or iPad, then tap Ready. You can also share the code.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Section("The draw · \(cup.participants.count)/\(cup.capacity) players") {
        ForEach(cup.participants) { player in
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Label(player.name, systemImage: "person.fill")
              Text((player.stRating ?? STRating()).label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(player.ready ? "Ready" : "Not ready").font(.subheadline)
              .foregroundStyle(player.ready ? TennisTheme.accent : .secondary)
          }
        }
        ForEach(0..<max(0,cup.capacity - cup.participants.count), id: \.self) { _ in
          Label("Open spot", systemImage: "person.badge.plus")
            .foregroundStyle(.secondary)
        }
      }
      if let me = cup.player(account.identity?.userID) {
        Section {
          Button(me.ready ? "Mark me not ready" : "I'm ready") {
            Task { await cups.action("ready", cup: cup, account: account, ready: !me.ready) }
          }.disabled(cups.busy).accessibilityIdentifier("cupReady")
          if cup.capacity == 2 { Text("Waiting for your opponent until " + Date(timeIntervalSince1970:cup.expiresAt/1000).formatted(date:.omitted,time:.shortened) + ".") } else if cup.hostID == me.id {
            Button("Start cup\(cup.participants.count < cup.capacity ? " with \(cup.capacity - cup.participants.count) AI" : "")") {
              Task { await cups.action("start", cup: cup, account: account) }
            }.disabled(cups.busy || cup.participants.contains { !$0.ready })
              .font(.headline).accessibilityIdentifier("startCup")
          } else { Text("The host starts once everyone is ready.").foregroundStyle(.secondary) }
        } footer: { Text("The draw locks when play starts.") }
      }
    } else {
      if let champion = cup.player(cup.championID) {
        Section {
          VStack(spacing: 8) {
            Image(systemName: "trophy.fill").font(.system(size: 42)).foregroundStyle(TennisTheme.accent)
            Text(champion.id == account.identity?.userID ? "You won the cup!" : "\(champion.name) wins the cup!")
              .font(.title2.bold()).multilineTextAlignment(.center)
            Text(champion.isBot ? "AI champion · Try another cup" : "Cup champion").foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity).padding(.vertical, 12)
        }
      } else if ["expired", "cancelled"].contains(cup.status) {
        Section { Label("Cup \(cup.status)", systemImage: "clock.badge.xmark") }
      }
      ForEach(["quarter-", "semi-"], id: \.self) { prefix in
        let round = cup.matches.filter { $0.id.hasPrefix(prefix) }
        if !round.isEmpty {
          Section(prefix == "quarter-" ? "Quarterfinals" : "Semifinals") { ForEach(round) { bracketMatch($0, cup: cup) } }
        }
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
              if player.isBot { Text("\(player.botST.map { "ST " + $0.formatted() } ?? cup.level.title) AI · \(player.botStyle.rawValue)").font(.caption).foregroundStyle(.secondary) }
              else {
                Text(match.ratingChanges?.first(where: { $0.userID == id })?.summary ?? (player.stRating ?? STRating()).label)
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          Spacer()
          if match.winnerID == id { Image(systemName: "checkmark.circle.fill").foregroundStyle(TennisTheme.accent) }
          Text(match.score.indices.contains(index) ? "\(match.score[index])" : "–").monospacedDigit()
        }
      }
      if match.complete, match.playerIDs.contains(account.identity?.userID ?? ""), match.playerIDs.allSatisfy({ cup.player($0)?.isBot == false }) {
        Button(match.rematchRequestedBy.map { $0 == account.identity?.userID ? "Open rematch" : "Accept rematch" } ?? "Rematch") { Task { await cups.rematch(account,cup:cup,match:match) } }.disabled(cups.busy)
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
  @State private var showCourtMenu = false
  @State private var leaving = false
  @State private var review: ReplayReview?
  @State private var shownHighlight: UUID?
  @State private var pendingHighlight: UUID?
  private var highlightFinished: Bool { shownHighlight == game.feedback.id || !session.scene.performance.replay.canPlay }
  let title: String
  init(cup: QuickCup, match: CupMatch, identity: CoachIdentity, onCup: @escaping (QuickCup) -> Void) {
    title = match.title
    _session = StateObject(wrappedValue: CupMatchSession(cup: cup, match: match, identity: identity, onCup: onCup))
  }
  private var game: PracticeEngine { session.game }
  var body: some View {
    ZStack {
      LiveCourt(scene: session.scene, paused: showCourtMenu && !game.settings.local, reviewing:review != nil).ignoresSafeArea()
        .accessibilityLabel("Tournament court. \(game.scoreSummary)")
        .accessibilityAction(named: "Move to contact") { session.input(CupInput(kind: "receive")) }
        .accessibilityAction(named: "Recover") { session.input(CupInput(kind: "recover")) }
        .accessibilityAction(named: "Split step") { session.input(CupInput(kind: "split")) }
        .accessibilityAction(named: "Serve") { session.input(CupInput(kind: "serve")) }
        .accessibilityAction(named: "Crosscourt") { session.input(CupInput(kind: "shot", shot: .cross)) }
        .accessibilityAction(named: "Down the line") { session.input(CupInput(kind: "shot", shot: .line)) }
        .accessibilityAction(named: "Lob") { session.input(CupInput(kind: "shot", shot: .lob)) }
        .accessibilityAction(named: "Approach the net") { session.input(CupInput(kind: "approach")) }
      if review == nil {
        if let result = session.result, highlightFinished {
          courtCard {
            Image(systemName: result.winnerID == gamePlayerID ? "trophy.fill" : "tennisball").font(.largeTitle)
            Text(result.winnerID == gamePlayerID ? "You win!" : "Match complete").font(.title2.bold())
            Text("\(result.score[session.side])–\(result.score[1 - session.side])\(result.reason == "disconnect" ? " · Disconnection" : result.reason == "forfeit" ? " · Forfeit" : "")")
            if let change = result.ratingChanges?.first(where: { $0.userID == gamePlayerID }) {
              Text(change.summary).font(.headline)
            } else if !game.settings.local { Text("AI match · ST unchanged").font(.subheadline) }
            replayButton
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
        } else if game.phase == .ready || (game.showsPointResult && highlightFinished) {
          courtCard {
            Text(game.phase == .ready ? "Ready for the \(title.lowercased())?" : game.feedback.title).font(.title3.bold())
            if game.phase != .ready { Text(game.feedback.reason).font(.subheadline) }
            Text(game.phase == .ready ? "Swipe toward yellow to receive and white to recover. A short swipe starts the run; use a fresh swipe from your moving player to choose a shot." : game.scoreSummary)
              .font(.subheadline).foregroundStyle(.secondary)
            if game.phase == .point && game.showsPointResult { replayButton }
            Button(session.waitingForNext ? "Waiting for opponent…" : game.phase == .ready ? "I'm ready to play" : "Next point") { session.next() }
              .buttonStyle(.borderedProminent).disabled(session.waitingForNext || game.phase == .finished)
          }
        }
        if session.ready && session.result == nil && !showCourtMenu,
           game.phase == .serving && game.scoring.server == session.side, let serve = game.servePreparation, serve.canTune {
          HStack {
            ServeGauge(title: "Speed", level: serve.profile.speed, tint: TennisTheme.lime, editable: true) {
              session.input(CupInput(kind: "serveTune", speed: $0))
            }.frame(maxWidth: 130)
            Spacer(minLength: 40)
            ServeGauge(title: "Spin", level: serve.profile.spin, tint: .mint, editable: true) {
              session.input(CupInput(kind: "serveTune", spin: $0))
            }.frame(maxWidth: 130)
          }.padding(.horizontal, 12).frame(maxHeight: .infinity, alignment: .bottom)
        }
        if !showCourtMenu && session.result == nil {
          Button { showCourtMenu = true } label: { CourtControlIcon(symbol: game.settings.local ? "ellipsis" : "pause.fill") }
            .buttonStyle(.plain).accessibilityLabel(game.settings.local ? "Cup match menu" : "Pause cup match")
            .padding(.top, 2).padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        if showCourtMenu {
          Color.black.opacity(0.32).ignoresSafeArea().onTapGesture { showCourtMenu = false }
          courtCard {
            Text(title).font(.headline)
            Text(game.scoreSummary).font(.title3.bold()).monospacedDigit()
            Text(game.settings.local ? "Live match · " + session.connection : "Match paused").font(.caption)
            Button(game.settings.local ? "Return to court" : "Resume match") { showCourtMenu = false }
              .buttonStyle(.borderedProminent)
            Button("Leave cup match") { leaving = true }
          }.accessibilityAddTraits(.isModal)
        }
        if let error = session.error, session.ready {
          Text(error).font(.caption).padding(8).background(.regularMaterial, in: Capsule())
            .frame(maxHeight: .infinity, alignment: .bottom).allowsHitTesting(false)
        }
      }
    }.statusBarHidden(true)
    .onChange(of: showCourtMenu) { _, _ in session.scene.resetClock() }
    .onChange(of: session.result?.id) { _, result in if result != nil { showCourtMenu = false } }
    .accessibilityHidden(review != nil)
    .onChange(of:game.showsPointResult, initial:true) { _, visible in
      if visible && shownHighlight != game.feedback.id && review == nil && session.scene.performance.replay.canPlay {
        pendingHighlight = game.feedback.id
        review = ReplayReview(clip:session.scene.performance.replay,game:game,side:session.side,automatic:true,stadium:session.scene.stadium)
      }
    }
    .overlay {
      if let active = review {
        PointReplayView(review:active) {
          session.scene.returnFromReplay()
          if let pendingHighlight { shownHighlight = pendingHighlight; self.pendingHighlight = nil }
          review = nil
        }.id(active.id)
      }
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
  @ViewBuilder private var replayButton: some View {
    if !session.waitingForNext && session.scene.performance.replay.canPlay {
      Button("Replay point") {
        review = ReplayReview(clip:session.scene.performance.replay,game:game,side:session.side,stadium:session.scene.stadium)
      }.accessibilityIdentifier("replayCupPoint")
    }
  }
  private var gamePlayerID: String? { session.result?.playerIDs[session.side] }
  private func courtCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 16, content: content).multilineTextAlignment(.center)
      .padding(24).frame(maxWidth: 340)
      .background(TennisTheme.cream, in: RoundedRectangle(cornerRadius: 22))
      .foregroundStyle(TennisTheme.ink).padding(20)
  }
}

private struct TourCareer: Decodable {
  struct Trophy: Decodable { let code, title, division: String; let size: Int; let wonAt: Double }
  struct Rival: Decodable, Identifiable { let id, name: String; let wins, losses: Int }
  struct Sample: Decodable { let time, rating: Double }
  struct Member: Decodable, Identifiable { let id, name: String; let rating: Double }
  struct Club: Decodable { let code, name: String }
  struct Summary: Decodable { let matches, activeDays, seasonMatches, seasonWins: Int }
  let trophies: [Trophy], rivals: [Rival], trend: [Sample], ladder: [Member]
  let summary: Summary, club: Club?, season: String
}

private struct TourCareerView: View {
  @EnvironmentObject private var account: CoachAccountStore
  @State private var career: TourCareer?
  @State private var clubName = ""
  @State private var invite = ""
  @State private var error = ""
  @State private var busy = false
  @State private var emblem = "tennisball.fill"
  private var preference: String { "tour.emblem." + (account.identity?.userID ?? "guest") }
  var body: some View {
    List {
      if let c = career {
        Section(c.season) {
          Label("Season record  \(c.summary.seasonWins)–\(c.summary.seasonMatches - c.summary.seasonWins)", systemImage:emblem)
          Text("\(c.summary.matches) career human matches on \(c.summary.activeDays) match days")
          Picker("Player emblem",selection:$emblem) {
            Label("Tennis ball",systemImage:"tennisball.fill").tag("tennisball.fill")
            if c.summary.matches >= 3 { Label("Established",systemImage:"star.fill").tag("star.fill") }
            if !c.trophies.isEmpty { Label("Cup winner",systemImage:"trophy.fill").tag("trophy.fill") }
          }.onChange(of:emblem) { _, value in UserDefaults.standard.set(value,forKey:preference) }
          Text("Earn the star after three human matches and the trophy emblem with your first cup.").font(.caption)
        }
        Section("Recent ST results") {
          if c.trend.count >= 2 {
            Chart(Array(c.trend.enumerated()),id:\.offset) { i, sample in
              LineMark(x:.value("Match",i+1),y:.value("ST",sample.rating))
                .symbol(.circle)
            }.chartYScale(domain:1...10).frame(height:140).accessibilityLabel("ST over the last \(c.trend.count) ranked matches")
          }
          if c.trend.isEmpty { Text("Complete a human match to see your first result.") }
          ForEach(Array(c.trend.suffix(10).reversed().enumerated()),id:\.offset) { _, sample in
            LabeledContent(Date(timeIntervalSince1970:sample.time/1000).formatted(date:.abbreviated,time:.shortened),value:"ST " + sample.rating.formatted())
          }
        }
        Section("Head to head") {
          if c.rivals.isEmpty { Text("Your human opponents appear here after a ranked match.") }
          ForEach(c.rivals) { rival in LabeledContent(rival.name,value:"\(rival.wins) W · \(rival.losses) L") }
        }
        Section("Trophy cabinet") {
          if c.trophies.isEmpty { Text("Win a cup to add your first trophy.") }
          ForEach(c.trophies,id:\.code) { trophy in
            Label { VStack(alignment:.leading) {
              Text(trophy.title)
              Text("\(trophy.division) · \(trophy.size) players · " + Date(timeIntervalSince1970:trophy.wonAt/1000).formatted(date:.abbreviated,time:.omitted)).font(.caption)
            } } icon: { Image(systemName:"trophy.fill").foregroundStyle(.orange) }
          }
        }
        if let club = c.club {
          Section(club.name + " · ST ladder") {
            ShareLink(item:"Join my SwipeTennis club with code " + club.code)
            Text(club.code).textSelection(.enabled)
            ForEach(Array(c.ladder.enumerated()),id:\.element.id) { i, member in LabeledContent("\(i+1). " + member.name,value:"ST " + member.rating.formatted()) }
            Button("Leave club",role:.destructive) { changeClub(["action":"leave"]) }
          }
        } else {
          Section("Clubs") {
            TextField("Club name",text:$clubName)
            Button("Create club") { changeClub(["action":"create","name":clubName]) }.disabled(clubName.trimmingCharacters(in:.whitespaces).isEmpty)
            TextField("Club invite code",text:$invite).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button("Join club") { changeClub(["action":"join","code":invite]) }.disabled(QuickCup.inviteCode(from:invite) == nil)
          }
        }
      } else if error.isEmpty { ProgressView() }
      if !error.isEmpty { Text(error); Button("Refresh") { Task { await reload() } } }
    }.disabled(busy).navigationTitle("Tour career").task(id:account.identity?.userID) {
      career = nil; emblem = UserDefaults.standard.string(forKey:preference) ?? "tennisball.fill"
      await reload()
    }.refreshable { await reload() }
  }
  private func reload() async {
    let owner = account.identity?.userID
    do {
      let value: TourCareer = try await account.request("career",authenticated:true)
      guard account.identity?.userID == owner else { return }
      career = value; error = ""
    } catch { self.error = error.localizedDescription }
  }
  private func changeClub(_ payload: [String:String]) {
    guard !busy else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        let _: [String:Bool] = try await account.request("club",method:"POST",body:JSONEncoder().encode(payload),authenticated:true)
        await reload()
      } catch { self.error = error.localizedDescription }
    }
  }
}
