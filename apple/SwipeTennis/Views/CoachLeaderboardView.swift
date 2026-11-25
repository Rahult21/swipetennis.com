import AuthenticationServices
import SwiftUI

struct CoachLeaderboardCard: View {
  @EnvironmentObject var account: CoachAccountStore
  @State private var metric: CoachMetric = .point
  @State private var isExpanded: Bool
  init(expanded: Bool = false) { _isExpanded = State(initialValue: expanded) }
  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Picker("Leaderboard category", selection: $metric) {
        ForEach(CoachMetric.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented)
      CoachStandings(metric: metric)
      NavigationLink("View leaderboard and account") { CoachLeaderboardView() }
    } label: {
      Label("Coachability Top 10", systemImage: "trophy")
    }.accessibilityIdentifier("coachLeaderboard")
      .task(id: metric) { await account.loadBoard(metric) }
  }
}

struct CoachStandings: View {
  @EnvironmentObject var account: CoachAccountStore
  let metric: CoachMetric
  var board: CoachLeaderboard { account.boards[metric] ?? .example(metric) }
  var body: some View {
    if board.isDemo {
      Label("Example standings", systemImage: "sparkles")
        .font(.subheadline).foregroundStyle(.secondary)
    }
    if board.entries.isEmpty {
      ContentUnavailableView("No records yet", systemImage: "trophy",
        description: Text("Complete a \(metric.rawValue) to set the first record."))
    }
    ForEach(Array(board.entries.enumerated()), id: \.element.id) { rank, entry in
      HStack(spacing: 12) {
        if rank < 3 {
          Image(systemName: "trophy.fill").frame(width: 26)
            .foregroundStyle([Color.orange, Color.gray, Color.brown][rank])
            .accessibilityLabel(["Gold", "Silver", "Bronze"][rank])
        } else {
          Text("\(rank + 1)").monospacedDigit().frame(width: 26).foregroundStyle(.secondary)
        }
        Text(entry.emailMask).font(.body)
        Spacer()
        Text("\(entry.score) CP").font(.body.weight(.semibold)).monospacedDigit()
      }.padding(.vertical, 3).accessibilityElement(children: .combine)
    }
    if let message = account.boardError { Text(message).font(.caption).foregroundStyle(.secondary) }
  }
}

struct CoachLeaderboardView: View {
  @EnvironmentObject var account: CoachAccountStore
  @State private var metric: CoachMetric = .point
  var body: some View {
    List {
      Section {
        Picker("Leaderboard category", selection: $metric) {
          ForEach(CoachMetric.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
      } footer: { Text("Personal bests against any opponent difficulty. +2 for a followed rule, −1 for a missed opportunity.") }
      Section("Top 10 · \(metric.title)") { CoachStandings(metric: metric) }
      Section { CoachRulesCard() }
      Section { NavigationLink { CoachAccountScreen() } label: { Label("Apple account", systemImage: "person.crop.circle") } }
    }.listStyle(.insetGrouped).navigationTitle("Coachability")
      .task(id: metric) { await account.loadBoard(metric) }
      .refreshable { await account.loadBoard(metric) }
  }
}

struct CoachRulesCard: View {
  @State private var isExpanded = false
  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Text("+2 when you follow a rule. −1 for a missed opportunity. Several rules can score in one tennis point.")
        .font(.subheadline).foregroundStyle(.secondary)
      ForEach(CoachRule.allCases) { rule in
        VStack(alignment: .leading, spacing: 6) {
          Label(rule.title, systemImage: "\(rule.rawValue).circle").font(.headline)
          Text(rule.instruction).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
      }
      Text("Rules 1–6 can score again on new opportunities. Recovery and split is scored once per point. Local two-player results stay off the public leaderboard.")
        .font(.caption).foregroundStyle(.secondary)
    } label: {
      Label("How to earn Coachability Points", systemImage: "checkmark.seal")
        .fixedSize(horizontal: false, vertical: true)
    }.accessibilityIdentifier("coachRules")
  }
}

struct CoachAccountScreen: View {
  var body: some View {
    Form { Section { CoachAccountView() } }
      .navigationTitle("Apple account").navigationBarTitleDisplayMode(.inline)
  }
}

/// Native form rows, shared by Settings and the account sheet.
struct CoachAccountView: View {
  @EnvironmentObject var account: CoachAccountStore
  @Environment(\.colorScheme) private var colorScheme
  @State private var confirmDelete = false
  var body: some View {
    Group {
      if let identity = account.identity {
        Label(identity.emailMask, systemImage: "person.crop.circle.badge.checkmark").font(.headline)
        Text(account.pendingCount == 0 ? "Your completed points are ready to sync with your personal bests."
          : "\(account.pendingCount) completed points waiting to sync.").font(.subheadline).foregroundStyle(.secondary)
        if identity.emailMask.contains("•") {
          Text("Refresh Apple sign-in to update your player name. Your scores stay saved.").font(.subheadline)
          Button("Refresh Apple sign-in") { Task { await account.signOut(); await account.prepareSignIn() } }
        }
        Button("Sync results", systemImage: "arrow.triangle.2.circlepath") { Task { await account.sync() } }
        Button("Sign out") { Task { await account.signOut() } }
        Button("Delete account and results", role: .destructive) { confirmDelete = true }
      } else {
        Label("Save your progress", systemImage: "person.crop.circle").font(.headline)
        Text("Sign in with Apple to play and save your Coachability records. Hide My Email works too.")
          .font(.subheadline).foregroundStyle(.secondary)
        SignInWithAppleButton(.signIn, onRequest: account.configure) { result in
          Task { await account.complete(result) }
        }.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black).frame(height: 48)
          .disabled(account.challenge == nil || account.busy)
        if account.challenge == nil && !account.busy {
          Button("Prepare sign-in") { Task { await account.prepareSignIn() } }
        }
      }
      if account.busy { ProgressView("Updating account") }
      if let message = account.error { Text(message).font(.subheadline).foregroundStyle(.red) }
      Text("Only the first five characters before @ appear as your player name. Your full email address and domain are not stored.")
        .font(.caption).foregroundStyle(.secondary)
    }.task { if !account.isSignedIn { await account.prepareSignIn() } }
      .alert("Delete your account and all Coachability results?", isPresented: $confirmDelete) {
        Button("Delete", role: .destructive) { Task { await account.deleteAccount() } }
        Button("Cancel", role: .cancel) {}
      } message: { Text("This removes your cloud records and signs you out. This cannot be undone.") }
  }
}
