import XCTest

final class SwipeTennisUITests: XCTestCase {
  /// Finish a live point by returning playable balls until the highlight starts.
  private func playUntilHighlight(_ app: XCUIApplication, timeout: TimeInterval = 75) {
    let court = app.descendants(matching: .any)["livePracticeCourt"].firstMatch
    let end = Date().addingTimeInterval(timeout)
    while Date() < end && !app.buttons["Skip"].exists && !app.buttons["nextPracticePoint"].exists && !app.buttons["replayPracticePoint"].exists {
      if court.exists && court.value as? String == "Swipe to hit" {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.77))
        let finish = start.withOffset(CGVector(dx: -30, dy: -120))
        start.press(forDuration: 0.05, thenDragTo: finish)
      } else { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
    }
  }

  func testFullCourtAndPauseInBothOrientations() {
    let app = XCUIApplication()
    defer { XCUIDevice.shared.orientation = .portrait }
    for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
      XCUIDevice.shared.orientation = orientation
      app.launch()
      let quick = app.buttons["matchdayQuickMatch"]
      XCTAssertTrue(quick.waitForExistence(timeout: 15))
      quick.tap()
      // Hold the player's service turn so the result sheet cannot cover the
      // court during the orientation, framing and pause assertions.
      let next = app.buttons["nextPracticePoint"]
      XCTAssertTrue(next.waitForExistence(timeout:90))
      if orientation == .landscapeLeft {
        XCTAssertFalse(app.descendants(matching: .any)["pointCoachSummary"].exists)
        app.buttons["pointCoachDetails"].tap()
        XCTAssertTrue(app.navigationBars["Point details"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
      }
      next.tap()
      let pause = app.buttons["Pause practice"]
      XCTAssertTrue(pause.waitForExistence(timeout: 18))
      let court = app.descendants(matching: .any)["livePracticeCourt"].firstMatch
      XCTAssertTrue(court.exists)
      XCTAssertFalse(app.descendants(matching: .any)["practiceScoreboard"].exists)
      let settled = expectation(for: NSPredicate(format: "value == %@", "On court"), evaluatedWith: court)
      XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 30), .completed)
      let screen = XCUIScreen.main.screenshot()
      let photo = XCTAttachment(screenshot: screen)
      photo.name = orientation == .portrait ? "Full court portrait" : "Full court landscape"
      photo.lifetime = .keepAlways; add(photo)
      XCTAssertEqual(court.frame.width, app.frame.width, accuracy: 4)
      XCTAssertEqual(court.frame.height, app.frame.height, accuracy: 4)
      XCTAssertTrue(pause.isHittable)
      pause.tap()
      XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 8))
      XCTAssertTrue(app.navigationBars["Match paused"].exists)
      app.buttons["startPractice"].tap()
      XCTAssertTrue(pause.waitForExistence(timeout: 8))
      app.terminate()
    }
  }

  func testMatchdayLandscapeWarmupAndReturn() {
    let app = XCUIApplication()
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    app.launch()
    let warm = app.buttons["matchdayWarmup"]
    XCTAssertTrue(warm.waitForExistence(timeout: 15))
    XCTAssertTrue(warm.isHittable && app.buttons["matchdayQuickMatch"].isHittable)
    let home = XCTAttachment(screenshot: app.screenshot())
    home.name = "Matchday landscape"; home.lifetime = .keepAlways; add(home)
    warm.tap()
    app.buttons["Pause warm up"].tap()
    let close = app.buttons["Close warm up"]
    XCTAssertTrue(close.waitForExistence(timeout: 12))
    close.tap()
    XCTAssertTrue(warm.waitForExistence(timeout: 12))
  }

  func testMatchdayWarmupQuickMatchAndResume() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-matchdayMusic", "YES", "-sound", "YES"]
    app.launch()
    let music = app.buttons["lobbyBeat"]
    XCTAssertTrue(music.waitForExistence(timeout: 15))
    XCTAssertEqual(music.value as? String, "Off")
    music.tap()
    XCTAssertEqual(music.value as? String, "On")
    XCTAssertTrue(app.buttons["matchdayQuickMatch"].isHittable)
    app.buttons["matchdayWarmup"].tap()
    let feed = app.staticTexts["warmupFeed"]
    XCTAssertTrue(feed.waitForExistence(timeout: 12))
    XCTAssertEqual(feed.label, "Place your serve")
    if !app.buttons["warmupNext"].exists { app.buttons["Pause warm up"].tap() }
    app.buttons["warmupNext"].tap()
    XCTAssertEqual(feed.label, "Deep forehand")
    if !app.buttons["warmupNext"].exists { app.buttons["Pause warm up"].tap() }
    app.buttons["warmupNext"].tap()
    XCTAssertEqual(feed.label, "Short backhand")
    if !app.buttons["warmupNext"].exists { app.buttons["Pause warm up"].tap() }
    app.buttons["warmupNext"].tap()
    let pauseMatch = app.buttons["Pause practice"]
    XCTAssertTrue(pauseMatch.waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["startPractice"].exists)
    pauseMatch.tap()
    app.buttons["Leave practice"].tap()
    app.buttons["saveAndLeave"].tap()
    let resume = app.buttons["matchdayResume"]
    XCTAssertTrue(resume.waitForExistence(timeout: 12))
    XCTAssertTrue(resume.isHittable && app.buttons["matchdayWarmup"].isHittable && app.buttons["matchdayQuickMatch"].isHittable)
    let returning = XCTAttachment(screenshot: app.screenshot())
    returning.name = "Matchday with saved match"; returning.lifetime = .keepAlways; add(returning)
    app.terminate(); app.launch()
    XCTAssertTrue(resume.waitForExistence(timeout: 12))
    XCTAssertEqual(music.value as? String, "Off")
    resume.tap()
    XCTAssertTrue(pauseMatch.waitForExistence(timeout: 12))
    pauseMatch.tap()
    app.buttons["Leave practice"].tap()
    app.buttons["saveAndLeave"].tap()
    app.buttons["matchdayQuickMatch"].tap()
    XCTAssertTrue(pauseMatch.waitForExistence(timeout: 12))
    XCTAssertFalse(app.buttons["startPractice"].exists)
    pauseMatch.tap()
    app.buttons["Leave practice"].tap()
    app.buttons["Leave without saving"].tap()
    XCTAssertTrue(app.buttons["matchdayFilm"].waitForExistence(timeout: 12))
    XCTAssertFalse(resume.exists)
    let first = XCTAttachment(screenshot: app.screenshot())
    first.name = "Matchday first serve"; first.lifetime = .keepAlways; add(first)

  }

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
    let attempts = app.descendants(matching:.any)["practiceCompletedAttempts"].firstMatch
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
      // After dismissing the arena picker a partly clipped row can report hittable.
      // Keep its center below the navigation bar before sending the tap.
      let formTop = app.navigationBars.firstMatch.frame.maxY + 18
      for _ in 0..<5 where !quick.isHittable || quick.frame.midY < formTop { app.swipeDown() }
      if quick.isHittable { quick.tap() }
      else {
        for _ in 0..<6 where !take.isHittable { app.swipeUp() }
        XCTAssertTrue(take.isEnabled)
        take.tap()
      }
      let start = app.buttons["startPractice"]
      XCTAssertTrue(start.waitForExistence(timeout:15))
      start.tap()
      playUntilHighlight(app)
      let skip = app.buttons["Skip"]
      if skip.exists && skip.isHittable { skip.tap() }
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
      app.buttons["Pause practice"].tap()
      app.buttons["Leave practice"].tap()
      app.buttons["Leave without saving"].tap()
      XCTAssertTrue(app.navigationBars["Play & practice"].waitForExistence(timeout:12))
    }
  }

  func testPracticeFinishesWinnerWalkAndPlayerReplayAutomatically() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1","YES"]
    app.launch()
    app.buttons["playPractice"].tap()
    let quick = app.buttons["quickGuestPlay"]
    if quick.exists { quick.tap() } else { app.buttons["takeCourt"].tap() }
    let start = app.buttons["startPractice"]
    XCTAssertTrue(start.waitForExistence(timeout:20))
    start.tap()
    playUntilHighlight(app)
    let panel = app.staticTexts["playingHighlight"]
    XCTAssertTrue(panel.waitForExistence(timeout:70))
    let result = app.buttons["nextPracticePoint"]
    XCTAssertTrue(result.waitForExistence(timeout:15))
    XCTAssertFalse(app.buttons["Skip"].exists)
    app.buttons["replayPracticePoint"].tap()
    let contact = app.buttons["freezeContact"]
    XCTAssertTrue(contact.waitForExistence(timeout:20))
    contact.tap()
    let capture = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
    capture.name = "Stroke replay at contact in portrait"; capture.lifetime = .keepAlways; add(capture)
    XCTAssertTrue(app.buttons["replayCameraStroke"].isSelected)
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    XCTAssertTrue(contact.isHittable)
    let wide = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
    wide.name = "Stroke replay at contact in landscape"; wide.lifetime = .keepAlways; add(wide)
    app.buttons["Done"].tap()
    result.tap()
    XCTAssertFalse(app.buttons["replayPracticePoint"].exists)
  }

  func testLockerRoomChangesKitAndKeepsItWhenReopened() {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1", "YES"]
    app.launch()
    let locker = app.buttons["playerOutfits"]
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
    app.segmentedControls.buttons["Back"].tap()
    XCTAssertTrue(app.segmentedControls.buttons["Back"].isSelected)
    app.segmentedControls.buttons["Front"].tap()
    let skin = app.buttons["kitSkinTone"]
    if !skin.isHittable { app.swipeUp() }
    skin.tap()
    let choices = ["Porcelain", "Espresso"]
    let tone = choices.first { !preview.label.contains($0) }!
    app.buttons[tone].tap()
    XCTAssertTrue(preview.label.contains(tone))
    let bottoms = app.buttons["kitBottoms"]
    if !bottoms.isHittable { app.swipeUp() }
    bottoms.tap()
    app.buttons["Skort"].tap()
    for _ in 0..<3 where !preview.isHittable { app.swipeDown() }
    XCTAssertTrue(preview.label.contains("skort"))
    let front = NSPredicate(format:"value == %@", "Front view")
    expectation(for:front,evaluatedWith:preview)
    waitForExpectations(timeout:18)
    let photo = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    photo.name = "Player-kit"
    photo.lifetime = .keepAlways
    add(photo)
  }

  func testStudioCanRepeatServeAndFreezeTheLanding() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1","YES","-athleteModel","Man","-kitColor","Chalk",
                           "-kitShirt","Polo","-kitBottomColor","White","-kitProp","None","-kitSkin","Honey","-kitSkort","NO"]
    XCUIDevice.shared.orientation = .portrait
    app.launch()
    app.buttons["playerOutfits"].tap()
    app.buttons["strokeStudio"].tap()
    let court = app.descendants(matching:.any)["motionStudioCourt"].firstMatch
    let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Ready"),object:court)
    XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:35),.completed)
    let loop = app.buttons["studioRepeat"]
    loop.tap()
    XCTAssertTrue(loop.isSelected)
    XCTContext.runActivity(named:"Watch three complete service motions") { _ in
      let recording = expectation(description:"Playback crosses three loop boundaries")
      DispatchQueue.main.asyncAfter(deadline:.now()+10.2) { recording.fulfill() }
      wait(for:[recording],timeout:13)
      XCTAssertTrue(app.buttons["Pause stroke"].exists)
    }
    app.buttons["Finish"].tap()
    XCTAssertTrue(app.buttons["Play stroke"].exists)
    app.buttons["Contact"].tap()
    XCTAssertTrue(app.buttons["Share pose"].waitForExistence(timeout:15))
    let serve = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
    serve.name = "Match whites at contact"; serve.lifetime = .keepAlways; add(serve)
    let export = app.buttons["exportStudioMovie"]
    for _ in 0..<2 where !export.isHittable { app.swipeUp() }
    export.tap()
    XCTAssertTrue(app.buttons["shareStudioMovie"].waitForExistence(timeout:120))
    let movie = app.buttons["shareStudioMovie"]
    XCTAssertTrue(movie.isEnabled)
    // Switching stroke invalidates the exported movie from the previous selection.
    for shot in ["Run","Forehand","Backhand"] {
      let choice = app.buttons[shot]
      if !choice.isHittable { app.swipeDown() }
      choice.tap()
      XCTAssertFalse(movie.exists)
      if !export.isHittable { app.swipeUp() }
      export.tap()
      XCTAssertTrue(movie.waitForExistence(timeout:120),shot)
    }
  }

  func testStrokeStudioShowsBothAthletesAtContactAndFinish() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1","YES"]
    XCUIDevice.shared.orientation = .portrait
    app.launch()
    app.buttons["playerOutfits"].tap()
    func capture(_ name: String) {
      let photo = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
      photo.name = name; photo.lifetime = .keepAlways; add(photo)
    }
    for model in ["Man","Woman"] {
      let athlete = app.buttons[model]
      if !athlete.isHittable { app.swipeUp() }
      athlete.tap()
      let studio = app.buttons["strokeStudio"]
      if !studio.isHittable { app.swipeDown() }
      studio.tap()
      let court = app.descendants(matching:.any)["motionStudioCourt"].firstMatch
      XCTAssertTrue(court.waitForExistence(timeout:12))
      let rendered = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Ready"),object:court)
      XCTAssertEqual(XCTWaiter.wait(for:[rendered],timeout:30),.completed)
      func waitForFrame(_ key: String) {
        let drawn = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",key),object:court)
        XCTAssertEqual(XCTWaiter.wait(for:[drawn],timeout:20),.completed,key)
        XCTAssertTrue(app.buttons["Share pose"].exists)
        // Check the displayed Metal surface, not just the offscreen snapshot.
        let image = court.screenshot().image.cgImage!
        var rgb = [UInt8](repeating:0,count:24*24*4)
        let nonSky = rgb.withUnsafeMutableBytes { bytes -> Int in
          guard let buffer = CGContext(data:bytes.baseAddress,width:24,height:24,bitsPerComponent:8,bytesPerRow:96,
              space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { return 0 }
          buffer.draw(image,in:CGRect(x:0,y:0,width:24,height:24))
          let pixels = bytes.bindMemory(to:UInt8.self)
          return stride(from:0,to:pixels.count,by:4).filter { pixels[$0]<125 && pixels[$0+1]<165 }.count
        }
        XCTAssertGreaterThan(nonSky,40,"The actual court must be visible "+key)
      }
      app.buttons["Contact"].tap()
      waitForFrame("Serve-Back-Contact")
      capture(model+" serve at contact")
      app.buttons["Side"].tap()
      app.buttons["Load"].tap()
      waitForFrame("Serve-Side-Load")
      capture(model+" trophy from side")
      for stroke in ["Forehand","Backhand","Volley"] {
        app.buttons[stroke].tap()
        app.buttons["Contact"].tap()
        XCTAssertTrue(app.buttons["Play stroke"].exists)
        app.buttons["Finish"].tap()
        waitForFrame(stroke+"-Side-Finish")
        capture(model+" "+stroke+" finish")
      }
      app.navigationBars.buttons.element(boundBy:0).tap()
    }
  }

  func testRepeatingServePresentsDistinctAthletePoses() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1","YES"]
    XCUIDevice.shared.orientation = .portrait
    app.launch()
    app.buttons["playerOutfits"].tap()
    app.buttons["strokeStudio"].tap()
    let court = app.descendants(matching:.any)["motionStudioCourt"].firstMatch
    let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Ready"),object:court)
    XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:30),.completed)
    app.buttons["studioRepeat"].tap()
    var previous = [UInt8](), changes = 0
    let deadline = Date.now.addingTimeInterval(6)
    while Date.now < deadline && changes < 5 {
      let frame = try XCTUnwrap(court.screenshot().image.cgImage)
      // In the behind-server view this crop contains the legs, shirt and racket.
      // Excluding the timeline prevents the slider alone from passing the test.
      let crop = try XCTUnwrap(frame.cropping(to:CGRect(x:Double(frame.width)*0.23,y:Double(frame.height)*0.24,
        width:Double(frame.width)*0.54,height:Double(frame.height)*0.65)))
      var pixels = [UInt8](repeating:0,count:32*40*4)
      pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data:buffer.baseAddress,width:32,height:40,bitsPerComponent:8,bytesPerRow:128,
          space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.draw(crop,in:CGRect(x:0,y:0,width:32,height:40))
      }
      if !previous.isEmpty {
        let changedPixels = stride(from:1,to:pixels.count,by:4).filter { abs(Int(pixels[$0])-Int(previous[$0])) > 18 }
        if changedPixels.count >= 12 { changes += 1 }
      }
      previous = pixels
      Thread.sleep(forTimeInterval:0.14)
    }
    XCTAssertGreaterThanOrEqual(changes,5,"The visible athlete should change pose through the service loop.")
  }

  func testLandscapeStrokeStudioFitsAthleteAndContactControls() {
    let app = XCUIApplication()
    app.launchArguments = ["-watchedQuickStartV1","YES"]
    XCUIDevice.shared.orientation = .portrait
    defer { XCUIDevice.shared.orientation = .portrait }
    app.launch()
    app.buttons["playerOutfits"].tap()
    app.buttons["strokeStudio"].tap()
    let court = app.descendants(matching:.any)["motionStudioCourt"].firstMatch
    let ready = XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@", "Ready"),object:court)
    XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:30),.completed)
    XCUIDevice.shared.orientation = .landscapeLeft
    let control = app.buttons["Contact"]
    let rotated = XCTNSPredicateExpectation(predicate:NSPredicate(format:"hittable == true"),object:control)
    XCTAssertEqual(XCTWaiter.wait(for:[rotated],timeout:10),.completed)
    XCTAssertGreaterThan(control.frame.minX,court.frame.maxX)
    XCTAssertLessThan(court.frame.maxY,app.tabBars.firstMatch.frame.minY)
    app.buttons["Side"].tap()
    for phase in ["Load", "Contact", "Finish"] {
      app.buttons[phase].tap()
      let displayed = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "value == %@", "Serve-Side-" + phase), object: court)
      XCTAssertEqual(XCTWaiter.wait(for: [displayed], timeout: 20), .completed)
      XCTAssertTrue(app.buttons["Share pose"].exists)
      let image = XCTAttachment(screenshot: court.screenshot())
      image.name = "Landscape serve " + phase
      image.lifetime = .keepAlways
      add(image)
    }
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
    let film = app.buttons["matchdayFilm"]
    XCTAssertTrue(film.waitForExistence(timeout: 12))
    film.tap()
    let done = app.buttons["closeQuickStart"]
    XCTAssertTrue(done.waitForExistence(timeout: 15))
    for title in ["Move to the return", "Drive a deep forehand", "Play a shorter backhand", "Place your serve"] {
      app.buttons[title].tap()
      XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout:3))
    }
    done.tap()
    if !app.buttons["playPractice"].isHittable { app.swipeDown() }
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
    let playing = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:start)
    XCTAssertEqual(XCTWaiter.wait(for:[playing],timeout:10),.completed)
    capture("Landscape-rally")
    playUntilHighlight(app)
    let skip = app.buttons["Skip"]
    XCTAssertTrue(skip.waitForExistence(timeout: 35))
    XCTAssertTrue(app.staticTexts["playingHighlight"].waitForExistence(timeout: 10))
    capture("Winning-shot")
    if skip.exists && skip.isHittable { skip.tap() }
    XCUIDevice.shared.orientation = .portrait
    // Review the completed point from the result card.
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
    let loop = app.buttons["loopContact"]
    loop.tap()
    XCTAssertTrue(loop.isSelected)
    XCTAssertTrue(app.buttons["Pause replay"].exists)
    app.buttons["freezeContact"].tap()
    XCTAssertFalse(loop.isSelected)
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
    let draw = app.buttons.containing(.staticText,identifier:env["TOUR_TEST_TITLE"] ?? "Replay test").firstMatch
    for _ in 0..<6 where !draw.isHittable { app.swipeUp() }
    XCTAssertTrue(draw.isHittable)
    draw.tap()
    let play = app.buttons["playCupMatch"]
    for _ in 0..<5 where !play.isHittable { app.swipeUp() }
    play.tap()
    let ready = app.buttons["I'm ready to play"]
    XCTAssertTrue(ready.waitForExistence(timeout:12)); ready.tap()
    let automatic = app.buttons["Skip"]
    XCTAssertTrue(automatic.waitForExistence(timeout:50))
    if automatic.isHittable { automatic.tap() }
    let replay = app.buttons["replayCupPoint"]
    let accessible = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND hittable == true"),object:replay)
    XCTAssertEqual(XCTWaiter.wait(for:[accessible],timeout:30),.completed)
    replay.tap()
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
      for _ in 0..<5 where !next.isHittable { app.swipeUp() }
      XCTAssertTrue(next.isHittable)
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
    pause.tap()
    app.buttons["Leave practice"].tap()
    XCTAssertTrue(app.buttons["saveAndLeave"].waitForExistence(timeout: 3))
    app.buttons["stayOnCourt"].tap()
    pause.tap()
    app.buttons["Leave practice"].tap()
    app.buttons["saveAndLeave"].tap()
    XCTAssertTrue(app.buttons["resumeSavedMatch"].waitForExistence(timeout: 5))
    app.buttons["resumeSavedMatch"].tap()
    let pauseMatch = app.buttons["Pause practice"]
    XCTAssertTrue(pauseMatch.waitForExistence(timeout: 5))
    pauseMatch.tap()
    app.buttons["Leave practice"].tap()
    app.buttons["Leave without saving"].tap()
    XCTAssertTrue(app.buttons["takeCourt"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["resumeSavedMatch"].exists)
  }
  func testManualMatchAndRelaunch() {
    let app = XCUIApplication()
    app.launchArguments += ["-watchedQuickStartV1", "YES"]
    app.launch()
    app.tabBars.buttons["Score"].tap()
    let one = app.textFields["playerOne"]
    if !one.waitForExistence(timeout:5) {
      let end = app.buttons["End this match"]
      for _ in 0..<6 where !end.isHittable { app.swipeUp() }
      XCTAssertTrue(end.isHittable)
      end.tap()
      app.buttons["Save & close match"].tap()
    }
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
