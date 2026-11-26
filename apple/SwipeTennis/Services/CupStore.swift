import Foundation
import SwiftUI

@MainActor final class CupStore: ObservableObject {
  @Published private(set) var cups: [QuickCup] = []
  @Published var selectedCode: String?
  @Published var pendingInvite: String?
  @Published var error: String?
  @Published private(set) var busy = false
  private var requestID = UUID().uuidString
  private var owner: String?
  var selected: QuickCup? { cups.first { $0.code == selectedCode } }
  func reset(owner: String?) {
    guard self.owner != owner else { return }
    self.owner = owner; cups = []; selectedCode = nil; error = nil
  }
  func update(_ cup: QuickCup) {
    if let old = cups.first(where: { $0.code == cup.code }), old.version > cup.version { return }
    cups.removeAll { $0.code == cup.code }; cups.append(cup)
    cups.sort { $0.createdAt > $1.createdAt }
  }
  func refresh(_ account: CoachAccountStore) async {
    guard let id = account.identity?.userID else { return }
    reset(owner: id)
    do {
      struct Result: Decodable { let cups: [QuickCup] }
      let result: Result = try await account.request("cups", authenticated: true)
      guard account.identity?.userID == id else { return }
      for cup in result.cups { update(cup) }
      error = nil
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
  func create(_ account: CoachAccountStore, title: String, name: String, level: CupLevel, surface: CourtSurface) async {
    await perform(account, path: "cups", payload: ["requestID": requestID, "title": title,
      "name": name, "level": level.rawValue, "surface": surface.rawValue.lowercased()])
    if error == nil { requestID = UUID().uuidString }
  }
  func join(_ account: CoachAccountStore, text: String, name: String) async {
    guard let code = QuickCup.inviteCode(from: text) else { error = "Enter an eight-character cup code or a SwipeTennis invite link."; return }
    await perform(account, path: "cups/\(code)/join", payload: ["name": name])
  }
  func action(_ action: String, cup: QuickCup, account: CoachAccountStore, ready: Bool = true) async {
    await perform(account, path: "cups/\(cup.code)/\(action)", payload: ["ready": ready])
    if action == "leave", error == nil {
      selectedCode = nil
      if cup.status == "lobby" { cups.removeAll { $0.code == cup.code } }
    }
  }
  private func perform(_ account: CoachAccountStore, path: String, payload: [String: Any]) async {
    guard !busy, let id = account.identity?.userID else { return }
    busy = true; error = nil
    defer { busy = false }
    do {
      let cup: QuickCup = try await account.request(path, method: "POST",
        body: JSONSerialization.data(withJSONObject: payload), authenticated: true)
      guard account.identity?.userID == id else { return }
      update(cup); selectedCode = cup.code
    } catch { self.error = error.localizedDescription }
  }
}

private struct CupMessage: Decodable {
  let type: String
  var cup: QuickCup?
  var snapshot: PracticeEngine?
  var side: Int?
  var authority: Bool?
  var input: CupInput?
  var ready: Bool?
  var deadline: Double?
  var point: Int?
  var message: String?
}

@MainActor final class CupMatchSession: ObservableObject {
  @Published var game: PracticeEngine
  @Published private(set) var connection = "Connecting to the court…"
  @Published private(set) var connected = false
  @Published private(set) var ready = false
  @Published private(set) var waitingForNext = false
  @Published private(set) var result: CupMatch?
  @Published private(set) var error: String?
  @Published private(set) var reconnectDeadline: Date?
  let scene: TennisScene
  let side: Int
  let isAuthority: Bool
  let cupCode: String
  let matchID: String
  private let identity: CoachIdentity
  private let onCup: (QuickCup) -> Void
  private var socket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var heartbeat: Task<Void, Never>?
  private var reconnectTask: Task<Void, Never>?
  private var generation = UUID()
  private var active = true
  private var retries = 0
  private var outbox: [(kind: String, data: Data)] = []
  private var sending = false
  private var lastAimSent = Date.distantPast

  init(cup: QuickCup, match: CupMatch, identity: CoachIdentity, onCup: @escaping (QuickCup) -> Void) {
    self.identity = identity; self.onCup = onCup
    cupCode = cup.code; matchID = match.id
    side = match.playerIDs.firstIndex(of: identity.userID) ?? 0
    isAuthority = match.authorityID == identity.userID
    let engine = cup.engine(for: match)
    game = engine
    scene = TennisScene(settings: engine.settings)
    scene.engine = engine; scene.controlledSide = side; scene.perspectiveSide = side
    scene.isReplica = !isAuthority; scene.suspended = true
    scene.publish = { [weak self] engine in self?.game = engine }
    scene.onCupInput = { [weak self] input in self?.input(input) }
    scene.onCupFrame = { [weak self] engine in self?.sendSnapshot(engine) }
  }
  func connect() {
    guard active, result == nil else { return }
    stopConnection()
    let current = generation
    guard let base = CupAPI.url,
      var url = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
      error = "The cup service is not configured."; return
    }
    url.scheme = CupAPI.localTestURL != nil ? "ws" : "wss"; url.path += "cups/\(cupCode)/matches/\(matchID)/socket"
    guard let socketURL = url.url else { return }
    var request = URLRequest(url: socketURL)
    request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
    let task = URLSession.shared.webSocketTask(with: request)
    task.maximumMessageSize = 128000
    socket = task; connection = retries == 0 ? "Connecting to the court…" : "Reconnecting…"
    task.resume()
    receiveTask = Task { [weak self] in
      do {
        while !Task.isCancelled {
          let received = try await task.receive()
          guard let self, generation == current else { return }
          let data: Data
          switch received { case .data(let value): data = value; case .string(let value): data = Data(value.utf8); @unknown default: continue }
          let message = try JSONDecoder().decode(CupMessage.self, from: data)
          handle(message)
        }
      } catch {
        guard let self, generation == current, !Task.isCancelled else { return }
        lostConnection()
      }
    }
    heartbeat = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
        guard let self, generation == current else { return }
        send(["type": "ping"])
      }
    }
  }
  private func handle(_ message: CupMessage) {
    if let cup = message.cup {
      onCup(cup)
      if let finished = cup.matches.first(where: { $0.id == matchID && $0.complete }) {
        result = finished; ready = false; scene.suspended = true; connection = "Match complete"
      } else if cup.isClosed { ready = false; scene.suspended = true; error = "This cup has \(cup.status). Return to the draw." }
    }
    switch message.type {
    case "welcome":
      guard message.side == side, message.authority == isAuthority else { error = "The court assignment changed. Return to the draw."; stopConnection(); return }
      connected = true; retries = 0; error = nil
      if let snapshot = message.snapshot {
        if isAuthority { scene.engine = snapshot; scene.restorePresentation(); game = snapshot }
        else { scene.receiveCupSnapshot(snapshot) }
      }
    case "presence":
      ready = message.ready == true && result == nil
      reconnectDeadline = message.deadline.map { Date(timeIntervalSince1970: $0 / 1000) }
      scene.suspended = !ready; scene.resetClock()
      connection = ready ? "Connected" : "Waiting for your opponent…"
      if ready { sendSnapshot(scene.engine) }
    case "snapshot": if !isAuthority, let snapshot = message.snapshot { scene.receiveCupSnapshot(snapshot) }
    case "input":
      if isAuthority, ready, let input = message.input, let side = message.side, side != self.side {
        input.apply(to: &scene.engine, side: side)
      }
    case "advance":
      waitingForNext = false
      if isAuthority, ready, message.point == scene.engine.scoring.points.reduce(0, +), [.ready, .point].contains(scene.engine.phase) {
        scene.engine.start(); scene.resetRallyPresentation(); scene.resetClock()
        game = scene.engine; sendSnapshot(scene.engine)
      }
    case "error": error = message.message
    default: break
    }
  }
  func input(_ input: CupInput) {
    guard ready, result == nil else { return }
    if !isAuthority, input.kind == "serveAim", input.finished == false {
      guard Date().timeIntervalSince(lastAimSent) >= 1 / 30 else { return }
      lastAimSent = Date()
    }
    if isAuthority { input.apply(to: &scene.engine, side: side); game = scene.engine }
    else if let value = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) { send(["type": "input", "input": value]) }
  }
  func next() {
    guard ready, result == nil else { return }
    waitingForNext = true
    send(["type": "next", "point": game.scoring.points.reduce(0, +)])
  }
  func forfeit() { send(["type": "forfeit"]) }
  private func sendSnapshot(_ engine: PracticeEngine) {
    guard isAuthority, ready, connected, result == nil else { return }
    var state = engine
    state.history = []; state.coach = engine.coach.cupSnapshot
    if let value = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) { send(["type": "snapshot", "snapshot": value]) }
  }
  private func send(_ value: [String: Any]) {
    guard let socket, let data = try? JSONSerialization.data(withJSONObject: value), let kind = value["type"] as? String else { return }
    // Preserve ordering, including point changes, while bounding slow-connection queues.
    if outbox.count > 100 { lostConnection(); return }
    outbox.append((kind, data))
    guard !sending else { return }
    sending = true
    let current = generation
    Task { [weak self] in
      guard let self else { return }
      do {
        while !outbox.isEmpty && generation == current {
          let next = outbox.removeFirst()
          try await socket.send(.string(String(decoding: next.data, as: UTF8.self)))
        }
        if generation == current { sending = false }
      } catch { if generation == current { sending = false; lostConnection() } }
    }
  }
  private func lostConnection() {
    stopConnection()
    guard active, result == nil else { return }
    connection = "Connection lost. Reconnecting…"
    retries += 1
    if retries > 7 { error = "Could not reconnect. Return to the draw to check the result."; return }
    let delay = min(8, retries)
    reconnectTask = Task { [weak self] in
      guard let self else { return }
      if await checkResult() { return }
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      connect()
    }
  }
  private func checkResult() async -> Bool {
    guard let base = CupAPI.url, let url = URL(string: "cups/\(cupCode)", relativeTo: base) else { return false }
    var request = URLRequest(url: url); request.timeoutInterval = 5
    request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      if (response as? HTTPURLResponse)?.statusCode == 401 {
        error = "Your sign-in expired. Return to the draw and sign in again."; return true
      }
      let cup = try JSONDecoder().decode(QuickCup.self, from: data)
      onCup(cup)
      if let finished = cup.matches.first(where: { $0.id == matchID && $0.complete }) {
        result = finished; connection = "Match complete"; return true
      }
      if cup.isClosed { error = "This cup has \(cup.status). Return to the draw."; return true }
    } catch { }
    return false
  }
  private func stopConnection() {
    generation = UUID(); receiveTask?.cancel(); heartbeat?.cancel()
    socket?.cancel(with: .goingAway, reason: nil); socket = nil
    outbox = []; sending = false; connected = false; ready = false
    scene.suspended = true; scene.resetClock()
  }
  func suspend() { active = false; reconnectTask?.cancel(); stopConnection() }
  func resume() { active = true; retries = 0; connect() }
  func close() { suspend(); scene.onCupFrame = nil; scene.onCupInput = nil }
}
