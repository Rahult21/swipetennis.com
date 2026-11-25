import XCTest

final class SwipeTennisUITests: XCTestCase {
  func testPracticeFlow() {
    let app = XCUIApplication()
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
    XCTAssertTrue(app.staticTexts["Take a breath."].waitForExistence(timeout: 3))
    app.buttons["startPractice"].tap()
    app.buttons["Leave practice"].tap()
    XCTAssertTrue(app.buttons["saveAndLeave"].waitForExistence(timeout: 3))
    app.buttons["Cancel"].tap()
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
