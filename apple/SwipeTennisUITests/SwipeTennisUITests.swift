import XCTest

final class SwipeTennisUITests: XCTestCase {
  func testTacticsPracticeModesReturnToSetup() {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1", "YES"]
    app.launch()
    app.buttons["playPractice"].tap()
    for mode in ["Serve + 1", "Net positioning"] {
      let modeButton = app.buttons[mode]
      for _ in 0..<3 where !modeButton.isHittable { app.swipeUp() }
      modeButton.tap()
      let play = app.buttons["startTacticalAttempt"]
      for _ in 0..<2 where !play.isHittable { app.swipeUp() }
      XCTAssertTrue(play.waitForExistence(timeout:5))
      play.tap()
      let done = app.buttons["Done"]
      XCTAssertTrue(done.waitForExistence(timeout:10))
      done.tap()
      XCTAssertTrue(app.navigationBars["Play & practice"].waitForExistence(timeout:8))
    }
  }

  func testCompletedNetAttemptsSurviveLeavingPractice() {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1", "YES"]
    app.launch()
    app.buttons["playPractice"].tap()
    let net = app.buttons["Net positioning"]
    for _ in 0..<4 where !net.isHittable { app.swipeUp() }
    net.tap()
    let play = app.buttons["startTacticalAttempt"]
    for _ in 0..<3 where !play.isHittable { app.swipeUp() }
    play.tap()
    let retry = app.buttons["Try again"]
    XCTAssertTrue(retry.waitForExistence(timeout:45))
    retry.tap()
    XCTAssertTrue(app.staticTexts["Last attempt"].waitForExistence(timeout:5))
    app.buttons["Done"].tap()
    net.tap()
    let attempts = app.staticTexts["Completed attempts"]
    for _ in 0..<4 where !attempts.isHittable { app.swipeUp() }
    XCTAssertTrue(attempts.isHittable)
  }

  func testAllFourVenuesPlayThroughContactReview() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1", "YES"]
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    app.launch()
    app.buttons["playPractice"].tap()
    for venue in ["Linden Gardens · Grass", "Copper Terraces · Clay", "Harbor Glass · Hard", "Midnight Pier · Hard"] {
      let arena = app.buttons["chooseArena"]
      for _ in 0..<5 where !arena.isHittable { app.swipeUp() }
      arena.tap()
      app.buttons[venue].tap()
      let quick = app.buttons["quickGuestPlay"]
      let take = app.buttons["takeCourt"]
      for _ in 0..<5 where !quick.isHittable { app.swipeDown() }
      if quick.isHittable { quick.tap() }
      else {
        for _ in 0..<6 where !take.isHittable { app.swipeUp() }
        XCTAssertTrue(take.isEnabled)
        take.tap()
      }
      let start = app.buttons["startPractice"]
      XCTAssertTrue(start.waitForExistence(timeout:15))
      start.tap()
      let replay = app.buttons["replayPracticePoint"]
      XCTAssertTrue(replay.waitForExistence(timeout:75))
      replay.tap()
      let contact = app.buttons["freezeContact"]
      XCTAssertTrue(contact.waitForExistence(timeout:20))
      contact.tap()
      let camera = app.buttons["replayCameraOpponent"]
      camera.tap()
      let photo = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
      photo.name = venue + " at contact"; photo.lifetime = .keepAlways; add(photo)
      XCTAssertTrue(app.buttons["Play replay"].exists)
      app.buttons["Done"].tap()
      app.buttons["nextPracticePoint"].tap()
      app.buttons["Leave practice"].tap()
      app.buttons["Leave without saving"].tap()
      XCTAssertTrue(app.navigationBars["Play & practice"].waitForExistence(timeout:12))
    }
  }

  func testLockerRoomChangesKitAndKeepsItWhenReopened() {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1", "YES"]
    app.launch()
    let locker = app.buttons["Player & kit"]
    XCTAssertTrue(locker.waitForExistence(timeout: 10))
    locker.tap()
    let woman = app.buttons["Woman"]
    let man = app.buttons["Man"]
    XCTAssertTrue(woman.waitForExistence(timeout: 8))
    let selected = woman.isSelected ? man : woman
    selected.tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    locker.tap()
    XCTAssertTrue(selected.isSelected)
    let preview = app.descendants(matching:.any)["kitPreview"].firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout:8))
    let side = app.buttons["Side"]
    side.tap()
    XCTAssertTrue(side.isSelected)
    let sideReady = NSPredicate(format:"value == %@", "Side view")
    expectation(for:sideReady,evaluatedWith:preview)
    waitForExpectations(timeout:18)
    app.buttons["Back"].tap()
    XCTAssertTrue(app.buttons["Back"].isSelected)
    app.buttons["Front"].tap()
    let skin = app.buttons["kitSkinTone"]
    skin.tap()
    let choices = ["Porcelain", "Espresso"]
    let tone = choices.first { !preview.label.contains($0) }!
    app.buttons[tone].tap()
    XCTAssertTrue(preview.label.contains(tone))
    let front = NSPredicate(format:"value == %@", "Front view")
    expectation(for:front,evaluatedWith:preview)
    waitForExpectations(timeout:18)
    let photo = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    photo.name = "Player-kit"
    photo.lifetime = .keepAlways
    add(photo)
  }

  func testCareerResumesAtSavedPointAfterQuickPlay() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-watchedQuickStartV1", "YES"]
    app.launch()
    let career = app.buttons["soloCareer"]
    XCTAssertTrue(career.waitForExistence(timeout: 10))
    career.tap()
    let play = app.buttons["playCareerGame"]
    guard play.waitForExistence(timeout: 5) else { throw XCTSkip("The club chapter is already complete on this simulator.") }
    play.tap()
    let start = app.buttons["startPractice"]
    if start.waitForExistence(timeout: 3) { start.tap() }
    let next = app.buttons["nextPracticePoint"]
    XCTAssertTrue(next.waitForExistence(timeout: 35))
    let savedScore = app.staticTexts["resultScore"].label
    XCTAssertFalse(savedScore.isEmpty)
    app.terminate()
    app.launch()
    app.buttons["playPractice"].tap()
    let quick = app.buttons["quickGuestPlay"]
    if quick.exists { quick.tap() } else { app.buttons["takeCourt"].tap() }
    XCTAssertTrue(start.waitForExistence(timeout: 8))
    start.tap()
    XCTAssertTrue(next.waitForExistence(timeout: 35))
    app.terminate()
    app.launch()
    XCTAssertTrue(career.label.contains("Continue Career"))
    career.tap()
    XCTAssertTrue(play.label.contains("Resume game"))
    play.tap()
    XCTAssertTrue(next.waitForExistence(timeout: 10))
    XCTAssertEqual(app.staticTexts["resultScore"].label, savedScore)
  }

  func testQuickStartRotationAndWinningShotReplay() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1", "NO"]
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    app.launch()
    let done = app.buttons["closeQuickStart"]
    XCTAssertTrue(done.waitForExistence(timeout: 15))
    done.tap()
    app.buttons["playPractice"].tap()
    let quick = app.buttons["quickGuestPlay"]
    guard quick.waitForExistence(timeout:5) else { throw XCTSkip("This simulator profile already mastered the academy.") }
    quick.tap()
    let start = app.buttons["startPractice"]
    XCTAssertTrue(start.waitForExistence(timeout:8))
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    capture("Portrait-ready")
    XCUIDevice.shared.orientation = .landscapeLeft
    capture("Landscape-ready")
    start.tap()
    capture("Landscape-rally")
    let skip = app.buttons["Skip"]
    XCTAssertTrue(skip.waitForExistence(timeout: 35))
    XCTAssertTrue(app.staticTexts["playingHighlight"].waitForExistence(timeout: 10))
    capture("Winning-shot")
    if skip.exists && skip.isHittable { skip.tap() }
    XCUIDevice.shared.orientation = .portrait
    // The far player serves first. Let the serve pass to reach the real result card.
    let replay = app.buttons["replayPracticePoint"]
    XCTAssertTrue(replay.waitForExistence(timeout:30))
    replay.tap()
    XCTAssertTrue(app.buttons["replayCameraNeutral"].waitForExistence(timeout:15))
    app.buttons["replayCameraNeutral"].tap()
    app.buttons["freezeContact"].tap()
    XCTAssertTrue(app.buttons["Play replay"].exists)
    let atContact = app.staticTexts["replayTime"].label
    if app.buttons["freezeBounce"].exists {
      app.buttons["freezeBounce"].tap()
      XCTAssertNotEqual(app.staticTexts["replayTime"].label,atContact)
    }
    XCTAssertTrue(app.buttons["Share highlight"].exists)
    app.buttons["Replay the decision"].tap()
    XCTAssertTrue(app.staticTexts["At your opponent’s contact"].waitForExistence(timeout:5))
    app.buttons["Frozen 3D view"].tap()
    app.buttons["Done"].firstMatch.tap()
    XCTAssertTrue(app.buttons["replayCameraNeutral"].waitForExistence(timeout:5))
    app.buttons["Done"].tap()
    XCTAssertTrue(replay.waitForExistence(timeout:8))
    let retry = app.buttons["Retry this ball"]
    if retry.exists {
      let saved = app.staticTexts["resultScore"].label
      retry.tap()
      app.buttons["startTacticalAttempt"].tap()
      app.buttons["Done"].tap()
      XCTAssertTrue(replay.waitForExistence(timeout:8))
      XCTAssertEqual(app.staticTexts["resultScore"].label,saved)
    }
  }
  func testTournamentPointReplay() throws {
    let env = ProcessInfo.processInfo.environment
    guard let token = env["TOUR_TEST_TOKEN"], let user = env["TOUR_TEST_USER"] else {
      throw XCTSkip("Requires a local Worker cup fixture.")
    }
    let app = XCUIApplication()
    app.launchArguments += ["-watchedQuickStartV1", "YES"]
    app.launchEnvironment = ["SWIPETENNIS_LOCAL_TEST_URL":"http://127.0.0.1:8788/api/",
      "SWIPETENNIS_LOCAL_TEST_USER":user,"SWIPETENNIS_LOCAL_TEST_TOKEN":token]
    app.launch()
    app.buttons["quickCup"].tap()
    let draw = app.buttons.containing(.staticText,identifier:"Replay test").firstMatch
    for _ in 0..<6 where !draw.isHittable { app.swipeUp() }
    XCTAssertTrue(draw.isHittable)
    draw.tap()
    let play = app.buttons["playCupMatch"]
    for _ in 0..<5 where !play.isHittable { app.swipeUp() }
    play.tap()
    let ready = app.buttons["I'm ready to play"]
    XCTAssertTrue(ready.waitForExistence(timeout:12)); ready.tap()
    let replay = app.buttons["replayCupPoint"]
    XCTAssertTrue(replay.waitForExistence(timeout:30)); replay.tap()
    XCTAssertTrue(app.buttons["replayCameraNeutral"].waitForExistence(timeout:15))
    app.buttons["replayCameraNeutral"].tap()
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Next point"].isEnabled)
    XCTAssertTrue(replay.exists)
  }
  func testPracticeFlow() {
    let app = XCUIApplication()
    app.launchArguments += ["-watchedQuickStartV1", "YES"]
    app.launch()
    app.buttons["playPractice"].tap()
    app.swipeUp()
    app.swipeUp()
    let court = app.buttons["takeCourt"]
    XCTAssertTrue(court.waitForExistence(timeout: 5))
    if !court.isEnabled {
      // New players must learn the required skills before match play is available.
      app.swipeDown()
      app.swipeDown()
      let demo = app.buttons["unlockCourtDemo"]
      XCTAssertTrue(demo.waitForExistence(timeout: 5))
      demo.tap()
      let next = app.buttons["continueShotDemo"]
      XCTAssertTrue(next.waitForExistence(timeout: 5))
      next.tap()
      XCTAssertTrue(app.buttons["tryDemoShot"].waitForExistence(timeout: 5))
      app.buttons["Done"].tap()
      return
    }
    court.tap()
    let start = app.buttons["startPractice"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()
    let pause = app.buttons["Pause practice"]
    XCTAssertTrue(pause.waitForExistence(timeout: 5))
    pause.tap()
    XCTAssertTrue(app.staticTexts["Match paused"].waitForExistence(timeout: 3))
    app.buttons["startPractice"].tap()
    app.buttons["Leave practice"].tap()
    XCTAssertTrue(app.buttons["saveAndLeave"].waitForExistence(timeout: 3))
    app.buttons["stayOnCourt"].tap()
    app.buttons["Leave practice"].tap()
    app.buttons["saveAndLeave"].tap()
    XCTAssertTrue(app.buttons["resumeSavedMatch"].waitForExistence(timeout: 5))
    app.buttons["resumeSavedMatch"].tap()
    let leave = app.buttons["Leave practice"]
    XCTAssertTrue(leave.waitForExistence(timeout: 5))
    leave.tap()
    app.buttons["Leave without saving"].tap()
    XCTAssertTrue(app.buttons["takeCourt"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["resumeSavedMatch"].exists)
  }
  func testManualMatchAndRelaunch() {
    let app = XCUIApplication()
    app.launchArguments += ["-watchedQuickStartV1", "YES"]
    app.launch()
    app.tabBars.buttons["Score"].tap()
    if app.buttons["End this match"].exists {
      app.buttons["End this match"].tap()
      app.buttons["Save & close match"].tap()
    }
    let one = app.textFields["playerOne"]
    XCTAssertTrue(one.waitForExistence(timeout: 5))
    one.tap()
    one.typeText("Alex")
    let two = app.textFields["playerTwo"]
    two.tap()
    two.typeText("Sam")
    app.swipeUp()
    let start = app.buttons["startMatch"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    start.tap()
    app.segmentedControls.buttons["Manual"].tap()
    app.buttons["Ace"].tap()
    XCTAssertTrue(app.staticTexts["15"].exists)
    app.terminate()
    app.launch()
    app.tabBars.buttons["Score"].tap()
    XCTAssertTrue(app.staticTexts["15"].waitForExistence(timeout: 5))
    app.swipeUp()
    app.buttons["Undo"].tap()
  }
}
