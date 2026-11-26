import SwiftUI

struct SoloCareerLink: View {
  @EnvironmentObject private var store: SoloCareerStore
  @EnvironmentObject private var account: CoachAccountStore
  @State private var error: String?
  private var owner: String { account.identity?.userID ?? DemoProgressArchive.guest }
  var body: some View {
    let career = store.progress(for: owner)
    Section("Road to the Grass Major") {
      NavigationLink { SoloCareerView(owner: owner) } label: {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text(career.next == nil ? "Chapter recap" : career.started ? "Continue Career" : "Start Career")
              .font(.headline)
            Text(career.next.map { "\($0.title) · \($0.rival.rawValue)" } ?? "Club debut complete · regional entry earned")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        } icon: { Image(systemName: "flag.checkered").foregroundStyle(TennisTheme.accent) }
      }.accessibilityIdentifier("soloCareer")
      if let message = error ?? store.loadError { Text(message).foregroundStyle(.red) }
    }.onChange(of: owner, initial: true) { _, id in
      do { try store.claimGuest(for: id); error = nil }
      catch { self.error = error.localizedDescription }
    }
  }
}

private struct SoloCareerView: View {
  @EnvironmentObject private var store: SoloCareerStore
  let owner: String
  @EnvironmentObject private var demos: ShotDemoStore
  @State private var drill: DemoLesson?
  @State private var match: SavedPracticeMatch?
  @State private var error: String?
  var body: some View {
    let career = store.progress(for: owner)
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Label("Chapter 1", systemImage: "flag.checkered").font(.subheadline.weight(.semibold))
          Text("Club debut").font(.largeTitle.weight(.semibold))
          Text("Meet three club rivals, then beat each in a rematch to earn the club’s regional entry.")
            .font(.subheadline)
          ProgressView(value: Double(career.completedCount), total: Double(ClubEncounter.allCases.count))
            .tint(.white).accessibilityLabel("Chapter progress")
          Text("\(career.completedCount) of \(ClubEncounter.allCases.count) encounters complete")
            .font(.caption.monospacedDigit())
        }.padding(.vertical, 8).foregroundStyle(.white)
      }.listRowBackground(Color(red: 0.07, green: 0.25, blue: 0.18))
      if let next = career.next {
        Section {
          LabeledContent("Opponent", value: "\(next.rival.rawValue) · \(next.rival.style.rawValue)")
          Text(next.cue)
          if let previous = career.meetings(with: next.rival).last {
            Text(previous.won ? "You won your last meeting with \(next.rival.rawValue)." : "\(next.rival.rawValue) won your last meeting.")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          if let active = career.active, active.phase != .ready {
            LabeledContent("Saved score", value: "\(active.scoring.pointLabel(0))–\(active.scoring.pointLabel(1))")
          }
          Button {
            do { match = try store.enter(owner: owner); error = nil }
            catch { self.error = error.localizedDescription }
          } label: {
            Label(career.active.map { $0.phase != .ready } == true
              ? "Resume game" : "Play \(next.rival.rawValue)", systemImage: "play.fill")
          }.accessibilityIdentifier("playCareerGame").disabled(store.loadError != nil)
        } header: { Text(next.title) } footer: { Text(next.stakes) }
      } else {
        Section {
          Label("Regional entry earned", systemImage: "rosette").font(.headline)
          Text("You won all three selection games. Your club debut is complete.")
        }.accessibilityIdentifier("careerComplete")
      }
      if let last = career.results.last {
        Section("Last result") {
          Label(last.won ? "You beat \(last.encounter.rival.rawValue)" : "\(last.encounter.rival.rawValue) won the game",
            systemImage: last.won ? "trophy" : "tennisball")
          if let review = last.review { Text(review).font(.subheadline) }
          LabeledContent("Coachability", value: "\(last.coachPoints > 0 ? "+" : "")\(last.coachPoints) CP")
          let lesson = last.encounter.practiceLesson
          if !demos.progress.mastery(lesson).isMastered {
            Button { drill = lesson } label: { Label("Practice " + lesson.title.lowercased(), systemImage: "figure.tennis") }
          }
        }
      }
      Section("Club rivals") {
        ForEach(TourRival.allCases) { rival in
          let matches = career.meetings(with: rival)
          let wins = matches.filter(\.won).count
          LabeledContent {
            Text(matches.isEmpty ? "First meeting ahead" : "\(wins) W · \(matches.count - wins) L").monospacedDigit()
          } label: { VStack(alignment: .leading) {
            Text(rival.rawValue)
            Text(rival.style.rawValue).font(.caption).foregroundStyle(.secondary)
          } }
        }
      }
      if let message = error ?? store.loadError { Text(message).foregroundStyle(.red) }
    }.navigationTitle("Road to the Grass Major").navigationBarTitleDisplayMode(.inline)
      .fullScreenCover(item: $match) { match in PracticeGameView(match: match) }
      .fullScreenCover(item: $drill) { lesson in ShotDemoFlowView(first: lesson) }
  }
}
