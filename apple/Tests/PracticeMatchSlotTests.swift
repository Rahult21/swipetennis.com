import Foundation
import XCTest
@testable import TennisCore

final class PracticeMatchSlotTests: XCTestCase {
  private func temporaryFile() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: dir) }
    return dir.appendingPathComponent("practice-match.json")
  }

  private func encoded(_ engine: PracticeEngine) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(engine)
  }

  @MainActor func testRelaunchContinuesSameFrameAndDoesNotCreateNewCoachRecords() async throws {
    let file = try temporaryFile()
    let slot = PracticeMatchSlot(file: file)
    var game = PracticeEngine(settings: .init(difficulty: .medium, surface: .clay))
    game.scoring = PracticeScore(format: .tennis, firstServer: 0)
    for _ in 0..<2 {
      game.start()
      game.phase = .live
      game.end(0, reason: "Winner", tip: "", random: { 0.5 })
    }
    game.start()
    game.phase = .live
    game.launch(1, aim: Vec(x: 2.8, y: 22), kind: .cross)
    game.inventory.held = .rally
    game.tapCourt(0, at: try XCTUnwrap(game.contactGuide(0)))
    game.usePower()
    for _ in 0..<7 { game.step(1 / 120, random: { 0.5 }) }
    XCTAssertNotNil(game.assist)
    try slot.save(game, owner: "A")
    let restoredSlot = PracticeMatchSlot(file: file)
    XCTAssertNil(restoredSlot.match(for: "B"))
    var resumed = try XCTUnwrap(restoredSlot.match(for: "A")?.engine)
    XCTAssertEqual(try encoded(resumed), try encoded(game))
    let ids = game.coach.records.map(\.id)
    XCTAssertEqual(resumed.momentum.winsInRow, 2)
    XCTAssertEqual(resumed.scoring.pointLabel(0), "30")
    while resumed.phase == .live && resumed.time < 20 {
      game.step(1 / 120, random: { 0.5 })
      resumed.step(1 / 120, random: { 0.5 })
    }
    XCTAssertEqual(resumed.phase, .point)
    XCTAssertEqual(resumed.scoring.points, game.scoring.points)
    XCTAssertEqual(resumed.coach.records.count, ids.count + 1)
    XCTAssertEqual(Array(resumed.coach.records.dropLast().map(\.id)), ids)
    XCTAssertEqual(resumed.coach.records.last?.sessionID, game.coach.sessionID)
    XCTAssertEqual(resumed.coach.records.last?.pointIndex, game.coach.records.last?.pointIndex)
  }

  @MainActor func testSaveSecondServeAndPointRecapWithoutRestartingOrRescoring() async throws {
    let slot = PracticeMatchSlot(file: try temporaryFile())
    var game = PracticeEngine(settings: .init(local: true, scoring: .tiebreak))
    game.start()
    game.prepareSecondServe()
    game.chooseServe(.wide, side: game.scoring.server)
    for _ in 0..<150 { game.step(1 / 120) }
    game.requestServe(game.scoring.server)
    game.step(0.03)
    try slot.save(game, owner: "A")
    let toss = try XCTUnwrap(slot.saved?.engine.servePreparation)
    XCTAssertEqual(toss.number, 2)
    XCTAssertEqual(toss.tossElapsed, game.servePreparation?.tossElapsed)
    game.phase = .live
    game.end(1, reason: "Winner", tip: "")
    for _ in 0..<150 { game.step(1 / 120) }
    try slot.save(game, owner: "A")
    var restored = try XCTUnwrap(slot.saved?.engine)
    XCTAssertTrue(restored.showsPointResult)
    let before = restored.coach.records.map(\.id)
    restored.start()
    XCTAssertEqual(restored.phase, .serving)
    XCTAssertEqual(restored.scoring.points, [0, 1])
    XCTAssertEqual(restored.scoring.server, game.scoring.server)
    XCTAssertEqual(restored.coach.records.map(\.id), before)
  }

  @MainActor func testOnlyStartingAnotherMatchReplacesTheSlotAndDiscardIsScoped() async throws {
    let file = try temporaryFile()
    let slot = PracticeMatchSlot(file: file)
    var first = PracticeEngine(settings: .init())
    first.start()
    try slot.save(first, owner: "A")
    var second = PracticeEngine(settings: .init())
    try slot.save(second, owner: "B")
    XCTAssertEqual(slot.saved?.id, first.coach.sessionID)
    second.start()
    try slot.save(second, owner: "B")
    try slot.discard(first.coach.sessionID, owner: "A")
    try slot.discard(second.coach.sessionID, owner: "A")
    XCTAssertNil(slot.match(for: "A"))
    XCTAssertEqual(PracticeMatchSlot(file: file).match(for: "B")?.id, second.coach.sessionID)
    try slot.discard(second.coach.sessionID, owner: "B")
    XCTAssertNil(PracticeMatchSlot(file: file).saved)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  @MainActor func testFailedWriteKeepsPreviousMatchAvailable() async throws {
    let file = try temporaryFile()
    let slot = PracticeMatchSlot(file: file)
    var game = PracticeEngine(settings: .init())
    game.start()
    try slot.save(game, owner: "A")
    // Replace the destination with a directory to simulate an atomic write failure.
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    var other = PracticeEngine(settings: .init())
    other.start()
    XCTAssertThrowsError(try slot.save(other, owner: "B"))
    XCTAssertEqual(slot.match(for: "A")?.id, game.coach.sessionID)
  }
}
