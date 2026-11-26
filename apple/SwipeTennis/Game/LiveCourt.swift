import RealityKit
import SpriteKit
import SwiftUI

/// One simulation drives the live athlete rigs, the recorded point and the touch overlay.
struct LiveCourt: UIViewRepresentable {
  let scene: TennisScene
  var paused = false

  final class Container: UIView {
    let stadium: CourtReplayView
    let controls = SKView()
    init(scene: TennisScene) {
      stadium = CourtReplayView(surface:scene.engine.settings.surface,venue:scene.engine.settings.matchVenue,localSide:scene.perspectiveSide)
      super.init(frame:.zero)
      addSubview(stadium); addSubview(controls)
      controls.allowsTransparency = true
      controls.isOpaque = false
      controls.backgroundColor = .clear
      controls.preferredFramesPerSecond = 60
      scene.stadium = stadium
      controls.presentScene(scene)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
      super.layoutSubviews()
      stadium.frame = bounds; controls.frame = bounds
    }
  }
  func makeUIView(context: Context) -> Container { Container(scene:scene) }
  func updateUIView(_ view: Container, context: Context) { view.controls.isPaused = paused }
  static func dismantleUIView(_ view: Container, coordinator: ()) {
    (view.controls.scene as? TennisScene)?.stadium = nil
    view.controls.presentScene(nil)
    view.stadium.scene.anchors.removeAll()
  }
}

struct KitPreview: UIViewRepresentable {
  func makeUIView(context: Context) -> CourtReplayView {
    let view = CourtReplayView(surface:.grass, studio:true)
    var game = PracticeEngine(settings:.init())
    game.players[0].pos = Vec(x:4.115,y:24.6); game.players[0].destination = game.players[0].pos
    var performance = CourtPerformance(game:game)
    performance.update(game:game,dt:0,reduceMotion:true)
    if let frame = performance.frame { view.draw(frame,angle:.neutral,reduceMotion:true,powerBeat:nil) }
    view.portraitCamera()
    return view
  }
  func updateUIView(_ view: CourtReplayView, context: Context) {}
}
