import Foundation

/// Animation coordinates are player-relative: +x is the right-handed player's forehand side.
/// The far-court figure mirrors those coordinates because it faces the opposite direction.
enum StrokeStance: Equatable { case forehand, backhand }
enum TennisStrokeStyle: String, Codable, Equatable { case groundstroke, volley, lob, serve, overhead, drop, slice }

struct StrokePose {
  var grip: Vec
  var racketAngle: Double
  var shoulderTurn: Double
  var kneeBend: Double
  var weightShift: Double
  var supportHandOnGrip: Bool

  // The racket model's string-bed centre is 19 points up from its grip.
  var racketCentre: Vec {
    Vec(x: grip.x - sin(racketAngle) * 19, y: grip.y + cos(racketAngle) * 19)
  }

  func blended(to next: StrokePose, amount: Double) -> StrokePose {
    let t = clamp(amount, 0, 1)
    return StrokePose(
      grip: Vec(x: grip.x + (next.grip.x - grip.x) * t, y: grip.y + (next.grip.y - grip.y) * t),
      racketAngle: racketAngle + (next.racketAngle - racketAngle) * t,
      shoulderTurn: shoulderTurn + (next.shoulderTurn - shoulderTurn) * t,
      kneeBend: kneeBend + (next.kneeBend - kneeBend) * t,
      weightShift: weightShift + (next.weightShift - weightShift) * t,
      supportHandOnGrip: t < 0.5 ? supportHandOnGrip : next.supportHandOnGrip)
  }
}

struct StrokeAnimation {
  private(set) var stance: StrokeStance = .forehand
  private(set) var style: TennisStrokeStyle = .groundstroke
  private(set) var timeAfterContact: Double?
  private(set) var timeUntilContact: Double?
  private var committed = false
  private(set) var contactReach = 30.0
  private var preparationStart: StrokePose?
  private var preparationRemaining: Double?

  static func lateralBallOffset(ballX: Double, playerX: Double, courtSide: Int) -> Double {
    (ballX - playerX) * (courtSide == 0 ? 1 : -1)
  }

  /// Predict the engine's first pre-bounce contact with its 0.9 m volley reach.
  /// Recomputed as the player moves, so the swing is ready before the ball reaches the body.
  static func volleyContactProgress(flight: BallFlight, player: Vec, side: Int) -> Double? {
    guard let window = BallContactWindow.volley(flight: flight, player: player, side: side),
      flight.progress <= window.exit
    else { return nil }
    return window.entry
  }

  var recoveryDuration: Double {
    style == .volley ? 0.30 : style == .serve ? 0.68 : 0.58
  }
  private var followThroughDuration: Double { style == .volley ? 0.10 : 0.20 }

  mutating func update(
    delta: Double, lateralBall: Double, arrival: Double?, incomingStyle: TennisStrokeStyle,
    reach: Double = 30
  ) {
    if let elapsed = timeAfterContact {
      let next = elapsed + max(0, delta)
      timeAfterContact = next
      if next < recoveryDuration {
        let windup = incomingStyle == .volley ? 0.30 : 0.65
        guard let arrival, arrival < windup, next >= followThroughDuration else { return }
        // Flow straight from follow-through into the next preparation when the ball is quick.
        preparationStart = pose
        preparationRemaining = max(0.001, arrival)
      } else {
        preparationStart = nil
        preparationRemaining = nil
      }
      timeAfterContact = nil
      committed = false
    }
    timeUntilContact = arrival
    guard let arrival else {
      committed = false
      preparationStart = nil
      preparationRemaining = nil
      return
    }
    style = incomingStyle
    if !committed {
      contactReach = clamp(reach, 0, 38)
      // A small dead band prevents flickering between poses as a player centres on the ball.
      if lateralBall < -0.12 {
        stance = .backhand
      } else if lateralBall > 0.12 {
        stance = .forehand
      }
      if arrival <= 0.12 { committed = true }
    }
  }

  mutating func hit(style: TennisStrokeStyle, elapsed: Double = 0) {
    self.style = style
    timeAfterContact = max(0, elapsed)
    timeUntilContact = nil
    preparationStart = nil
    preparationRemaining = nil
    committed = true
  }

  var readyPose: StrokePose {
    StrokePose(
      grip: Vec(x: 3, y: 26), racketAngle: -0.12, shoulderTurn: 0,
      kneeBend: 0.45, weightShift: 0, supportHandOnGrip: true)
  }

  var contactPose: StrokePose {
    if style == .serve || style == .overhead {
      return StrokePose(
        grip: Vec(x: 7, y: style == .overhead ? 47 : 43), racketAngle: -0.22, shoulderTurn: 0.22,
        kneeBend: 0, weightShift: 2, supportHandOnGrip: false)
    }
    let sign = stance == .forehand ? 1.0 : -1.0
    let volley = style == .volley
    let angle = -sign * min(volley ? 0.88 : 1.15, contactReach / 30 * 1.15)
    let centre = Vec(x: sign * contactReach, y: volley ? 40 : style == .drop ? 25 : style == .slice ? 29 : 31)
    return StrokePose(
      grip: Vec(x: centre.x + sin(angle) * 19, y: centre.y - cos(angle) * 19),
      racketAngle: angle,
      shoulderTurn: sign * 0.13, kneeBend: 0.3, weightShift: sign * 2.5,
      supportHandOnGrip: stance == .backhand)
  }

  var preparedPose: StrokePose {
    if style == .serve || style == .overhead {
      return StrokePose(
        grip: Vec(x: 12, y: 35), racketAngle: -2.65, shoulderTurn: -0.75,
        kneeBend: 0.95, weightShift: -3, supportHandOnGrip: false)
    }
    let sign = stance == .forehand ? 1.0 : -1.0
    if style == .drop || style == .slice {
      return StrokePose(grip: Vec(x: sign * 16, y: style == .drop ? 30 : 37),
        racketAngle: -sign * 0.3, shoulderTurn: -sign * 0.5,
        kneeBend: 0.7, weightShift: -sign * 1.5, supportHandOnGrip: false)
    }
    return StrokePose(
      grip: Vec(x: sign * 15, y: style == .volley ? 30 : 26),
      racketAngle: sign * (style == .volley ? -0.45 : -0.30),
      shoulderTurn: -sign * (style == .volley ? 0.28 : 0.85),
      kneeBend: 0.9, weightShift: -sign * 3,
      supportHandOnGrip: stance == .backhand)
  }

  var finishPose: StrokePose {
    if style == .serve || style == .overhead {
      return StrokePose(
        grip: Vec(x: -12, y: 23), racketAngle: 1.85, shoulderTurn: 0.65,
        kneeBend: 0.55, weightShift: 4, supportHandOnGrip: false)
    }
    let sign = stance == .forehand ? 1.0 : -1.0
    if style == .volley {
      return StrokePose(
        grip: Vec(x: sign * 14, y: 32), racketAngle: -sign * 1.15,
        shoulderTurn: sign * 0.25, kneeBend: 0.35, weightShift: sign * 3,
        supportHandOnGrip: stance == .backhand)
    }
    if style == .drop || style == .slice {
      return StrokePose(grip: Vec(x: sign * (style == .drop ? 16 : 23), y: 21),
        racketAngle: -sign * 1.0, shoulderTurn: sign * 0.28,
        kneeBend: 0.45, weightShift: sign * 2, supportHandOnGrip: false)
    }
    return StrokePose(
      grip: Vec(x: -sign * 9, y: style == .lob ? 41 : 35),
      racketAngle: sign * 0.85, shoulderTurn: sign * 0.75,
      kneeBend: 0.15, weightShift: sign * 4,
      supportHandOnGrip: stance == .backhand)
  }

  var pose: StrokePose {
    if let elapsed = timeAfterContact {
      let finishAt = followThroughDuration
      if elapsed < finishAt {
        // Fast through contact, then decelerate through the follow-through.
        let t = elapsed / finishAt
        return contactPose.blended(to: finishPose, amount: 1 - pow(1 - t, 3))
      }
      let t = (elapsed - finishAt) / (recoveryDuration - finishAt)
      return finishPose.blended(to: readyPose, amount: Self.ease(t))
    }
    guard let remaining = timeUntilContact else { return readyPose }
    let windup = style == .volley ? 0.30 : 0.65
    if remaining > 0.12 {
      let start = preparationRemaining ?? windup
      return (preparationStart ?? readyPose).blended(
        to: preparedPose,
        amount: Self.ease((start - remaining) / max(0.001, start - 0.12)))
    }
    // The forward swing starts BEFORE the physics contact, ending at the string bed at t=0.
    let shortPreparation = (preparationRemaining ?? windup) <= 0.12
    let startPose = shortPreparation ? (preparationStart ?? preparedPose) : preparedPose
    let duration = shortPreparation ? max(0.001, preparationRemaining ?? 0.12) : 0.12
    return startPose.blended(to: contactPose, amount: pow(clamp(1 - remaining / duration, 0, 1), 2))
  }

  static func ease(_ value: Double) -> Double {
    let t = clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
  }
}
