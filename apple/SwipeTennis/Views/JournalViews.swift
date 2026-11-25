import Combine
import SwiftUI

struct HistoryView: View {
  @EnvironmentObject var store: AppStore
  @State private var filter = false
  var matches: [TennisMatch] {
    guard filter, let p = store.data.player else { return store.data.history }
    return store.data.history.filter {
      $0.players.contains { $0.name.caseInsensitiveCompare(p.name) == .orderedSame }
    }
  }
  var body: some View {
    List {
      if let player = store.data.player { Toggle("Only \(player.name)’s matches", isOn: $filter) }
      if matches.isEmpty {
        ContentUnavailableView(
          "Your story starts here", systemImage: "tennisball",
          description: Text("Saved matches, point-by-point replays, and reports will appear here."))
      }
      ForEach(matches) { match in
        NavigationLink {
          ReportView(match: match)
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            Text("\(match.players[0].name) vs \(match.players[1].name)").font(.headline)
            Text(match.score).font(.title3.weight(.semibold).monospacedDigit())
            Text(
              "\(match.createdAt.formatted(date:.abbreviated,time:.omitted)) · \(match.winner == nil ? "Unfinished":"Completed")"
            ).font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
        }
      }
    }.navigationTitle("Journal").listStyle(.insetGrouped)
  }
}
struct ReportView: View {
  @Environment(\.dismiss) var dismiss
  var match: TennisMatch
  var presented = false
  private let metrics = ["Points won", "Aces", "Winners", "First serve points won", "Second serve points won",
    "Forced errors", "Unforced errors", "Double faults"]
  var body: some View {
    List {
      Section { Scoreboard(match: match) }
      Section {
        ForEach(metrics, id: \.self) { metric in
          HStack {
            Text("\(match.stats(0)[metric] ?? 0)").fontWeight(.semibold).frame(width: 35)
            Spacer()
            Text(metric).font(.subheadline).multilineTextAlignment(.center)
            Spacer()
            Text("\(match.stats(1)[metric] ?? 0)").fontWeight(.semibold).frame(width: 35)
          }.monospacedDigit().accessibilityElement(children: .combine)
        }
      } header: {
        HStack { Text(match.players[0].name); Spacer(); Text(match.players[1].name) }
      } footer: { Text("Serve statistics count points won on each serve attempt.") }
      Section("Winning positions") {
        ForEach(ShotPosition.allCases, id: \.self) { position in
          LabeledContent(position.rawValue, value: "\(match.log.filter { $0.position == position }.count)")
        }
      }
      Section {
        NavigationLink { ReplayView(match: match) } label: { Label("Replay match", systemImage: "play.fill") }
          .disabled(match.log.isEmpty)
      }
    }.listStyle(.insetGrouped).navigationTitle("Match report").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { ShareLink(item: match.report) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share report") }
        if presented { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      }
  }
}
struct ReplayView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.scenePhase) var scenePhase
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  var match: TennisMatch
  var presented = false
  @State private var index = 0
  @State private var speed = 1.0
  @State private var progress = 0.0
  @State private var playing = false
  let clock = Timer.publish(every: 0.04, on: .main, in: .common).autoconnect()
  var entry: PointEntry? { match.log.indices.contains(index) ? match.log[index] : nil }
  var frame: TennisMatch {
    var m = TennisMatch(
      players: match.players, mode: match.mode, bestOfThree: match.bestOfThree,
      gamesPerSet: match.gamesPerSet, useSetTiebreak: match.useSetTiebreak,
      firstServer: match.firstServer, server: match.firstServer)
    for point in match.log.prefix(index + 1) { m.advance(point.winner) }
    return m
  }
  var body: some View {
    List {
        if let entry {
          Section { Scoreboard(match: frame) }
          Section {
          HStack {
            Eyebrow(text: "Point \(index+1) of \(match.log.count)")
            Spacer()
            Text(entry.event).font(.caption.bold())
          }
          ZStack {
            CourtDrawing(
              path: entry.path, landings: progress >= 1 ? entry.landings : [],
              progress: reduceMotion ? 1 : min(1, progress)
            ).frame(maxWidth: 320).frame(height: 420)
            if entry.path.isEmpty {
              Text("Manually recorded\n\(entry.outcome)").font(.headline).multilineTextAlignment(
                .center
              ).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
          }
          Text("\(match.players[entry.winner].name) · \(entry.outcome)").font(.headline)
          Text("\(entry.position.rawValue) · Serve \(entry.serve)").font(.caption).foregroundStyle(.secondary)
          }
          Section("Playback") {
          Slider(
            value: Binding(
              get: { Double(index) },
              set: {
                index = Int($0)
                progress = 0
              }), in: 0...Double(max(1, match.log.count - 1)), step: 1
          ).disabled(match.log.count < 2).accessibilityLabel("Replay point")
          HStack {
            Button {
              index = max(0, index - 1)
              progress = 0
            } label: {
              Image(systemName: "backward.end.fill")
            }.disabled(index == 0).accessibilityLabel("Previous point")
            Spacer()
            Button {
              if index == match.log.count - 1 && progress >= 1 {
                index = 0
                progress = 0
              }
              playing.toggle()
            } label: {
              Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            Spacer()
            Button {
              index = min(match.log.count - 1, index + 1)
              progress = 0
            } label: {
              Image(systemName: "forward.end.fill")
            }.disabled(index == match.log.count - 1).accessibilityLabel("Next point")
          }.buttonStyle(.bordered).controlSize(.large)
          Picker("Playback speed", selection: $speed) {
            Text("0.5×").tag(0.5)
            Text("1×").tag(1.0)
            Text("2×").tag(2.0)
          }.pickerStyle(.segmented)
          }
        } else {
          ContentUnavailableView("No points yet", systemImage: "play.slash")
        }
    }.listStyle(.insetGrouped).navigationTitle("Match replay").navigationBarTitleDisplayMode(
      .inline
    )
    .toolbar { if presented { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
    .onReceive(clock) { _ in
      guard playing else { return }
      progress += 0.04 * speed / 1.8
      if progress > 1.4 {
        if index < match.log.count - 1 {
          index += 1
          progress = 0
        } else {
          playing = false
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
    .onDisappear { playing = false }
  }
}
