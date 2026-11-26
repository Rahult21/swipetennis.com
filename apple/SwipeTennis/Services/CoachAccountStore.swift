import AuthenticationServices
import Foundation
import Security
import SwiftUI

struct CoachIdentity: Codable {
  let token: String
  let userID: String
  let emailMask: String
  var appleUserID: String = ""
  var stRating: STRating?
}
struct AppleChallenge: Decodable { let id: String; let nonce: String }
private struct PendingCoachPoint: Codable { let userID: String; let point: CoachPointRecord }

@MainActor final class CoachAccountStore: ObservableObject {
  @Published private(set) var identity: CoachIdentity?
  @Published private(set) var challenge: AppleChallenge?
  @Published private(set) var busy = false
  @Published var error: String?
  @Published private(set) var boards: [CoachMetric: CoachLeaderboard] = [:]
  @Published private(set) var boardError: String?
  @Published private(set) var pendingCount = 0
  private var pending: [PendingCoachPoint] = []
  private var syncing = false
  private let queueURL: URL
  private let keychainService = "com.swipetennis.coach-account"
  private var api: URL? { CupAPI.url }
  var isSignedIn: Bool { identity != nil }

  init() {
    queueURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SwipeTennis/coach-pending.json")
    if let data = try? Data(contentsOf: queueURL), let stored = try? JSONDecoder().decode([PendingCoachPoint].self, from: data) {
      pending = stored
    }
    var result: CFTypeRef?
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
      identity = try? JSONDecoder().decode(CoachIdentity.self, from: data)
    }
    if let fixture = CupAPI.localTestIdentity { identity = fixture }
    pendingCount = pending.filter { $0.userID == identity?.userID }.count
  }

  private func saveIdentity(_ value: CoachIdentity?) throws {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService]
    if let value {
      let data = try JSONEncoder().encode(value)
      let changes = [kSecValueData as String: data]
      let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
      if status == errSecItemNotFound {
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw accountError("Could not securely save your sign-in.") }
      } else if status != errSecSuccess { throw accountError("Could not securely update your sign-in.") }
    } else { SecItemDelete(query as CFDictionary) }
    identity = value
    pendingCount = pending.filter { $0.userID == value?.userID }.count
  }

  private func accountError(_ message: String) -> NSError {
    NSError(domain: "SwipeTennis", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
    authenticated: Bool = false) async throws -> T {
    guard let api, let url = URL(string: String(path.drop(while: { $0 == "/" })), relativeTo: api) else {
      throw accountError("The online leaderboard is not connected yet. Please try again later.")
    }
    var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 20
    request.httpBody = body
    request.setValue("3", forHTTPHeaderField: "X-Cup-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if authenticated, let identity { request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw accountError("Could not reach the leaderboard.") }
    if !(200..<300).contains(http.statusCode) {
      if authenticated, http.statusCode == 401,
        request.value(forHTTPHeaderField: "Authorization") == identity.map({ "Bearer \($0.token)" }) {
        try saveIdentity(nil)
        challenge = nil
        throw accountError("Your sign-in expired. Sign in with Apple again; saved results will sync to the same account.")
      }
      let message = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
      throw accountError(message ?? "Could not reach the leaderboard. Please retry.")
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  func prepareSignIn() async {
    busy = true; error = nil; challenge = nil
    defer { busy = false }
    do { challenge = try await request("/auth/challenge", method: "POST") }
    catch { self.error = error.localizedDescription }
  }
  func configure(_ request: ASAuthorizationAppleIDRequest) {
    request.requestedScopes = [.email]
    request.nonce = challenge?.nonce
    request.state = challenge?.id
  }
  func complete(_ result: Result<ASAuthorization, Error>) async {
    busy = true; error = nil
    defer { busy = false; challenge = nil }
    do {
      let authorization = try result.get()
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let challenge, credential.state == challenge.id,
        let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
        throw accountError("Apple sign-in expired. Please retry.")
      }
      let payload = try JSONSerialization.data(withJSONObject: ["identityToken": token, "challengeId": challenge.id])
      // Only Apple's verified subject is used by the server. The raw token is never persisted.
      struct Login: Decodable { let token: String; let userID: String; let emailMask: String; let stRating: STRating? }
      let login: Login = try await request("/auth/apple", method: "POST", body: payload)
      try saveIdentity(CoachIdentity(token: login.token, userID: login.userID, emailMask: login.emailMask, appleUserID: credential.user, stRating: login.stRating))
      await sync()
    } catch {
      if (error as? ASAuthorizationError)?.code != .canceled { self.error = error.localizedDescription }
    }
  }

  func restore() async {
    if CupAPI.localTestIdentity != nil { return }
    guard let identity else { return }
    do {
      let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: identity.appleUserID)
      if state == .revoked || state == .notFound { try saveIdentity(nil); return }
    } catch { /* Offline practice retains the signed-in account and queues completed points. */ }
    do {
      struct Profile: Decodable { let userID: String; let emailMask: String; let stRating: STRating? }
      let profile: Profile = try await request("/me", authenticated: true)
      if self.identity?.token == identity.token && profile.userID == identity.userID {
        try saveIdentity(CoachIdentity(token: identity.token, userID: identity.userID,
          emailMask: profile.emailMask, appleUserID: identity.appleUserID, stRating: profile.stRating))
      }
    } catch { /* Retain the offline profile; authenticated 401 responses clear expired sign-ins. */ }
    await sync()
  }

  func enqueue(_ points: [CoachPointRecord], owner: String) {
    guard identity?.userID == owner else { return }
    for point in points where !pending.contains(where: { $0.point.id == point.id }) {
      pending.append(PendingCoachPoint(userID: owner, point: point))
    }
    persistQueue()
    Task { await sync() }
  }
  private func persistQueue() {
    pendingCount = pending.filter { $0.userID == identity?.userID }.count
    do {
      try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(pending).write(to: queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    } catch { self.error = "Could not save pending Coachability results. Keep the app open and retry." }
  }
  func sync() async {
    guard let owner = identity?.userID, !syncing else { return }
    syncing = true
    defer { syncing = false }
    while identity?.userID == owner {
      let batch = Array(pending.filter { $0.userID == owner }.prefix(50))
      guard !batch.isEmpty else { break }
      do {
        struct Upload: Encodable { let points: [CoachPointRecord] }
        struct Accepted: Decodable { let accepted: [UUID] }
        let body = try JSONEncoder().encode(Upload(points: batch.map(\.point)))
        let response: Accepted = try await request("/points", method: "POST", body: body, authenticated: true)
        let accepted = Set(response.accepted)
        guard !accepted.isEmpty else { break }
        pending.removeAll { $0.userID == owner && accepted.contains($0.point.id) }
        persistQueue()
      } catch { self.error = "Results saved on this iPhone. \(error.localizedDescription)"; break }
    }
    await refreshRanking()
    for metric in CoachMetric.allCases { await loadBoard(metric) }
  }
  func refreshRanking() async {
    guard let identity else { return }
    do {
      struct Profile: Decodable { let userID: String; let emailMask: String; let stRating: STRating? }
      let profile: Profile = try await request("/me", authenticated: true)
      guard self.identity?.token == identity.token, profile.userID == identity.userID else { return }
      try saveIdentity(CoachIdentity(token: identity.token, userID: identity.userID,
        emailMask: profile.emailMask, appleUserID: identity.appleUserID, stRating: profile.stRating))
    } catch { /* Keep the last server rating while offline. */ }
  }
  func loadBoard(_ metric: CoachMetric) async {
    do {
      let board: CoachLeaderboard = try await request("/leaderboard?metric=\(metric.rawValue)")
      boards[metric] = board; boardError = nil
    } catch { boardError = "Could not refresh live standings. Previously loaded results may be out of date; examples are labeled." }
  }
  func signOut() async {
    struct Response: Decodable { let ok: Bool }
    let _: Response? = try? await request("/auth/logout", method: "POST", authenticated: true)
    try? saveIdentity(nil)
  }
  func deleteAccount() async {
    guard let owner = identity?.userID else { return }
    busy = true; defer { busy = false }
    do {
      struct Response: Decodable { let deleted: Bool }
      let _: Response = try await request("/me", method: "DELETE", authenticated: true)
      pending.removeAll { $0.userID == owner }; persistQueue(); try saveIdentity(nil)
      let profile = DemoProgressArchive.profile(for:owner)
      for key in ["academy.strength."+profile,"academy.style."+profile,"pressure.results."+owner,"tour.emblem."+owner] {
        UserDefaults.standard.removeObject(forKey:key)
      }
      boards = [:]
    } catch { self.error = error.localizedDescription }
  }
}
