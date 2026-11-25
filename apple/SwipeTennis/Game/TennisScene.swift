import GameController
import SpriteKit
import SwiftUI

@MainActor final class PracticeSession: ObservableObject {
  @Published var snapshot: PracticeEngine
  @Published var paused = false
  @Published var coachMiss: CoachMiss?
  let scene: TennisScene
  private var inventoryKey: String?
  init(engine: PracticeEngine) {
    snapshot = engine
    scene = TennisScene(settings: engine.settings)
    scene.engine = engine
    scene.restorePresentation()
    scene.publish = { [weak self] engine in
      guard let self else { return }
      if snapshot.inventory != engine.inventory, let key = inventoryKey,
        let data = try? JSONEncoder().encode(engine.inventory) {
        UserDefaults.standard.set(data, forKey: key)
      }
      snapshot = engine
    }
    scene.publishCoachMiss = { [weak self] miss in self?.coachMiss = miss }
  }
  func restoreInventory(owner: String?) {
    guard inventoryKey == nil, !scene.engine.settings.local, let owner else { return }
    let key = "matchPowers." + owner
    inventoryKey = key
    if scene.engine.phase == .ready, let data = UserDefaults.standard.data(forKey: key),
      let saved = try? JSONDecoder().decode(PowerInventory.self, from: data) {
      scene.engine.inventory = saved
    }
  }
  func start(owner: String, slot: PracticeMatchSlot) throws {
    var next = scene.engine
    if next.phase == .finished {
      next = PracticeEngine(settings: next.settings)
      next.inventory = scene.engine.inventory
    }
    guard next.phase == .ready || next.phase == .point else { return }
    next.start()
    try slot.save(next, owner: owner)
    scene.engine = next
    paused = false
    scene.suspended = false
    scene.resetRallyPresentation()
    snapshot = scene.engine
    scene.resetClock()
    scene.configureMotion()
  }
  func pause() {
    paused = true
    scene.suspended = true
    scene.resetClock()
    Immersion.shared.stop()
  }
  func resume() {
    paused = false
    scene.suspended = false
    scene.resetClock()
    scene.configureMotion()
  }
  func choose(_ side: Int, _ kind: ShotKind) {
    scene.engine.choose(side, kind)
    snapshot = scene.engine
  }
  func restart() {
    let inventory = scene.engine.inventory
    scene.engine = PracticeEngine(settings: snapshot.settings)
    scene.engine.inventory = inventory
    scene.resetRallyPresentation()
    snapshot = scene.engine
    paused = false
    scene.suspended = false
    scene.resetClock()
  }
}
@MainActor final class TennisScene: SKScene {
  var engine: PracticeEngine
  var publish: ((PracticeEngine) -> Void)?
  var publishCoachMiss: ((CoachMiss?) -> Void)?
  private var missPresentation = CoachMissPresentation()
  private let missedOpportunityRing = SKShapeNode(ellipseOf: CGSize(width: 43, height: 15))
  private let courtReaction = CourtReaction()
  var suspended = false
  private let world = SKNode(), marks = SKNode(), dynamic = SKNode()
  private var actors: [PlayerFigure] = []
  private var observedContactSerial = 0
  private var animationTime = 0.0
  private let ballNode = SKShapeNode(circleOfRadius: 4),
    shadow = SKShapeNode(ellipseOf: CGSize(width: 9, height: 4))
  private let contactRings = (0..<2).map { _ in SKShapeNode(circleOfRadius: 13) }
  private let recoveryRings = (0..<2).map { _ in SKShapeNode(circleOfRadius: 19) }
  private let splitRings = (0..<2).map { _ in SKShapeNode(ellipseOf: CGSize(width: 32, height: 12)) }
  private let targetRing = SKShapeNode(circleOfRadius: 8)
  private let serveRing = SKShapeNode(circleOfRadius: 12)
  private let servePath = SKShapeNode()
  private let faultRing = SKShapeNode(circleOfRadius: 12)
  private struct ServeTouch {
    let start: CGPoint
    var dragging = false
  }
  private var serveTouches: [UITouch: ServeTouch] = [:]
  private var affirmationTouches: [UITouch: CGPoint] = [:]
  private let approachPath = SKShapeNode(), openCourt = SKShapeNode()
  private let followLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
  private let openLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
  private var swipeCoach = SwipeCoach()
  private let swipeHand = SKSpriteNode()
  private let swipeTouch = SKShapeNode(circleOfRadius: 6)
  private let demoGesturePath = SKShapeNode()
  private let trail = SKShapeNode()
  private var trails: [CGPoint] = []
  private var previousTime: TimeInterval = 0, accumulator = 0.0, publishAt = 0.0
  private var touchGestures: [UITouch: PracticeGesture] = [:]
  private var keyboardMoving = [false, false]
  var reduceMotion = false
  init(settings: PracticeSettings) {
    engine = PracticeEngine(settings: settings)
    super.init(size: CGSize(width: 390, height: 520))
    scaleMode = .resizeFill
  }
  required init?(coder: NSCoder) { fatalError("Use init(settings:)") }
  func resetClock() {
    previousTime = 0
    accumulator = 0
    touchGestures.removeAll()
    serveTouches.removeAll()
    affirmationTouches.removeAll()
    keyboardMoving = [false, false]
  }
  func configureMotion() {
    if UserDefaults.standard.bool(forKey: "tilt") && !engine.settings.local {
      Immersion.shared.startMotion()
    }
  }
  override func didMove(to view: SKView) {
    view.isMultipleTouchEnabled = true
    backgroundColor = UIColor(red: 0.10, green: 0.22, blue: 0.17, alpha: 1)
    if world.parent == nil {
      addChild(world)
      world.addChild(marks)
      world.addChild(dynamic)
      setupActors()
      Immersion.shared.prepareAudio()
    }
    drawCourt()
    updatePlayerAnimations(delta: 0)
    render()
  }
  override func didChangeSize(_ oldSize: CGSize) {
    if world.parent != nil {
      drawCourt()
      render()
    }
  }
  // Perspective projection keeps far court smaller while retaining exact inverse touch mapping.
  func project(_ p: Vec) -> CGPoint {
    let t = (p.y + 3) / 29.77
    let width = size.width * (0.64 + 0.24 * t)
    return CGPoint(
      x: size.width / 2 + (p.x - 4.115) / 10.97 * width,
      y: size.height - 52 - max(1, size.height - 90) * t)
  }
  func unproject(_ p: CGPoint) -> Vec {
    let t = (size.height - 52 - p.y) / max(1, size.height - 90)
    let width = size.width * (0.64 + 0.24 * t)
    return Vec(x: (p.x - size.width / 2) / width * 10.97 + 4.115, y: t * 29.77 - 3)
  }
  private func polygon(_ values: [Vec], fill: UIColor, stroke: UIColor = .clear, width: CGFloat = 1)
    -> SKShapeNode
  {
    let p = CGMutablePath()
    p.addLines(between: values.map(project))
    p.closeSubpath()
    let node = SKShapeNode(path: p)
    node.fillColor = fill
    node.strokeColor = stroke
    node.lineWidth = width
    return node
  }
  private func line(_ a: Vec, _ b: Vec, width: CGFloat = 1.2, color: UIColor = .white)
    -> SKShapeNode
  {
    let p = CGMutablePath()
    p.move(to: project(a))
    p.addLine(to: project(b))
    let node = SKShapeNode(path: p)
    node.strokeColor = color
    node.lineWidth = width
    return node
  }
  private func drawCourt() {
    marks.removeAllChildren()
    let surface = engine.settings.surface
    let color =
      surface == .clay
      ? UIColor(red: 0.68, green: 0.34, blue: 0.23, alpha: 1)
      : surface == .hard
        ? UIColor(red: 0.23, green: 0.43, blue: 0.56, alpha: 1)
        : UIColor(red: 0.32, green: 0.48, blue: 0.34, alpha: 1)
    marks.addChild(
      polygon(
        [Vec(x: -1.37, y: 0), Vec(x: 9.6, y: 0), Vec(x: 9.6, y: 23.77), Vec(x: -1.37, y: 23.77)],
        fill: color, stroke: .white.withAlphaComponent(0.8)))
    for i in 0..<8 where i % 2 == 0 {
      let y = Double(i) * 23.77 / 8
      marks.addChild(
        polygon(
          [
            Vec(x: -1.37, y: y), Vec(x: 9.6, y: y), Vec(x: 9.6, y: y + 23.77 / 8),
            Vec(x: -1.37, y: y + 23.77 / 8),
          ], fill: .white.withAlphaComponent(0.035)))
    }
    for x in [0.0, 8.23] { marks.addChild(line(Vec(x: x, y: 0), Vec(x: x, y: 23.77))) }
    for y in [5.485, 18.285] { marks.addChild(line(Vec(x: 0, y: y), Vec(x: 8.23, y: y))) }
    marks.addChild(line(Vec(x: 4.115, y: 5.485), Vec(x: 4.115, y: 18.285)))
    for y in [0.0, 23.77] {
      marks.addChild(line(Vec(x: 4.115, y: y), Vec(x: 4.115, y: y + (y == 0 ? 0.35 : -0.35))))
    }
    if UserDefaults.standard.object(forKey: "guides") as? Bool ?? true {
      for x in [0.0, 7.38] {
        marks.addChild(
          polygon(
            [
              Vec(x: x, y: 0), Vec(x: x + 0.85, y: 0), Vec(x: x + 0.85, y: 23.77),
              Vec(x: x, y: 23.77),
            ], fill: .systemOrange.withAlphaComponent(0.10)))
      }
    }
    let left = project(Vec(x: -1.65, y: 11.885))
    let right = project(Vec(x: 9.88, y: 11.885))
    let net = CGMutablePath()
    net.move(to: left)
    net.addLine(to: right)
    net.addLine(to: CGPoint(x: right.x, y: right.y + 13))
    net.addLine(to: CGPoint(x: left.x, y: left.y + 13))
    net.closeSubpath()
    let mesh = SKShapeNode(path: net)
    mesh.fillColor = .black.withAlphaComponent(0.3)
    mesh.strokeColor = .white.withAlphaComponent(0.5)
    marks.addChild(mesh)
    for fraction in stride(from: 0.0, through: 1.0, by: 0.04) {
      let x = left.x + (right.x - left.x) * fraction
      let path = CGMutablePath()
      path.move(to: CGPoint(x: x, y: left.y))
      path.addLine(to: CGPoint(x: x, y: left.y + 13))
      let n = SKShapeNode(path: path)
      n.strokeColor = .white.withAlphaComponent(0.15)
      n.lineWidth = 0.5
      marks.addChild(n)
    }
    let band = SKShapeNode(rectOf: CGSize(width: right.x - left.x, height: 2.5))
    band.fillColor = .white
    band.strokeColor = .clear
    band.position = CGPoint(x: size.width / 2, y: left.y + 13)
    marks.addChild(band)
    for (text, y) in [
      (surface.rawValue.uppercased() + " COURT", 26.0)
    ] {
      let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
      label.text = text
      label.fontSize = 8
      label.fontColor = .white.withAlphaComponent(0.55)
      label.position = project(Vec(x: 4.115, y: y))
      marks.addChild(label)
    }
  }
  private func setupActors() {
    for side in 0...1 {
      let athlete = PlayerFigure(courtSide: side)
      actors.append(athlete)
      dynamic.addChild(athlete)
    }
    func addRing(_ ring: SKShapeNode, color: UIColor) {
      ring.strokeColor = color
      ring.lineWidth = 1.4
      ring.fillColor = color.withAlphaComponent(0.06)
      dynamic.addChild(ring)
    }
    for ring in contactRings { addRing(ring, color: .systemYellow) }
    for ring in recoveryRings { addRing(ring, color: .white.withAlphaComponent(0.6)) }
    for ring in splitRings {
      addRing(ring, color: .white)
      ring.zPosition = 18
      ring.isHidden = true
    }
    addRing(missedOpportunityRing, color: .systemRed)
    missedOpportunityRing.lineWidth = 2
    missedOpportunityRing.fillColor = .systemRed.withAlphaComponent(0.12)
    missedOpportunityRing.zPosition = 19
    missedOpportunityRing.isHidden = true
    addRing(targetRing, color: .systemOrange)
    addRing(serveRing, color: .systemCyan)
    addRing(faultRing, color: .systemRed)
    faultRing.lineWidth = 2.5
    faultRing.fillColor = .systemRed.withAlphaComponent(0.12)
    faultRing.zPosition = 98
    faultRing.isHidden = true
    serveRing.lineWidth = 2.2
    serveRing.fillColor = .systemBlue.withAlphaComponent(0.22)
    serveRing.zPosition = 8
    servePath.strokeColor = .systemCyan.withAlphaComponent(0.45)
    servePath.lineWidth = 1.2
    servePath.zPosition = 4
    dynamic.addChild(servePath)
    approachPath.strokeColor = .systemYellow.withAlphaComponent(0.65)
    approachPath.lineWidth = 2
    approachPath.zPosition = 5
    openCourt.fillColor = .systemYellow.withAlphaComponent(0.08)
    openCourt.strokeColor = .systemYellow.withAlphaComponent(0.35)
    openCourt.lineWidth = 1
    openCourt.zPosition = 1
    dynamic.addChild(approachPath)
    dynamic.addChild(openCourt)
    for label in [followLabel, openLabel] {
      label.fontSize = 9
      label.zPosition = 6
      dynamic.addChild(label)
    }
    followLabel.text = "FOLLOW"
    followLabel.fontColor = .systemYellow
    openLabel.text = "OPEN"
    openLabel.fontColor = .systemYellow.withAlphaComponent(0.8)
    trail.strokeColor = UIColor(red: 0.86, green: 0.93, blue: 0.46, alpha: 0.5)
    trail.lineWidth = 2
    dynamic.addChild(trail)
    shadow.fillColor = .black.withAlphaComponent(0.3)
    shadow.strokeColor = .clear
    dynamic.addChild(shadow)
    ballNode.fillColor = UIColor(red: 0.88, green: 0.96, blue: 0.39, alpha: 1)
    ballNode.strokeColor = .white
    ballNode.lineWidth = 0.6
    ballNode.glowWidth = 1
    ballNode.zPosition = 100
    dynamic.addChild(ballNode)
    if let hand = UIImage(systemName: "hand.point.up.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 46, weight: .regular))?
      .withTintColor(.white, renderingMode: .alwaysOriginal) {
      // SpriteKit reads the underlying symbol pixels; bake UIKit's white tint into the texture.
      let rendered = UIGraphicsImageRenderer(size: hand.size).image { _ in hand.draw(at: .zero) }
      swipeHand.texture = SKTexture(image: rendered)
      swipeHand.size = CGSize(width: 44 * hand.size.width / hand.size.height, height: 44)
    }
    swipeHand.anchorPoint = CGPoint(x: 0.38, y: 1)
    swipeHand.color = .white
    swipeHand.colorBlendFactor = 0
    swipeHand.zPosition = 140
    swipeHand.isHidden = true
    swipeTouch.strokeColor = .white.withAlphaComponent(0.5)
    swipeTouch.fillColor = .white.withAlphaComponent(0.08)
    swipeTouch.lineWidth = 1
    swipeTouch.zPosition = 139
    swipeTouch.isHidden = true
    dynamic.addChild(swipeTouch)
    dynamic.addChild(swipeHand)
    demoGesturePath.strokeColor = .white.withAlphaComponent(0.55)
    demoGesturePath.lineWidth = 2
    demoGesturePath.zPosition = 138
    demoGesturePath.isHidden = true
    dynamic.addChild(demoGesturePath)
  }
  override func update(_ currentTime: TimeInterval) {
    guard !suspended else {
      previousTime = 0
      return
    }
    let dt = previousTime == 0 ? 0 : min(0.1, currentTime - previousTime)
    previousTime = currentTime
    let oldInventory = engine.inventory
    let oldPhase = engine.phase
    let showedGauges = engine.displayedServeGauges != nil
    let oldResultVisible = engine.showsPointResult
    let oldBounce = engine.bounceSerial
    if engine.needsSimulation {
      accumulator += dt
      while accumulator >= 1 / 120 {
        if engine.acceptsCourtMovement && engine.demo?.demonstration != true { applyInputs() }
        engine.step(1 / 120)
        accumulator -= 1 / 120
      }
    }
    animationTime += dt
    let oldMiss = missPresentation.current
    missPresentation.update(coach: engine.coach, delta: dt)
    if oldMiss != missPresentation.current { publishCoachMiss?(missPresentation.current) }
    let showGuides = engine.demo != nil || (UserDefaults.standard.object(forKey: "guides") as? Bool ?? true)
    swipeCoach.update(guide: showGuides ? engine.movementGuide(0) : nil, delta: dt)
    updatePlayerAnimations(delta: dt)
    if engine.bounceSerial != oldBounce { Immersion.shared.hit(bounce: true, x: engine.ball.x) }
    if oldPhase.isPlaying && !engine.phase.isPlaying {
      if engine.flight?.power == .ace { Immersion.shared.cheer() }
      Immersion.shared.finishRally()
    }
    if !oldResultVisible && engine.showsPointResult {
      Immersion.shared.point(engine.scoreAnnouncement)
    }
    if oldPhase == .serveFault && engine.phase == .serving { configureMotion(); trails.removeAll() }
    render()
    if currentTime - publishAt > 0.1 || oldInventory != engine.inventory || oldPhase != engine.phase
      || oldResultVisible != engine.showsPointResult || showedGauges != (engine.displayedServeGauges != nil) {
      publishAt = currentTime
      publish?(engine)
    }
  }
  private func applyInputs() {
    let controllers = GCController.controllers()
    for side in 0...(engine.settings.local ? 1 : 0) {
      if engine.phase == .serving && engine.scoring.server == side { continue }
      if controllers.indices.contains(side), let pad = controllers[side].extendedGamepad {
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = -Double(pad.leftThumbstick.yAxis.value)
        if abs(x) + abs(y) > 0.15 {
          engine.move(
            side,
            to:
              Vec(x: engine.players[side].pos.x + x * 1.8, y: engine.players[side].pos.y + y * 1.8))
        }
        let pressed = [
          pad.buttonA.isPressed, pad.buttonB.isPressed, pad.buttonX.isPressed,
          pad.buttonY.isPressed,
        ]
        for i in 0..<4 where pressed[i] { engine.choose(side, ShotKind.allCases[i]) }
      } else if side == 0 && !engine.settings.local && UserDefaults.standard.bool(forKey: "tilt") {
        let t = Immersion.shared.tilt
        if t.length > 0.12 {
          engine.move(
            0,
            to: Vec(x: engine.players[0].pos.x + t.x * 1.8, y: engine.players[0].pos.y + t.y * 1.8))
        }
      }
      if let keyboard = GCKeyboard.coalesced?.keyboardInput {
        let movement: [GCKeyCode] =
          side == 0
          ? [.keyA, .keyD, .keyW, .keyS] : [.leftArrow, .rightArrow, .upArrow, .downArrow]
        let pressed = movement.map { keyboard.button(forKeyCode: $0)?.isPressed == true }
        let dx = (pressed[1] ? 1.0 : 0) - (pressed[0] ? 1.0 : 0)
        let dy = (pressed[3] ? 1.0 : 0) - (pressed[2] ? 1.0 : 0)
        if dx != 0 || dy != 0 {
          engine.move(
            side,
            to:
              Vec(
                x: engine.players[side].pos.x + dx * 1.8, y: engine.players[side].pos.y + dy * 1.8))
          keyboardMoving[side] = true
        } else if keyboardMoving[side] {
          engine.players[side].destination = engine.players[side].pos
          keyboardMoving[side] = false
        }
        let shots: [GCKeyCode] =
          side == 0 ? [.keyZ, .keyX, .keyC, .keyV] : [.one, .two, .three, .four]
        for (index, key) in shots.enumerated()
        where keyboard.button(forKeyCode: key)?.isPressed == true {
          engine.choose(side, ShotKind.allCases[index])
        }
      }
    }
  }
  func restorePresentation() {
    resetRallyPresentation()
    missPresentation.restore(from: engine.coach)
  }

  func resetRallyPresentation() {
    swipeCoach.dismiss()
    actors.forEach { $0.reset() }
    trails.removeAll()
    observedContactSerial = engine.contactSerial
  }

  private func positionPlayers() {
    for i in 0...1 {
      let p = engine.players[i].pos
      actors[i].position = project(p)
      // Scale by actual court depth so approach shots keep their perspective.
      actors[i].setScale(0.82 + clamp(p.y / PracticeEngine.length, 0, 1) * 0.18)
      actors[i].zPosition = 20 + p.y
    }
  }

  private func incomingTiming(for side: Int, flight: BallFlight) -> (Double, TennisStrokeStyle) {
    let window = engine.contactWindow(side)
    return (
      max(0, (window?.entry ?? 1) * flight.duration - flight.elapsed),
      window?.overhead == true
        ? .overhead
        : window?.volley == true
          ? .volley : engine.players[side].kind.strokeStyle
    )
  }

  private func updatePlayerAnimations(delta: Double) {
    guard actors.count == 2 else { return }
    positionPlayers()
    // Observe the engine event instead of starting a new independent SKAction after impact.
    // This includes opening serves, which are initiated outside the frame loop.
    let hit = engine.contactSerial != observedContactSerial
    if hit, let flight = engine.flight {
      observedContactSerial = engine.contactSerial
      let actor = actors[flight.hitter]
      actor.motion.hit(style: flight.stroke, elapsed: flight.elapsed)
      Immersion.shared.hit(x: engine.ball.x, gain: flight.power?.contactGain ?? 1)
      trails.removeAll()
    }
    for side in 0...1 {
      let player = engine.players[side]
      var arrival: Double?
      var style = player.kind.strokeStyle
      var reach = 30.0
      if engine.phase == .live, let flight = engine.flight,
        flight.hitter != side, flight.fault == nil, flight.power == nil,
        !(side == 1 && (flight.opponentError == .unreachable || flight.dropReachable == false))
      {
        (arrival, style) = incomingTiming(for: side, flight: flight)
        let contact = project(engine.intercept(side))
        reach = abs(contact.x - actors[side].position.x) / actors[side].xScale
      }
      if engine.phase == .serving, let serve = engine.servePreparation, serve.server == side,
        let elapsed = serve.tossElapsed {
        arrival = max(0, ServePreparation.tossDuration - elapsed)
        style = .serve
      }
      if side == 0, let assist = engine.assist {
        arrival = max(0, assist.travelTime - assist.elapsed)
        style = assist.power == .overhead ? .overhead : .groundstroke
      }
      let lateral = StrokeAnimation.lateralBallOffset(
        ballX: engine.ball.x, playerX: player.pos.x, courtSide: side)
      actors[side].motion.update(
        delta: hit && engine.flight?.hitter == side ? 0 : delta,
        lateralBall: lateral, arrival: arrival, incomingStyle: style, reach: reach)
    }
  }

  private func displayedBallPosition() -> CGPoint {
    if let resolution = engine.pointResolution, let impact = resolution.impact {
      let pose = impact.ball(after: resolution.elapsed)
      let ground = project(pose.position)
      return CGPoint(x: ground.x, y: ground.y + pose.height * 20)
    }
    if engine.phase == .serving, let serve = engine.servePreparation {
      let from = project(engine.players[serve.server].pos)
      let direction = serve.server == 0 ? 1.0 : -1.0
      let scale = actors[serve.server].xScale
      let impact = actors[serve.server].motion.contactPose.racketCentre
      if let t = serve.tossProgress {
        // The toss finishes at the same string-bed position used by the outgoing flight.
        return CGPoint(x: from.x + (-14 + (impact.x + 14) * t) * direction * scale,
          y: from.y + (25 + (impact.y + (reduceMotion ? 0 : engine.queuedPower == .ace ? 14 : 10) - 25) * t + sin(t * .pi) * 34) * scale)
      }
      return CGPoint(x: from.x - 14 * direction * scale, y: from.y + 25 * scale)
    }
    guard let flight = engine.flight else { return project(engine.ball) }
    if flight.kind == .drop && flight.dropReachable == false && flight.progress >= 0.8 {
      let ground = project(flight.position)
      return CGPoint(x: ground.x, y: ground.y + flight.height * 20)
    }
    let progress = flight.progress
    let from = project(flight.from)
    let groundLanding = project(flight.landing)
    let landing = CGPoint(x: groundLanding.x,
      y: groundLanding.y + (flight.fault == "net" ? 9 : 0))
    let contact = project(flight.contact)
    let hitter = actors[flight.hitter]
    // Keep the origin fixed to the stroke location while the hitter starts recovering.
    let localImpact = hitter.motion.contactPose.racketCentre
    let direction = flight.hitter == 0 ? 1.0 : -1.0
    let launchScale = 0.82 + clamp(flight.from.y / PracticeEngine.length, 0, 1) * 0.18
    let origin = CGPoint(
      x: from.x + localImpact.x * direction * launchScale,
      y: from.y + (localImpact.y + (flight.serve && !reduceMotion ? (flight.power == .ace ? 14 : 10) : 0)) * launchScale)
    if progress < 0.8 {
      let t = progress / 0.8
      let arc = sin(t * .pi) * flight.loft * 25 * engine.settings.surface.bounce
      let airborne = CGPoint(
        x: origin.x + (landing.x - origin.x) * t,
        y: origin.y + (landing.y - origin.y) * t + arc)
      let receiver = 1 - flight.hitter
      if let assist = engine.assist, assist.power == .overhead, assist.impactProgress < 0.8 {
        let blend = StrokeAnimation.ease(1 - (assist.travelTime - assist.elapsed) / 0.22)
        let strings = actors[receiver].contactPoint(in: self)
        return CGPoint(x: airborne.x + (strings.x - airborne.x) * blend,
          y: airborne.y + (strings.y - airborne.y) * blend)
      }
      if let window = engine.contactWindow(receiver), window.volley {
        let remaining = (window.entry - progress) * flight.duration
        let blend = StrokeAnimation.ease(1 - remaining / 0.16)
        let strings = actors[receiver].contactPoint(in: self)
        return CGPoint(
          x: airborne.x + (strings.x - airborne.x) * blend,
          y: airborne.y + (strings.y - airborne.y) * blend)
      }
      return airborne
    }
    let receiver = 1 - flight.hitter
    let kick = flight.serveProfile?.kick ?? 1
    var endpoint = CGPoint(x: contact.x, y: contact.y + 31 * kick * actors[receiver].yScale)
    if let power = flight.power {
      let t = clamp((progress - 0.8) / 0.2, 0, 1)
      let ground = project(flight.position)
      let rise = power == .overhead ? 100 * sin(t * .pi / 2)
        : (power == .ace ? 1.25 * kick : 1) * 31 * t
      return CGPoint(x: ground.x, y: ground.y + rise * actors[receiver].yScale)
    }
    if flight.fault == nil && engine.players[receiver].pos.distance(to: flight.contact) <= 1.35 {
      endpoint = actors[receiver].contactPoint(in: self)
    }
    let impactProgress = engine.assist?.impactProgress ?? engine.contactWindow(receiver)?.entry ?? 1
    if engine.assist != nil { endpoint = actors[receiver].contactPoint(in: self) }
    let t = clamp((progress - 0.8) / max(0.001, impactProgress - 0.8), 0, 1)
    return CGPoint(
      x: landing.x + (endpoint.x - landing.x) * t,
      y: landing.y + (endpoint.y - landing.y) * t + sin(t * .pi) * (kick - 1) * 31 * actors[receiver].yScale)
  }

  private func render() {
    guard actors.count == 2 else { return }
    positionPlayers()
    if courtReaction.parent == nil { dynamic.addChild(courtReaction) }
    let reaction = engine.isResolvingPoint ? engine.pointResolution?.reaction : nil
    courtReaction.draw(reaction, courtCenter: project(Vec(x: PracticeEngine.width / 2, y: 18)),
      opponentPosition: project(engine.players[1].pos), width: size.width,
      courtHeight: project(Vec(x: 0, y: PracticeEngine.net)).y - project(Vec(x: 0, y: PracticeEngine.length)).y - 20,
      elapsed: engine.pointResolution?.elapsed ?? 0, reduceMotion: reduceMotion)
    missedOpportunityRing.position = project(engine.players[0].pos)
    missedOpportunityRing.isHidden = missPresentation.ringProgress == nil
    if let progress = missPresentation.ringProgress {
      missedOpportunityRing.alpha = 0.9 * (1 - progress)
      missedOpportunityRing.setScale(reduceMotion ? 1 : 1 + progress * 0.12)
    }
    for i in 0...1 {
      actors[i].draw(
        time: animationTime, velocity: engine.players[i].velocity, reduceMotion: reduceMotion,
        split: engine.splitProgress(i),
        servePreparing: engine.phase == .serving && engine.scoring.server == i,
        serveToss: engine.scoring.server == i ? engine.servePreparation?.tossProgress : nil,
        serveLanding: engine.serveLanding?.server == i ? engine.serveLanding?.progress : nil,
        frustration: i == 1 ? reaction?.frustration ?? 0 : 0,
        affirmation: i == 0 && reaction?.affirmation != nil,
        reactionTime: engine.pointResolution?.elapsed ?? 0,
        explosiveServe: i == 0 && (engine.queuedPower == .ace || engine.flight?.power == .ace),
        surprise: i == 1 && engine.flight?.power == .ace ? (engine.ball.x < engine.players[1].pos.x ? 1 : -1) : 0,
        acknowledge: i == 0 && engine.isResolvingPoint && engine.flight?.acknowledge == true)
      let progress = engine.splitProgress(i)
      splitRings[i].isHidden = progress == nil || !engine.phase.isPlaying
      splitRings[i].position = project(engine.players[i].pos)
      splitRings[i].strokeColor = engine.splitTimed[i] ? .systemMint : .white
      splitRings[i].alpha = 1 - (progress ?? 0) * 0.65
      splitRings[i].setScale(reduceMotion ? 1 : 1 + (progress ?? 0) * 0.35)
    }
    let ground = project(engine.ball)
    shadow.position = ground
    ballNode.position = displayedBallPosition()
    let lift = max(0, ballNode.position.y - ground.y)
    ballNode.setScale(1 + min(0.3, lift / 150))
    let showingFlight = engine.phase == .live || engine.isResolvingPoint
    if showingFlight && !reduceMotion {
      trails.append(ballNode.position)
      // Retain the complete fault path through its impact and rebound, until the result appears.
      let limit = engine.flight?.fault == nil ? 9 : 480
      if trails.count > limit { trails.removeFirst(trails.count - limit) }
    }
    let path = CGMutablePath()
    path.addLines(between: trails)
    trail.path = path
    trail.isHidden = reduceMotion || !showingFlight
    faultRing.isHidden = engine.pointResolution?.showsMarker != true
    if let impact = engine.pointResolution?.impact {
      let location = project(impact.point)
      faultRing.position = CGPoint(x: location.x, y: location.y + impact.height * 20)
    }
    let guides = engine.demo != nil || (UserDefaults.standard.object(forKey: "guides") as? Bool ?? true)
    for side in 0...1 {
      // Each human sees one next-action guide: receive, then recover after contact.
      let green = side == 0 && engine.phase == .live && engine.inventory.held == .rally && engine.canChooseShot(0)
      let visible = green || engine.phase == .serving
        || (guides && engine.acceptsCourtMovement && engine.flight != nil && (side == 0 || engine.settings.local))
      let contact = engine.contactGuide(side)
      let golden = engine.showsGoldenContact(side)
      let chasingOut = engine.outBallChaseTarget(side) != nil
      contactRings[side].strokeColor = green ? .systemGreen : golden
        ? UIColor(red: 1, green: 0.69, blue: 0.12, alpha: 1) : .yellow
      contactRings[side].lineWidth = golden ? 4.2 : 2
      contactRings[side].glowWidth = golden ? 2 : 0
      contactRings[side].alpha = chasingOut ? 0.3
        : golden && !reduceMotion ? 0.6 + 0.4 * (0.5 + 0.5 * sin(animationTime * 2 * .pi)) : 1
      contactRings[side].isHidden = !visible || contact == nil
      recoveryRings[side].isHidden = !visible || engine.recoveryGuide(side) == nil
      if let contact, visible {
          let center = project(contact)
          contactRings[side].position = center
          let outline = CGMutablePath()
          let points = stride(from: 0.0, through: 2 * .pi, by: .pi / 24).map { angle in
            let p = project(
              Vec(
                x: contact.x + cos(angle) * PracticeEngine.contactRadius,
                y: contact.y + sin(angle) * PracticeEngine.contactRadius))
            return CGPoint(x: p.x - center.x, y: p.y - center.y)
          }
          outline.addLines(between: points)
          outline.closeSubpath()
          contactRings[side].path = outline
        }
      if let flight = engine.flight {
        recoveryRings[side].position = project(PracticeEngine.recovery(side, flight.contact))
      }
    }
    if let goal = engine.demo?.target, engine.phase == .serving {
      targetRing.isHidden = false
      targetRing.strokeColor = .systemMint
      targetRing.setScale(1.4)
      targetRing.position = project(goal)
    } else if let demo = engine.demo, demo.lesson == .recoverySplit, demo.stage == .rallyRecovery,
      demo.bounceWindowOpen, demo.result == nil, let landing = engine.flight?.landing {
      targetRing.position = project(landing)
      targetRing.strokeColor = .systemMint
      targetRing.setScale(1.4)
      targetRing.isHidden = false
    } else {
      targetRing.strokeColor = .systemOrange
      targetRing.setScale(1)
      targetRing.isHidden = !guides || engine.phase != .live || engine.players[0].aim == nil
      if let aim = engine.players[0].aim { targetRing.position = project(aim) }
    }
    let serveInFlight = engine.phase == .live && engine.flight?.serve == true && (engine.flight?.progress ?? 1) < 0.8
    serveRing.isHidden = engine.phase != .serving && !serveInFlight
    if serveInFlight, let flight = engine.flight { serveRing.position = project(flight.landing) }
    servePath.isHidden = engine.phase != .serving
    if engine.phase == .serving, let serve = engine.servePreparation {
      serveRing.position = project(serve.target)
      serveRing.alpha = serve.isTossing ? 1 : 0.85
      let line = CGMutablePath()
      line.move(to: project(engine.players[serve.server].pos))
      line.addLine(to: project(serve.target))
      if let receiver = engine.serveReceiveTarget(1 - serve.server) { line.addLine(to: project(receiver)) }
      servePath.path = line.copy(dashingWithPhase: 0, lengths: [4, 5])
    }
    drawTacticalGuides(enabled: guides)
    drawSwipeCoach(enabled: guides)
  }

  private func drawTacticalGuides(enabled: Bool) {
    let active =
      enabled && engine.settings.allCourtTraining && !engine.settings.local
      && engine.phase == .live && engine.attacking[0] && engine.flight?.fault == nil
    openCourt.isHidden = !active
    openLabel.isHidden = !active
    let following = active && engine.followingApproach[0] && engine.flight?.hitter == 0
    let guide = engine.movementGuide(0) ?? (following
      ? MovementGuide(kind: .approach, from: engine.players[0].pos, to: engine.players[0].destination)
      : nil)
    approachPath.isHidden = !enabled || guide == nil
    followLabel.isHidden = !enabled || guide?.kind != .approach
    if active {
      let aim = CourtTactics.openCourt(side: 0, opponent: engine.players[1].pos, overhead: false)
      let left = aim.x < 4.115 ? 0.7 : 4.6
      let right = aim.x < 4.115 ? 3.63 : 7.53
      let region = CGMutablePath()
      region.addLines(
        between: [
          Vec(x: left, y: 1), Vec(x: right, y: 1),
          Vec(x: right, y: 6), Vec(x: left, y: 6),
        ].map(project))
      region.closeSubpath()
      openCourt.path = region
      openLabel.position = project(Vec(x: (left + right) / 2, y: 3.5))
    }
    if let guide, enabled {
      let from = project(guide.from)
      let to = project(guide.to)
      approachPath.strokeColor = (guide.kind == .recover ? UIColor.white : .systemYellow)
        .withAlphaComponent(0.55)
      followLabel.fontColor = guide.kind == .recover ? .white : .systemYellow
      followLabel.text = following ? "FOLLOW" : guide.kind == .approach ? "SWIPE IN" : "SWIPE"
      let path = CGMutablePath()
      path.move(to: from)
      path.addLine(to: to)
      let dx = to.x - from.x
      let dy = to.y - from.y
      let length = max(1, hypot(to.x - from.x, to.y - from.y))
      path.move(
        to: CGPoint(
          x: to.x - dx / length * 8 - dy / length * 4,
          y: to.y - dy / length * 8 + dx / length * 4))
      path.addLine(to: to)
      path.addLine(
        to: CGPoint(
          x: to.x - dx / length * 8 + dy / length * 4,
          y: to.y - dy / length * 8 - dx / length * 4))
      approachPath.path = path
      followLabel.position = CGPoint(x: (from.x + to.x) / 2 + 26, y: (from.y + to.y) / 2)
    }
  }

  private func drawSwipeCoach(enabled: Bool) {
    if engine.demo != nil { drawDemoGesture(); return }
    demoGesturePath.isHidden = true
    guard enabled, engine.phase.isPlaying, let guide = swipeCoach.active else {
      swipeHand.isHidden = true
      swipeTouch.isHidden = true
      return
    }
    let cycle = swipeCoach.elapsed.truncatingRemainder(dividingBy: 1.2) / 1.2
    let progress = reduceMotion ? 0.5 : StrokeAnimation.ease(clamp((cycle - 0.12) / 0.68, 0, 1))
    let from = project(guide.from)
    let to = project(guide.to)
    let distance = max(1, hypot(to.x - from.x, to.y - from.y))
    // Demonstrate a short directional swipe, not a drag across the whole display.
    let travel = min(distance, 72)
    let point = guide.kind == .recover
      ? CGPoint(x: to.x, y: to.y + (reduceMotion ? 0 : sin(cycle * .pi) * 7))
      : CGPoint(
        x: from.x + (to.x - from.x) / distance * travel * progress,
        y: from.y + (to.y - from.y) / distance * travel * progress)
    swipeHand.position = point
    swipeTouch.position = point
    swipeHand.alpha = 0.58 * min(1, max(0, (swipeCoach.duration - swipeCoach.elapsed) / 0.2))
    swipeTouch.alpha = swipeHand.alpha * 0.65
    swipeHand.isHidden = false
    swipeTouch.isHidden = false
  }
  private func drawDemoGesture() {
    swipeHand.isHidden = true
    swipeTouch.isHidden = true
    demoGesturePath.isHidden = true
    guard let demo = engine.demo, demo.result == nil, engine.phase.isPlaying else { return }
    let cycle = demo.stageTime.truncatingRemainder(dividingBy: 1.6) / 1.6
    let progress = reduceMotion ? 0.55 : StrokeAnimation.ease(clamp((cycle - 0.1) / 0.7, 0, 1))
    let player = project(engine.players[0].pos)
    var from = player, to = player
    var tap = false, circle = false
    if engine.phase == .serving, let goal = demo.target, let serve = engine.servePreparation {
      guard !serve.isTossing else { return }
      if demo.serveAdjusted {
        from = project(Vec(x: engine.players[0].pos.x + 1.6, y: engine.players[0].pos.y))
        tap = true
      } else {
        from = project(serve.target)
        to = project(goal)
      }
    } else if demo.stage == .rallyRecovery, let white = demo.recoveryTarget {
      guard demo.recoveredAt == nil || (demo.lesson == .recoverySplit && demo.bounceWindowOpen && !demo.splitAfterRecovery) else { return }
      from = project(white)
      tap = true
    } else if demo.stage == .approachFlight {
      guard !demo.approached else { return }
      from = CGPoint(x: player.x + 44, y: player.y - 5)
      to = CGPoint(x: from.x, y: from.y + 65)
    } else if demo.stage == .receive || demo.stage == .volleyReceive {
      guard demo.chosenShot == nil else { return }
      let yellow = engine.contactGuide(0)
      let movingToYellow = yellow.map { engine.players[0].destination.distance(to: $0) <= 0.3 } ?? false
      if demo.lesson.isFootwork && movingToYellow { return }
      if !movingToYellow, let yellow {
        from = project(yellow)
        tap = true
      } else {
        let opposite: CGFloat = engine.players[0].pos.x < PracticeEngine.width / 2 ? 1 : -1
        from = CGPoint(x: player.x, y: player.y + 25)
        switch demo.lesson.shot {
        case .line: to = CGPoint(x: from.x, y: from.y + 55)
        case .cross: to = CGPoint(x: from.x + 48 * opposite, y: from.y + 48)
        case .angle: to = CGPoint(x: from.x + 60 * opposite, y: from.y)
        case .lob: to = CGPoint(x: from.x, y: max(46, from.y - 45))
        case .drop: from.x += 28; circle = true
        case .slice:
          from = project(Vec(x: -1.65, y: PracticeEngine.net))
          to = project(Vec(x: 6.8, y: PracticeEngine.length - 0.5))
        }
      }
    } else { return }
    let path = CGMutablePath()
    let point: CGPoint
    if tap {
      point = CGPoint(x: from.x, y: from.y + (reduceMotion ? 0 : sin(cycle * .pi) * 6))
    } else if circle {
      path.addEllipse(in: CGRect(x: from.x - 22, y: from.y - 22, width: 44, height: 44))
      point = CGPoint(x: from.x + cos(progress * 2 * .pi) * 22, y: from.y + sin(progress * 2 * .pi) * 22)
    } else {
      path.move(to: from); path.addLine(to: to)
      point = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
    }
    demoGesturePath.path = path.copy(dashingWithPhase: 0, lengths: [3, 4])
    demoGesturePath.isHidden = tap
    swipeHand.position = point
    swipeTouch.position = point
    swipeHand.alpha = 0.7
    swipeTouch.alpha = 0.45
    swipeHand.isHidden = false
    swipeTouch.isHidden = false
  }

  private func applyTouch(_ touch: UITouch, ended: Bool = false) {
    guard engine.acceptsCourtMovement && !suspended && engine.demo?.demonstration != true else { return }
    if var serveTouch = serveTouches[touch] {
      let point = touch.location(in: self)
      if hypot(point.x - serveTouch.start.x, point.y - serveTouch.start.y) >= 8 { serveTouch.dragging = true }
      serveTouches[touch] = serveTouch
      if serveTouch.dragging {
        engine.aimServe(at: unproject(point), side: engine.scoring.server, finished: ended)
      } else if ended {
        if engine.demo == nil, let target = engine.servePreparation?.target {
          engine.aimServe(at: target, side: engine.scoring.server)
        } else {
          engine.requestServe(engine.scoring.server)
        }
      }
      if ended { publish?(engine) }
      return
    }
    guard var gesture = touchGestures[touch] else { return }
    let action = gesture.update(
      at: unproject(touch.location(in: self)),
      screenPoint: Vec(x: touch.location(in: self).x, y: -touch.location(in: self).y),
      ended: ended, timestamp: touch.timestamp)
    touchGestures[touch] = gesture
    if let action {
      let showedGauges = engine.displayedServeGauges != nil
      engine.apply(action, side: gesture.side, shotEpoch: gesture.shotEpoch)
      if engine.inventory.held != nil || showedGauges != (engine.displayedServeGauges != nil) { publish?(engine) }
    }
  }
  func dismissAffirmation() {
    guard !suspended, engine.dismissAffirmation() else { return }
    affirmationTouches.removeAll()
    touchGestures.removeAll()
    serveTouches.removeAll()
    render()
    publish?(engine)
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard !suspended && engine.demo?.demonstration != true else { return }
    if engine.showsAffirmation {
      for touch in touches { affirmationTouches[touch] = touch.location(in: self) }
      return
    }
    guard engine.acceptsCourtMovement else { return }
    for touch in touches {
      let p = unproject(touch.location(in: self))
      if engine.canAimServe(engine.scoring.server), let serve = engine.servePreparation,
        p.distance(to: serve.target) <= 1.1 {
        serveTouches[touch] = ServeTouch(start: touch.location(in: self))
        continue
      }
      var side = engine.settings.local && p.y < 11.885 ? 1 : 0
      if SlicePath.isNetPost(p), let receiver = (0...1).first(where: { engine.canChooseShot($0) }) {
        side = receiver
        touchGestures[touch] = PracticeGesture(side: side, intent: .slice,
          shotEpoch: engine.shotGestureEpoch(side))
        applyTouch(touch)
        continue
      }
      swipeCoach.dismiss()
      let finger = touch.location(in: self)
      var onPlayer = false
      // A figure at the net can extend into the other half on screen. Its receiving owner wins.
      for candidate in 0...(engine.settings.local ? 1 : 0) where engine.canChooseShot(candidate) {
        let player = project(engine.players[candidate].pos)
        if abs(finger.x - player.x) <= 25 && finger.y >= player.y - 12 && finger.y <= player.y + 58 {
          side = candidate
          onPlayer = true
          break
        }
      }
      let intent: CourtTouchIntent = onPlayer && engine.canChooseShot(side) ? .shot : .movement
      touchGestures[touch] = PracticeGesture(side: side, intent: intent,
        shotEpoch: engine.shotGestureEpoch(side), allowsDrop: engine.canDrawDrop(side))
      applyTouch(touch)
    }
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      if let start = affirmationTouches[touch] {
        let point = touch.location(in: self)
        if hypot(point.x - start.x, point.y - start.y) > 10 { affirmationTouches.removeValue(forKey: touch) }
      } else { applyTouch(touch) }
    }
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      // Only a new tap begun during the affirmation may skip it. A rally swipe
      // released after the point, or this same tap, cannot advance the next point.
      if let start = affirmationTouches.removeValue(forKey: touch) {
        let point = touch.location(in: self)
        if hypot(point.x - start.x, point.y - start.y) <= 10 { dismissAffirmation() }
        continue
      }
      applyTouch(touch, ended: true)
      touchGestures.removeValue(forKey: touch)
      serveTouches.removeValue(forKey: touch)
    }
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    for touch in touches {
      touchGestures.removeValue(forKey: touch)
      serveTouches.removeValue(forKey: touch)
      affirmationTouches.removeValue(forKey: touch)
    }
  }
}
