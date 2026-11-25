import Combine
import SwiftUI

struct MatchHub: View {
  @EnvironmentObject var store: AppStore
  var body: some View {
    Group {
      if let match = store.data.match { LiveMatchView(match: match) } else { MatchSetupView() }
    }
    .navigationTitle("Score a match")
  }
}
struct MatchSetupView: View {
  @EnvironmentObject var store: AppStore
  @State private var name1 = ""
  @State private var name2 = ""
  @State private var utr1 = ""
  @State private var utr2 = ""
  @State private var mode: ScoringMode = .swipe
  @State private var bestOfThree = true
  @State private var useSetTiebreak = false
  @State private var useDefault = true
  @State private var games = 6
  @State private var server = 0
  var body: some View {
    Form {
      Section {
        Label("New match", systemImage: "tennisball").font(.headline)
        Text("Capture the match with a tap, or trace the rally directly on the court.").font(
          .subheadline
        ).foregroundStyle(.secondary)
        Picker("Scoring mode", selection: $mode) {
          ForEach(ScoringMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented)
      }
      Section("You") {
        TextField("Your name (optional)", text: $name1).textContentType(.name).accessibilityIdentifier(
          "playerOne")
        TextField("UTR (optional)", text: $utr1).keyboardType(.decimalPad)
        Toggle("Make my default player", isOn: $useDefault)
      }
      Section("Opponent") {
        TextField("Opponent name (optional)", text: $name2).textContentType(.name).accessibilityIdentifier(
          "playerTwo")
        TextField("UTR (optional)", text: $utr2).keyboardType(.decimalPad)
      }
      Section("Match format") {
        Picker("Sets", selection: $bestOfThree) {
          Text("Best of 3 sets").tag(true)
          Text("2 sets + match tiebreak").tag(false)
        }
        Picker("Games per set", selection: $games) {
          Text("4").tag(4)
          Text("6").tag(6)
        }
        Toggle("Tiebreak at \(games)–\(games)", isOn: $useSetTiebreak)
        Picker("First server", selection: $server) {
          Text(displayName(name1, fallback: "You")).tag(0)
          Text(displayName(name2, fallback: "Opponent")).tag(1)
        }
      }
      Section {
        Button("Start match") {
          let players = [
            TennisPlayer(name: displayName(name1, fallback: "You"), utr: utr1),
            TennisPlayer(name: displayName(name2, fallback: "Opponent"), utr: utr2),
          ]
          if useDefault { store.data.player = players[0] }
          store.update(
            TennisMatch(
              players: players, mode: mode, bestOfThree: bestOfThree, gamesPerSet: games,
              useSetTiebreak: useSetTiebreak,
              firstServer: server, server: server))
        }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("startMatch")
      }.listRowBackground(Color.clear)
    }.formStyle(.grouped)
      .onAppear {
        if let p = store.data.player {
          name1 = p.name
          utr1 = p.utr
        }
      }
  }
  private func displayName(_ text: String, fallback: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }
}
struct Scoreboard: View {
  var match: TennisMatch
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(match.score).font(.subheadline).foregroundStyle(.secondary)
      Grid(horizontalSpacing: 16, verticalSpacing: 12) {
        GridRow {
          Text("Player").frame(maxWidth: .infinity, alignment: .leading)
          Text("Games")
          Text("Points")
        }.font(.caption).foregroundStyle(.secondary)
        ForEach(0..<2) { p in
          GridRow {
            HStack(spacing: 8) {
              Image(systemName: match.server == p ? "tennisball.fill" : "circle")
                .font(.caption).foregroundStyle(match.server == p ? TennisTheme.accent : Color.secondary.opacity(0.4))
                .accessibilityLabel(match.server == p ? "Serving" : "Receiving")
              VStack(alignment: .leading, spacing: 2) {
                Text(match.players[p].name).font(.headline)
                if !match.players[p].utr.isEmpty { Text("UTR \(match.players[p].utr)").font(.caption).foregroundStyle(.secondary) }
              }
              Spacer(minLength: 0)
            }
            Text("\(match.games[p])").font(.title3.monospacedDigit())
            Text(match.pointLabel(p)).font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
          }.accessibilityElement(children: .combine)
        }
      }
      Text(match.situation).font(.subheadline).foregroundStyle(TennisTheme.accent)
        .accessibilityIdentifier("scoreSituation")
    }.padding(.vertical, 6)
  }
}
struct LiveMatchView: View {
  @EnvironmentObject var store: AppStore
  var match: TennisMatch
  @State private var position: ShotPosition = .baseline
  @State private var showReplay = false
  @State private var showReport = false
  @State private var showEnd = false
  var body: some View {
    List {
      Section { Scoreboard(match: match) }
      if match.winner == nil {
        Section {
          Picker("Scoring mode", selection: Binding(get: { match.mode }, set: { mode in store.edit { $0.mode = mode } })) {
            ForEach(ScoringMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }.pickerStyle(.segmented)
        }
        Section(match.mode == .swipe ? "Trace the rally" : "Record a point") {
          if match.mode == .swipe { TraceScorer(match: match) } else { manual }
        }
      } else {
        Section { Label("Match complete", systemImage: "checkmark.circle.fill").font(.headline) }
      }
      Section {
        DisclosureGroup("Point journal · \(match.log.count)") {
          ForEach(Array(match.log.reversed())) { entry in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(match.players[entry.winner].name).fontWeight(.semibold)
                Spacer()
                Text(entry.outcome)
              }
              Text("\(entry.position.rawValue) · Serve \(entry.serve) \(entry.event)")
                .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
          }
        }
      }
      Section {
        Button(match.winner == nil ? "End this match" : "Start another match",
          role: match.winner == nil ? .destructive : nil) { showEnd = true }
      }
    }.listStyle(.insetGrouped)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Undo", systemImage: "arrow.uturn.backward") { store.edit { $0.undo() } }
            .disabled(match.log.isEmpty && match.serveAttempt == 1)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu("Match actions", systemImage: "ellipsis") {
            Button("Replay", systemImage: "play.fill") { showReplay = true }.disabled(match.log.isEmpty)
            Button("Report", systemImage: "chart.bar.xaxis") { showReport = true }
          }
        }
      }
      .sheet(isPresented: $showReplay) { NavigationStack { ReplayView(match: match, presented: true) } }
      .sheet(isPresented: $showReport) { NavigationStack { ReportView(match: match, presented: true) } }
      .confirmationDialog(
        "\(match.winner == nil ? "End this match? Unfinished scores will be saved in your journal.":"Ready for another match?")",
        isPresented: $showEnd, titleVisibility: .visible
      ) {
        Button("Save & close match") {
          store.data.history.removeAll { $0.id == match.id }
          store.data.history.insert(match, at: 0)
          store.data.match = nil
          store.save()
        }
      }
      .onChange(of: match.log.count) { _, _ in
        Immersion.shared.point("\(match.pointLabel(0)), \(match.pointLabel(1)). \(match.situation)")
      }
  }
  private var manual: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker("Winner’s position", selection: $position) {
        ForEach(ShotPosition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      ForEach([match.server, 1 - match.server], id: \.self) { p in
        VStack(alignment: .leading, spacing: 12) {
          Eyebrow(text: "\(p == match.server ? "Server":"Returner") · \(match.players[p].name)")
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            if p == match.server {
              scoreButton("Ace", winner: p, outcome: "Ace")
              Button(match.serveAttempt == 1 ? "First fault" : "Double fault") {
                store.edit { $0.fault() }
              }.buttonStyle(.bordered).accessibilityIdentifier("serveFault")
            } else {
              scoreButton("Return error", winner: 1 - p, outcome: "Return error")
            }
            scoreButton(
              "Winner", winner: p, outcome: p == match.server ? "Winner" : "Return winner")
            scoreButton(
              "Unforced error", winner: 1 - p, outcome: "\(match.players[p].name) unforced error")
            scoreButton(
              "Forced error", winner: 1 - p, outcome: "\(match.players[p].name) forced error")
          }.controlSize(.large).font(.subheadline)
        }
      }
    }
  }
  private func scoreButton(_ title: String, winner: Int, outcome: String) -> some View {
    Button(title) { store.edit { $0.record(winner: winner, outcome: outcome, position: position) } }
      .buttonStyle(.bordered).frame(maxWidth: .infinity)
  }
}
struct PendingPoint: Identifiable {
  var id = UUID()
  var winner: Int
  var outcome: String
  var serve: Int
  var position: ShotPosition
  var path: [CourtPoint]
  var landings: [CourtPoint]
}
struct TraceScorer: View {
  @EnvironmentObject var store: AppStore
  var match: TennisMatch
  @State private var path: [CourtPoint] = []
  @State private var landings: [CourtPoint] = []
  @State private var drawing = false
  @State private var help = false
  @State private var lastMove = Date()
  @State private var captured = false
  @State private var message = "Start at the bottom baseline. Pause at each bounce. Lift to finish."
  @State private var pending: PendingPoint?
  private let clock = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Trace a rally").font(.headline)
        Spacer()
        Button {
          help = true
        } label: {
          Image(systemName: "questionmark.circle")
        }.accessibilityLabel("How to trace a rally")
      }
      Text(message).font(.caption).foregroundStyle(TennisTheme.muted)
      Text("\(match.players[1-match.server].name) · RETURNER").font(.caption2).frame(
        maxWidth: .infinity)
      GeometryReader { geo in
        CourtDrawing(path: path, landings: landings)
          .gesture(
            DragGesture(minimumDistance: 0).onChanged { value in
              let p = CourtPoint(
                x: clamp(value.location.x / geo.size.width * 100, 0, 100),
                y: clamp(value.location.y / geo.size.height * 160, 0, 160))
              if !drawing {
                path = []
                landings = []
                drawing = true
                captured = true
              }
              if let previous = path.last, hypot(previous.x - p.x, previous.y - p.y) < 0.75 {
                return
              }
              path.append(p)
              lastMove = Date()
              captured = false
            }.onEnded { _ in finish() })
      }.frame(height: 420).accessibilityHint("Use Manual mode for accessible point entry.")
      Text(
        "\(match.players[match.server].name) · SERVE \((match.tiebreak?.points ?? match.points).reduce(0,+)%2 == 0 ? "FROM RIGHT":"FROM LEFT")"
      ).font(.caption2).frame(maxWidth: .infinity)
    }
    .onReceive(clock) { _ in
      if drawing && !captured && Date().timeIntervalSince(lastMove) > 0.25, let p = path.last,
        path.count > 2
      {
        addLanding(p)
        captured = true
      }
    }
    .sheet(item: $pending) { point in
      PointReview(point: point, names: match.players.map(\.name)) { edited in
        store.edit {
          $0.record(
            winner: edited.winner, outcome: edited.outcome, position: edited.position,
            path: edited.path, landings: edited.landings, serve: edited.serve)
        }
        path = []
        landings = []
        pending = nil
        message = "Point saved. Trace the next rally."
      }
    }
    .sheet(isPresented: $help) { TraceTutorial() }
  }
  private func addLanding(_ p: CourtPoint) {
    if let last = landings.last, (last.y < 80) == (p.y < 80) { return }
    landings.append(p)
    Immersion.shared.hit(bounce: true, x: p.x / 100 * 8.23)
  }
  private func finish() {
    drawing = false
    guard let end = path.last else { return }
    addLanding(end)
    switch TraceRules.analyze(match: match, path: path, landings: landings) {
    case .retry(let reason): message = reason
    case .fault(let reason):
      if match.serveAttempt == 1 {
        store.edit { $0.serveAttempt = 2 }
        message = "\(reason). Trace your second serve."
      } else {
        pending = PendingPoint(
          winner: 1 - match.server, outcome: "Double fault", serve: 2, position: .baseline,
          path: path, landings: landings)
      }
    case .point(let winner, let outcome):
      pending = PendingPoint(
        winner: winner, outcome: outcome, serve: match.serveAttempt,
        position: TraceRules.position(path: path, bottom: winner == match.server), path: path,
        landings: landings)
    }
  }
}
struct PointReview: View {
  @Environment(\.dismiss) var dismiss
  @State var point: PendingPoint
  var names: [String]
  var confirm: (PendingPoint) -> Void
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label("Review the point", systemImage: "checkmark.circle").font(.headline)
          Text("Trace recognition suggests a result. Correct it before it changes the score.").font(
            .subheadline
          ).foregroundStyle(.secondary)
        }
        Section {
          Picker("Winner", selection: $point.winner) { ForEach(0..<2) { Text(names[$0]).tag($0) } }
          Picker("Outcome", selection: $point.outcome) {
            ForEach(
              Array(
                Set(
                  [point.outcome, "Ace", "Winner", "Return winner", "Return error", "Double fault"]
                    + names.flatMap { ["\($0) forced error", "\($0) unforced error"] })
              ).sorted(), id: \.self
            ) { Text($0) }
          }
          Picker("Serve", selection: $point.serve) {
            Text("First").tag(1)
            Text("Second").tag(2)
          }
          Picker("Winner’s position", selection: $point.position) {
            ForEach(ShotPosition.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
        }
      }.navigationTitle("Review point").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Retry") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { confirm(point); dismiss() }.accessibilityIdentifier("confirmPoint")
          }
        }
    }
  }
}
struct TraceTutorial: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @State private var progress = 0.0
  @State private var running = false
  private let clock = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()
  private let demo = [
    CourtPoint(x: 68, y: 148), .init(x: 60, y: 118), .init(x: 40, y: 80), .init(x: 25, y: 58),
    .init(x: 40, y: 90), .init(x: 75, y: 138), .init(x: 57, y: 80), .init(x: 20, y: 22),
  ]
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Trace. Pause. Lift.").font(.title2.bold())
          CourtDrawing(path: demo, progress: progress).frame(height: 370)
          Text(
            "1. Begin at the server’s bottom baseline.\n2. Cross into the diagonal service box.\n3. Pause briefly at every bounce.\n4. Alternate sides through the rally.\n5. Lift at the final landing, then review."
          ).lineSpacing(10)
          Button("Play demonstration") {
            progress = reduceMotion ? 1 : 0
            running = !reduceMotion
          }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(24)
      }.background(TennisTheme.cream).navigationTitle("Trace a rally").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }.onAppear {
        progress = 1
      }.onReceive(clock) { _ in
        if running {
          progress = min(1, progress + 0.01)
          if progress >= 1 { running = false }
        }
      }
    }
  }
}
