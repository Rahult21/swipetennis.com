import XCTest
@testable import TennisCore

final class PointMomentumTests: XCTestCase {
  func testOneRandomAffirmationPerGameAfterTwoLossesAvoidsImmediateRepeats() {
    var momentum = PointMomentum()
    XCTAssertNil(momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0 }))
    let first = momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0 })
    XCTAssertEqual(first?.affirmation, TennisAffirmation.all[0])
    for _ in 0..<8 {
      XCTAssertNil(momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0.8 }))
    }
    _ = momentum.finishPoint(winner: 0, game: 1, againstOpponent: true, random: { 0 })
    _ = momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0 })
    XCTAssertNil(momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0.5 }))
    let next = momentum.finishPoint(winner: 1, game: 2, againstOpponent: true, random: { 0 })
    XCTAssertNotNil(next?.affirmation)
    XCTAssertNotEqual(next?.affirmation, first?.affirmation)
    XCTAssertNotEqual(next?.smile, first?.smile)
    XCTAssertNil(momentum.finishPoint(winner: 1, game: 2, againstOpponent: true, random: { 0.2 }))
  }

  func testRandomSelectionIncludesAllTwentySixAndWinBreaksLosingStreak() {
    var selected = Set<String>()
    for i in 0..<26 {
      var momentum = PointMomentum()
      _ = momentum.finishPoint(winner: 1, game: 0, againstOpponent: true, random: { 0 })
      _ = momentum.finishPoint(winner: 0, game: 0, againstOpponent: true, random: { 0 })
      XCTAssertNil(momentum.finishPoint(winner: 1, game: 0, againstOpponent: true, random: { 0 }))
      let reaction = momentum.finishPoint(winner: 1, game: 0, againstOpponent: true,
        random: { (Double(i) + 0.5) / 26 })
      selected.insert(reaction!.affirmation!.text)
    }
    XCTAssertEqual(selected.count, 26)
  }

  func testBotFrustrationStartsAtTwoWinsAndResetsOnLoss() {
    var momentum = PointMomentum()
    XCTAssertNil(momentum.finishPoint(winner: 0, game: 1, againstOpponent: true, random: { 0 }))
    XCTAssertEqual(momentum.finishPoint(winner: 0, game: 1, againstOpponent: true, random: { 0 })?.frustration, 1)
    XCTAssertEqual(momentum.finishPoint(winner: 0, game: 1, againstOpponent: true, random: { 0 })?.frustration, 2)
    _ = momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0 })
    XCTAssertNil(momentum.finishPoint(winner: 0, game: 1, againstOpponent: true, random: { 0 }))
    XCTAssertNil(momentum.finishPoint(winner: 0, game: 1, againstOpponent: false, random: { 0 }))
  }

  func testAffirmationWaitsForItsReadingTimeBeforeResultAtEveryFrameRate() throws {
    for (dt, quote) in [1.0 / 30, 1.0 / 60, 1.0 / 120].flatMap({ dt in
      [0, 15, 21].map { (dt, $0) }
    }) {
      var engine = PracticeEngine(settings: .init())
      engine.phase = .live
      engine.end(1, reason: "Miss", tip: "", random: { 0 })
      engine.start()
      engine.phase = .live
      engine.end(1, reason: "Miss", tip: "", random: { (Double(quote) + 0.5) / 26 })
      XCTAssertNotNil(engine.pointResolution?.reaction?.affirmation)
      let duration = try XCTUnwrap(engine.pointResolution).duration
      XCTAssertEqual(duration, TennisAffirmation.all[quote].readingDuration)
      let time = engine.time
      while engine.time - time < duration - dt - 0.000001 {
        engine.step(dt)
        XCTAssertFalse(engine.showsPointResult)
      }
      while engine.isResolvingPoint { engine.step(dt) }
      XCTAssertEqual(engine.time - time, duration, accuracy: dt + 0.000001)
      XCTAssertTrue(engine.showsPointResult)
      XCTAssertEqual(engine.scoring.points, [0, 2])
      engine.start()
      engine.phase = .live
      engine.end(1, reason: "Miss", tip: "", random: { 0.9 })
      XCTAssertNil(engine.pointResolution?.reaction?.affirmation)
      XCTAssertEqual(engine.pointResolution?.duration, 0.75)
    }
  }

  func testReadingTimeIsLongerForLongQuotesAndNeverExceedsEightSeconds() {
    XCTAssertEqual(TennisAffirmation.all[0].readingDuration, 4)
    XCTAssertEqual(TennisAffirmation.all[21].readingDuration, 8)
    XCTAssertTrue(TennisAffirmation.all.allSatisfy { (4...8).contains($0.readingDuration) })
    let enormous = TennisAffirmation(text: String(repeating: "Keep going. ", count: 100))
    XCTAssertEqual(enormous.readingDuration, 8)
    XCTAssertEqual(PointReaction(frustration: 2).duration, 2)
    XCTAssertEqual(PointResolution(impact: nil).duration, 0.75)
  }

  func testSmileSelectionVariesIndependentlyFromQuoteAndStaysWithReaction() throws {
    var selected = Set<String>()
    for i in PointReaction.smiles.indices {
      var momentum = PointMomentum()
      _ = momentum.finishPoint(winner: 1, game: 1, againstOpponent: true, random: { 0 })
      var rolls = [0.0, (Double(i) + 0.5) / Double(PointReaction.smiles.count)]
      let reaction = try XCTUnwrap(momentum.finishPoint(winner: 1, game: 1, againstOpponent: true,
        random: { rolls.removeFirst() }))
      XCTAssertEqual(reaction.affirmation, TennisAffirmation.all[0])
      selected.insert(reaction.smile)
      var resolution = PointResolution(impact: nil, reaction: reaction)
      resolution.elapsed = 3
      XCTAssertEqual(resolution.reaction?.smile, reaction.smile)
    }
    XCTAssertEqual(selected, Set(PointReaction.smiles))
  }

  func testStreamingRevealsEveryQuoteAndEmojiInOrderBeforeTimeout() {
    for affirmation in TennisAffirmation.all {
      let reaction = PointReaction(affirmation: affirmation, smile: "☺️")
      XCTAssertEqual(reaction.visibleCharacterCount(at: 0), 0)
      var previous = 0
      for elapsed in stride(from: 0.0, through: reaction.duration, by: 1 / 60) {
        let count = reaction.visibleCharacterCount(at: elapsed)
        XCTAssertGreaterThanOrEqual(count, previous)
        XCTAssertLessThanOrEqual(count, reaction.displayText.count)
        let visible = String(reaction.displayText.prefix(count))
        if count < reaction.displayText.count { XCTAssertFalse(visible.contains("☺️")) }
        previous = count
      }
      XCTAssertGreaterThan(reaction.visibleCharacterCount(at: 0.5), 0)
      XCTAssertLessThan(reaction.visibleCharacterCount(at: 0.5), reaction.displayText.count)
      XCTAssertEqual(reaction.visibleCharacterCount(at: reaction.duration - 1), reaction.displayText.count)
      XCTAssertEqual(reaction.visibleCharacterCount(at: 0, reduceMotion: true), reaction.displayText.count)
    }
  }

  func testTapDuringTypingOrReadingImmediatelyShowsResultWithoutStartingAnotherPoint() throws {
    for elapsed in [0.2, 1.5, 4.0, 7.5] {
      var engine = PracticeEngine(settings: .init())
      engine.phase = .live
      engine.end(1, reason: "Miss", tip: "", random: { 0.8 })
      engine.start()
      engine.phase = .live
      engine.end(1, reason: "Miss", tip: "", random: { 0.82 })
      XCTAssertEqual(engine.pointResolution?.duration, 8)
      engine.pointResolution?.elapsed = elapsed
      let points = engine.scoring.points
      let records = engine.coach.records.map(\.id)
      XCTAssertTrue(engine.showsAffirmation)
      engine.tapCourt(0, at: Vec(x: 1, y: 14))
      XCTAssertTrue(engine.showsPointResult)
      XCTAssertFalse(engine.showsAffirmation)
      XCTAssertFalse(engine.needsSimulation)
      XCTAssertFalse(engine.dismissAffirmation())
      engine.tapCourt(0, at: Vec(x: 4, y: 24))
      XCTAssertEqual(engine.phase, .point)
      XCTAssertEqual(engine.scoring.points, points)
      XCTAssertEqual(engine.coach.records.map(\.id), records)
    }
  }

  func testAffirmationSkipDoesNotShortenOrdinaryFaultOrFrustrationDelay() {
    for reaction in [nil, PointReaction(frustration: 1)] {
      var engine = PracticeEngine(settings: .init())
      engine.phase = .point
      engine.pointResolution = PointResolution(impact: nil, reaction: reaction)
      XCTAssertFalse(engine.dismissAffirmation())
      engine.tapCourt(0, at: .zero)
      XCTAssertEqual(engine.pointResolution?.elapsed, 0)
      XCTAssertFalse(engine.showsPointResult)
    }
  }
}
