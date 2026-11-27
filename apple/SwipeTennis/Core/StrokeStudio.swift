import Foundation

/// Examples are recorded through the match engine and its actual footwork and racket solver.
/// Changing a stroke in gameplay therefore also changes the locker room demonstration.
enum StudioStroke: String, CaseIterable {
  case serve = "Serve", forehand = "Forehand", backhand = "Backhand", volley = "Volley"

  var cue: String {
    switch self {
    case .serve: return "Watch the tossing shoulder rise, then the racket climb through contact."
    case .forehand: return "Watch the outside leg load and the hitting shoulder turn through the ball."
    case .backhand: return "Watch the right shoulder turn toward the net before both hands drive forward."
    case .volley: return "Watch the step toward the ball and the short punch in front of the body."
    }
  }
}

struct StrokeStudioClip {
  let recording: PointReplay
  let start, impact, end: Double
  var duration: Double { end-start }
  var contactTime: Double { impact-start }
  func frame(_ time: Double) -> RallyFrame? { recording.frame(at:start+clamp(time,0,duration)) }

  init?(_ stroke: StudioStroke) {
    var game: PracticeEngine
    if stroke == .serve {
      game = TrainingFeed.serve(.wide,surface:.hard)
      game.servePreparation?.requested = true
    } else {
      game = PracticeEngine(settings:.init(local:true,surface:.hard,allCourtTraining:false))
      game.phase = .live
      let net = stroke == .volley
      let side = stroke == .backhand ? -1.0 : 1.0
      game.players[0].pos = Vec(x:4.115,y:net ? 15.6 : 22.6)
      game.players[1].pos = Vec(x:4.115,y:1)
      for i in 0...1 { game.players[i].destination = game.players[i].pos }
      game.launch(1,aim:Vec(x:4.115+side*(net ? 0.68 : 0.43),y:net ? 20.8 : 21.5),kind:.cross)
    }
    var performance = CourtPerformance(game:game)
    var strike: RecordedStrike?
    for _ in 0..<900 {
      game.step(PointReplay.tick,random:{0.8})
      performance.update(game:game,dt:PointReplay.tick)
      if strike == nil { strike = performance.replay.strikes.last(where:{$0.hitter == 0}) }
      if let strike, performance.replay.duration >= strike.time+0.66 { break }
    }
    guard let strike else { return nil }
    recording = performance.replay
    impact = strike.time
    start = max(0,impact-(stroke == .serve ? 0.90 : 0.66))
    end = min(recording.duration,impact+0.63)
  }
}
