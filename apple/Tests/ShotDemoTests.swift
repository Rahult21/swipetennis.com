import XCTest
@testable import TennisCore

final class ShotDemoTests: XCTestCase {
  private func finish(_ engine: inout PracticeEngine, dt: Double = 1/120, learner: Bool = false) {
    let limit = engine.demo?.lesson.isFootwork == true ? 90.0 : 30.0
    for _ in 0..<Int(limit/dt) where engine.demo?.result == nil {
      if learner { engine.performDemoScript() }
      engine.step(dt)
    }
  }
  func testEveryDemonstrationShowsAValidShotAtAllFrameRatesOnBothSides() throws {
    for dt in [1.0/30, 1.0/60, 1.0/120] {
      for lesson in DemoLesson.allCases {
        for attempt in 0...1 {
          var engine = PracticeEngine(settings: .init())
          engine.beginShotDemo(lesson, attempt: attempt, demonstration: true)
          finish(&engine, dt: dt)
          let result = try XCTUnwrap(engine.demo?.result, "\(lesson) did not finish")
          XCTAssertTrue(result.success, "\(lesson) #\(attempt) at \(dt): \(result.message)")
          XCTAssertTrue(result.demonstration)
          XCTAssertEqual(engine.scoring.points, [0,0])
          XCTAssertTrue(engine.coach.records.isEmpty)
          XCTAssertTrue(engine.coach.events.isEmpty)
          XCTAssertFalse(engine.showsPointResult)
        }
      }
    }
  }
  func testActualInputsCanPassEveryLessonButDoingNothingCannotMasterAnAutomaticReturn() throws {
    for lesson in DemoLesson.allCases {
      var engine = PracticeEngine(settings: .init())
      engine.beginShotDemo(lesson, attempt: 0, demonstration: false)
      finish(&engine, learner: true)
      XCTAssertTrue(try XCTUnwrap(engine.demo?.result).success, lesson.rawValue)
      XCTAssertFalse(engine.demo!.result!.demonstration)
      var inactive = PracticeEngine(settings: .init())
      inactive.beginShotDemo(lesson, attempt: 0, demonstration: false)
      if lesson.placement != nil {
        for _ in 0..<100 { inactive.step(1/120) }
        inactive.requestServe(0)
      } else if inactive.contactGuide(0) != nil { inactive.apply(.guidedMove(.receive), side: 0) }
      finish(&inactive)
      XCTAssertFalse(try XCTUnwrap(inactive.demo?.result).success, "Automatic \(lesson) must not pass")
    }
  }
  func testMistakeResetsStreakDemonstrationsNeverCountAndMasteredLessonsStayHidden() throws {
    var progress = DemoProgress()
    let lesson = DemoLesson.crosscourt
    func result(_ success: Bool, demo: Bool = false) -> DemoOutcome {
      DemoOutcome(id: UUID(), success: success, message: "test", demonstration: demo)
    }
    progress.record(result(true, demo: true), lesson: lesson)
    XCTAssertEqual(progress.mastery(lesson).attempts, 0)
    let first = result(true)
    progress.record(first, lesson: lesson); progress.record(first, lesson: lesson)
    XCTAssertEqual(progress.mastery(lesson).streak, 1)
    XCTAssertFalse(progress.mastery(lesson).isMastered)
    progress.record(result(false), lesson: lesson)
    XCTAssertEqual(progress.mastery(lesson).streak, 0)
    for _ in 0..<DemoMastery.target { progress.record(result(true), lesson: lesson) }
    XCTAssertFalse(progress.remaining.contains(lesson))
    progress.record(result(false), lesson: lesson)
    XCTAssertTrue(progress.mastery(lesson).isMastered)
    let restored = try JSONDecoder().decode(DemoProgress.self, from: JSONEncoder().encode(progress))
    XCTAssertEqual(restored, progress)
    XCTAssertEqual(restored.next, .rallyRecovery)
  }
  func testProgressIsAccountScopedAndGuestProgressIsClaimedOnlyOnce() throws {
    var archive = DemoProgressArchive()
    var guest = DemoProgress()
    for _ in 0..<DemoMastery.target { guest.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: .dropShot) }
    archive.profiles[DemoProgressArchive.guest] = guest
    let one = DemoProgressArchive.profile(for: "one"), two = DemoProgressArchive.profile(for: "two")
    archive.claimGuest(for: one)
    archive = try JSONDecoder().decode(DemoProgressArchive.self, from: JSONEncoder().encode(archive))
    XCTAssertTrue(archive.profiles[one]!.mastery(.dropShot).isMastered)
    XCTAssertTrue(archive.profiles[DemoProgressArchive.guest]!.remaining.contains(.dropShot))
    archive.claimGuest(for: two)
    XCTAssertNil(archive.profiles[two])
    XCTAssertEqual(archive.guestClaimedBy, one)
  }

  func testWrongGestureDirectionAndMissingFollowThroughCannotPass() throws {
    for lesson in [DemoLesson.crosscourt, .centerLob, .approachVolley] {
      var engine = PracticeEngine(settings: .init())
      engine.beginShotDemo(lesson, attempt: 0, demonstration: false)
      engine.apply(.guidedMove(.receive), side: 0)
      for _ in 0..<150 { engine.step(1/120) }
      // Crosscourt deliberately stays on the same side, the lob aims away from center,
      // and the approach selects the correct shot but never commands a second swipe.
      let wrong = lesson == .crosscourt ? Vec(x: -40, y: -40)
        : lesson == .centerLob ? Vec(x: 40, y: 50) : Vec(x: 0, y: -50)
      engine.selectShotSwipe(wrong, side: 0)
      finish(&engine)
      XCTAssertFalse(try XCTUnwrap(engine.demo?.result).success, lesson.rawValue)
    }
    var wrongShot = PracticeEngine(settings: .init())
    wrongShot.beginShotDemo(.crosscourt, attempt: 0, demonstration: false)
    wrongShot.apply(.guidedMove(.receive), side: 0)
    wrongShot.selectShotSwipe(Vec(x: 0, y: -50), side: 0)
    finish(&wrongShot)
    XCTAssertFalse(try XCTUnwrap(wrongShot.demo?.result).success)
  }

  func testWrongServePlacementFailsAndFirstReturnReallyTargetsServer() throws {
    var serve = PracticeEngine(settings: .init())
    serve.beginShotDemo(.serveWide, attempt: 0, demonstration: false)
    let wrongTarget = try XCTUnwrap(serve.demo?.initialBlue)
    serve.aimServe(at: Vec(x: wrongTarget.x + 0.2, y: wrongTarget.y + 0.2), side: 0)
    serve.requestServe(0)
    finish(&serve)
    XCTAssertTrue(serve.demo?.serveAdjusted == true)
    XCTAssertFalse(try XCTUnwrap(serve.demo?.result).success)

    var returned = PracticeEngine(settings: .init())
    returned.beginShotDemo(.firstReturn, attempt: 0, demonstration: true)
    finish(&returned)
    XCTAssertEqual(try XCTUnwrap(returned.flight).landing.x, returned.players[1].pos.x, accuracy: 0.85)
  }

  func testAllMasteredLessonsAreOmittedAfterReload() throws {
    var progress = DemoProgress()
    for lesson in DemoLesson.allCases {
      for _ in 0..<DemoMastery.target {
        progress.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: lesson)
      }
    }
    let restored = try JSONDecoder().decode(DemoProgress.self, from: JSONEncoder().encode(progress))
    XCTAssertTrue(restored.remaining.isEmpty)
    XCTAssertNil(restored.next)
  }

  func testFootworkAttemptRequiresAllFourExchangesIncludingFinalRecovery() throws {
    for lesson in [DemoLesson.rallyRecovery, .recoverySplit] {
      var engine = PracticeEngine(settings: .init())
      engine.beginShotDemo(lesson, attempt: 0, demonstration: false)
      for _ in 0..<10_800 where engine.demo?.result == nil && engine.demo!.completedExchanges < 3 {
        engine.performDemoScript()
        engine.step(1/120)
        if engine.demo!.completedExchanges < 4 { XCTAssertNil(engine.demo?.result) }
      }
      XCTAssertEqual(engine.demo?.completedExchanges, 3)
      XCTAssertNil(engine.demo?.result)
      // Receive the fourth ball, but deliberately skip its recovery.
      for _ in 0..<1_800 where engine.demo?.result == nil {
        if engine.demo?.stage == .receive { engine.performDemoScript() }
        engine.step(1/120)
      }
      XCTAssertFalse(try XCTUnwrap(engine.demo?.result).success)
      XCTAssertEqual(engine.demo?.completedExchanges, 3)
      var progress = DemoProgress()
      progress.record(engine.demo!.result!, lesson: lesson)
      XCTAssertEqual(progress.mastery(lesson).streak, 0)

      engine.beginShotDemo(lesson, attempt: 1, demonstration: false)
      finish(&engine, learner: true)
      XCTAssertEqual(engine.demo?.completedExchanges, 4)
      progress.record(try XCTUnwrap(engine.demo?.result), lesson: lesson)
      XCTAssertEqual(progress.mastery(lesson).streak, 1, "One four-exchange rally is only one of six attempts")
    }
  }

  func testSplitRequiresANewTapAfterPhysicalRecoveryAndAcceptsAnyCourtLocation() throws {
    for splitAfterArrival in [false, true] {
      var engine = PracticeEngine(settings: .init())
      engine.beginShotDemo(.recoverySplit, attempt: 0, demonstration: false)
      for _ in 0..<10_800 where engine.demo?.result == nil {
        let run = try XCTUnwrap(engine.demo)
        if run.stage == .receive { engine.performDemoScript() }
        if run.stage == .rallyRecovery, !run.scriptTap {
          engine.apply(.guidedMove(.recover), side: 0)
          engine.demo?.scriptTap = true
          XCTAssertFalse(engine.demo!.splitAfterRecovery, "Swiping toward white cannot count as a split")
        }
        if splitAfterArrival, run.recoveredAt != nil, engine.inSplitWindow(0),
          !run.splitAfterRecovery {
          // An empty patch of court is a valid deliberate split tap.
          engine.tapCourt(0, at: Vec(x: 7.8, y: 18))
          XCTAssertTrue(engine.demo!.splitAfterRecovery)
        }
        engine.step(1/120)
      }
      XCTAssertEqual(try XCTUnwrap(engine.demo?.result).success, splitAfterArrival)
      XCTAssertEqual(engine.demo?.completedExchanges, splitAfterArrival ? 4 : 0)
    }
  }

  func testCourtUnlockRequiresTheSpecificFirstFiveSkillsAndSurvivesReload() throws {
    var progress = DemoProgress()
    func master(_ lesson: DemoLesson) {
      for _ in 0..<DemoMastery.target { progress.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: lesson) }
    }
    XCTAssertEqual(Array(DemoLesson.allCases.prefix(5)), DemoLesson.courtEntrySkills)
    for lesson in [DemoLesson.centerLob, .dropShot, .slice, .overhead, .serveWide] { master(lesson) }
    XCTAssertFalse(progress.unlocksCourt, "Five optional skills cannot bypass the five required skills")
    XCTAssertEqual(progress.requiredMasteredCount, 0)
    for lesson in DemoLesson.courtEntrySkills.dropLast() { master(lesson) }
    XCTAssertFalse(progress.unlocksCourt)
    XCTAssertEqual(progress.requiredMasteredCount, 4)
    XCTAssertEqual(progress.next, .shortAngle)
    master(.shortAngle)
    let restored = try JSONDecoder().decode(DemoProgress.self, from: JSONEncoder().encode(progress))
    XCTAssertTrue(restored.unlocksCourt)
    XCTAssertEqual(restored.requiredMasteredCount, 5)
    XCTAssertTrue(restored.requiredRemaining.isEmpty)
    XCTAssertFalse(DemoProgress().unlocksCourt, "A different player's empty profile remains locked")
  }

  func testExistingShotMasteryIsPreservedWhileNewFoundationsRemainRequired() throws {
    // Same schema as progress saved before the two movement lessons existed.
    let old = """
      {"lessons":{"crosscourt":{"streak":3,"attempts":3,"recentAttempts":[]},
      "downLine":{"streak":3,"attempts":3,"recentAttempts":[]},
      "shortAngle":{"streak":3,"attempts":3,"recentAttempts":[]}},"lastLesson":"shortAngle"}
      """
    let restored = try JSONDecoder().decode(DemoProgress.self, from: Data(old.utf8))
    XCTAssertEqual(restored.requiredMasteredCount, 3)
    XCTAssertEqual(restored.requiredRemaining, [.rallyRecovery, .recoverySplit])
    XCTAssertFalse(restored.unlocksCourt)
    XCTAssertEqual(restored.next, .rallyRecovery)
    XCTAssertFalse(restored.remaining.contains(.crosscourt))
  }

  func testPreviouslyEarnedMasteryRemainsCompleteWhenTargetIncreases() throws {
    let old = """
      {"lessons":{"crosscourt":{"streak":2,"attempts":2,"recentAttempts":[]},
      "downLine":{"streak":3,"attempts":3,"recentAttempts":[]},
      "shortAngle":{"streak":1,"attempts":1,"recentAttempts":[]}},"lastLesson":"crosscourt"}
      """
    let progress = try JSONDecoder().decode(DemoProgress.self, from: Data(old.utf8))
    for lesson in [DemoLesson.crosscourt, .downLine] {
      XCTAssertTrue(progress.mastery(lesson).isMastered)
      XCTAssertEqual(progress.mastery(lesson).completedAttempts, lesson == .crosscourt ? 2 : 3)
      XCTAssertFalse(progress.remaining.contains(lesson))
    }
    XCTAssertFalse(progress.mastery(.shortAngle).isMastered)
    XCTAssertEqual(progress.requiredMasteredCount, 2)
  }

  func testLearningFlowAdvancesAfterSixAttemptsSkipsMasteredAndIgnoresLateCallbacks() {
    var progress = DemoProgress()
    func succeed(_ lesson: DemoLesson) {
      progress.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: lesson)
    }
    for _ in 0..<6 { succeed(.slice) }
    var flow = DemoLessonFlow(first: .rallyRecovery)
    var visited: [DemoLesson] = []
    for _ in DemoLesson.allCases {
      guard let lesson = flow.current else { break }
      visited.append(lesson)
      XCTAssertFalse(flow.advance(after: lesson, progress: progress))
      for _ in 0..<5 {
        succeed(lesson)
        XCTAssertFalse(flow.advance(after: lesson, progress: progress), "Fewer than six attempts must not advance")
      }
      succeed(lesson)
      XCTAssertTrue(flow.advance(after: lesson, progress: progress))
      let next = flow.current
      // A Next tap and its outstanding automatic timer may both arrive.
      XCTAssertFalse(flow.advance(after: lesson, progress: progress))
      XCTAssertEqual(flow.current, next, "A stale callback must not skip or replace the new lesson")
    }
    XCTAssertEqual(visited, DemoLesson.allCases.filter { $0 != .slice })
    XCTAssertNil(flow.current)
    XCTAssertTrue(progress.unlocksCourt)
    XCTAssertTrue(progress.remaining.isEmpty)
  }

  func testEverySkillRequiresSixCleanAttemptsEvenAfterSavingPartialProgress() throws {
    var progress = DemoProgress()
    for lesson in DemoLesson.allCases {
      for attempt in 1...5 {
        progress.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: lesson)
        progress = try JSONDecoder().decode(DemoProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertFalse(progress.mastery(lesson).isMastered, "\(lesson) must remain unfinished at \(attempt)/6")
        XCTAssertEqual(progress.mastery(lesson).completedAttempts, attempt)
      }
    }
    XCTAssertFalse(progress.unlocksCourt)
    XCTAssertEqual(progress.remaining.count, DemoLesson.allCases.count)
    for lesson in DemoLesson.allCases {
      progress.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: lesson)
      XCTAssertTrue(progress.mastery(lesson).isMastered)
      XCTAssertEqual(progress.mastery(lesson).completedAttempts, 6)
    }
    let restored = try JSONDecoder().decode(DemoProgress.self, from: JSONEncoder().encode(progress))
    XCTAssertTrue(restored.remaining.isEmpty)
    XCTAssertTrue(restored.unlocksCourt)
  }

  func testGuestMergeNeverReplacesEarnedMasteryWithALargerUnfinishedStreak() throws {
    let legacy = try JSONDecoder().decode(DemoMastery.self,
      from: Data("{\"streak\":2,\"attempts\":2,\"recentAttempts\":[]}".utf8))
    var partial = DemoProgress()
    for _ in 0..<5 { partial.record(.init(id: UUID(), success: true, message: "", demonstration: false), lesson: .crosscourt) }
    var completed = DemoProgress()
    completed.lessons[DemoLesson.crosscourt.rawValue] = legacy
    for guestWasMastered in [false, true] {
      var archive = DemoProgressArchive()
      let owner = DemoProgressArchive.profile(for: "player")
      archive.profiles[DemoProgressArchive.guest] = guestWasMastered ? completed : partial
      archive.profiles[owner] = guestWasMastered ? partial : completed
      archive.claimGuest(for: owner)
      XCTAssertTrue(archive.profiles[owner]!.mastery(.crosscourt).isMastered)
    }
  }

  func testFirstSkillKeepsAllFourExchangesTwentyPercentFaster() throws {
    var engine = PracticeEngine(settings: .init())
    engine.beginShotDemo(.rallyRecovery, attempt: 0, demonstration: false)
    var seen = Set<Int>()
    for _ in 0..<7_200 where engine.demo?.result == nil {
      if seen.insert(engine.contactSerial).inserted {
        XCTAssertEqual(try XCTUnwrap(engine.flight).duration, 3.8 / 1.2, accuracy: 0.000001)
      }
      engine.performDemoScript()
      engine.step(1/120)
    }
    XCTAssertTrue(try XCTUnwrap(engine.demo?.result).success)
    XCTAssertEqual(seen.count, 8, "Four incoming balls and four outgoing returns must share the faster pace")
  }

  func testTrainingSpeedBuildsMonotonicallyToMatchTimingWithoutExceedingIt() {
    for match in [0.65, 0.95, 1.8, 2.65, 3.5] {
      for training in [3.2, 3.8] {
        var previous = Double.infinity
        for lesson in DemoLesson.allCases {
          let duration = DemoPace.duration(match: match, training: training, lesson: lesson)
          XCTAssertLessThanOrEqual(duration, previous + 0.000001)
          XCTAssertGreaterThanOrEqual(duration, match - 0.000001)
          if lesson == .rallyRecovery {
            XCTAssertEqual(duration, max(match, training / 1.2), accuracy: 0.000001)
          }
          previous = duration
        }
        XCTAssertEqual(previous, match, accuracy: 0.000001, "Last skill uses exact match timing")
      }
    }
  }

  func testServeReturnsUseProgressivePaceAndFinalServeKeepsActualMatchSpeed() throws {
    for lesson in [DemoLesson.firstReturn, .secondReturn, .serveWide, .serveCenter, .serveBody] {
      var engine = PracticeEngine(settings: .init())
      engine.beginShotDemo(lesson, attempt: 0, demonstration: false)
      if let target = engine.demo?.target {
        engine.aimServe(at: target, side: 0)
        engine.requestServe(0)
      }
      for _ in 0..<1_200 where engine.phase == .serving { engine.step(1/120) }
      let flight = try XCTUnwrap(engine.flight)
      var match = PracticeEngine(settings: engine.settings)
      match.players[flight.hitter].pos = flight.from
      match.launch(flight.hitter, aim: flight.landing, kind: flight.kind,
        serve: flight.serve, serveNumber: flight.serveNumber, stroke: flight.stroke)
      let matchDuration = try XCTUnwrap(match.flight).duration
      let expected = lesson.isReturn
        ? DemoPace.duration(match: matchDuration, training: 3.2, lesson: lesson) : matchDuration
      XCTAssertEqual(flight.duration, expected, accuracy: 0.000001, lesson.rawValue)
      engine.step(1/120)
      XCTAssertEqual(engine.flight?.duration, flight.duration, "Pace must be applied only once per flight")
    }
  }
}
