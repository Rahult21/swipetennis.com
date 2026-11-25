import SpriteKit

/// A small articulated vector athlete. Limbs, hands and racket share the same pose, rather
/// than animating a detached racket sprite. Works at both court and enlarged preview scales.
@MainActor final class PlayerFigure: SKNode {
  let courtSide: Int
  var motion = StrokeAnimation()
  private let silhouette = SKNode()
  private let shadow = SKShapeNode(ellipseOf: CGSize(width: 33, height: 11))
  private let leftLeg = SKShapeNode(), rightLeg = SKShapeNode()
  private let leftSock = SKShapeNode(), rightSock = SKShapeNode()
  private let leftShoe = SKShapeNode(), rightShoe = SKShapeNode()
  private let shorts = SKShapeNode(), shirt = SKShapeNode(), shirtPanel = SKShapeNode()
  private let collar = SKShapeNode(), hem = SKShapeNode(), chestMark = SKShapeNode()
  private let leftArm = SKShapeNode(), rightArm = SKShapeNode()
  private let leftBand = SKShapeNode(), rightBand = SKShapeNode()
  private let leftHand = SKShapeNode(circleOfRadius: 2.1),
    rightHand = SKShapeNode(circleOfRadius: 2.1)
  private let neck = SKShapeNode(rectOf: CGSize(width: 5, height: 6), cornerRadius: 2)
  private let head = SKShapeNode(ellipseOf: CGSize(width: 10, height: 12))
  private let hair = SKShapeNode(), headband = SKShapeNode(), face = SKShapeNode()
  private let racket = SKNode(), racketTrail = SKShapeNode()
  private let skin = SKColor(red: 0.76, green: 0.53, blue: 0.36, alpha: 1)
  private let kit: SKColor
  private let kitShadow: SKColor
  private let ink = SKColor(red: 0.12, green: 0.20, blue: 0.20, alpha: 1)
  private var previousRacketCentres: [CGPoint] = []

  init(courtSide: Int) {
    self.courtSide = courtSide
    kit =
      courtSide == 0
      ? SKColor(red: 0.74, green: 0.89, blue: 0.94, alpha: 1)
      : SKColor(red: 0.97, green: 0.64, blue: 0.36, alpha: 1)
    kitShadow =
      courtSide == 0
      ? SKColor(red: 0.25, green: 0.54, blue: 0.61, alpha: 1)
      : SKColor(red: 0.66, green: 0.30, blue: 0.17, alpha: 1)
    super.init()
    name = "player-\(courtSide)"
    addChild(shadow)
    shadow.fillColor = .black.withAlphaComponent(0.22)
    shadow.strokeColor = .clear
    shadow.position = CGPoint(x: 3, y: -1.5)
    addChild(silhouette)
    silhouette.xScale = courtSide == 0 ? 1 : -1
    for node in [
      leftLeg, rightLeg, leftSock, rightSock, leftShoe, rightShoe, shorts, shirt,
      shirtPanel, hem, collar, chestMark, leftArm, rightArm, leftBand, rightBand,
      neck, head, hair, headband, face, racketTrail, leftHand, rightHand,
    ] {
      silhouette.addChild(node)
      node.strokeColor = .clear
    }
    for limb in [leftLeg, rightLeg, leftArm, rightArm] { limb.fillColor = skin }
    for item in [
      leftSock, rightSock, leftShoe, rightShoe, headband, collar, hem, leftBand, rightBand,
    ] {
      item.fillColor = .white
    }
    shorts.fillColor = ink
    shirt.fillColor = kit
    shirtPanel.fillColor = kitShadow
    chestMark.fillColor = kitShadow
    neck.fillColor = skin
    head.fillColor = skin
    hair.fillColor = SKColor(red: 0.15, green: 0.11, blue: 0.09, alpha: 1)
    face.strokeColor = ink.withAlphaComponent(0.65)
    face.lineWidth = 0.7
    leftHand.fillColor = skin
    rightHand.fillColor = skin
    racketTrail.strokeColor = .white.withAlphaComponent(0.19)
    racketTrail.lineWidth = 1.8
    racketTrail.zPosition = 12
    silhouette.addChild(racket)
    buildRacket()
    draw(time: 0, velocity: .zero, reduceMotion: false)
  }

  required init?(coder: NSCoder) { fatalError("Use init(courtSide:)") }

  func reset() {
    motion = StrokeAnimation()
    previousRacketCentres.removeAll()
  }

  /// Predicted string-bed contact in scene coordinates, also used to align the drawn ball.
  func contactPoint(in scene: SKNode) -> CGPoint {
    let p = motion.contactPose.racketCentre
    return silhouette.convert(CGPoint(x: p.x, y: p.y), to: scene)
  }

  private func buildRacket() {
    let grip = SKShapeNode(rectOf: CGSize(width: 2.7, height: 9), cornerRadius: 1)
    grip.position.y = 2
    grip.fillColor = ink
    grip.strokeColor = .white.withAlphaComponent(0.8)
    grip.lineWidth = 0.5
    racket.addChild(grip)
    let throat = SKShapeNode()
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 5))
    path.addLine(to: CGPoint(x: -4.3, y: 12.5))
    path.move(to: CGPoint(x: 0, y: 5))
    path.addLine(to: CGPoint(x: 4.3, y: 12.5))
    throat.path = path
    throat.strokeColor = kit
    throat.lineWidth = 1.3
    racket.addChild(throat)
    let rim = SKShapeNode(ellipseOf: CGSize(width: 13, height: 19))
    rim.position.y = 19
    rim.strokeColor = ink
    rim.lineWidth = 2.3
    rim.fillColor = .white.withAlphaComponent(0.07)
    racket.addChild(rim)
    let edge = SKShapeNode(ellipseOf: CGSize(width: 12.5, height: 18.5))
    edge.position.y = 19
    edge.strokeColor = kit
    edge.lineWidth = 0.8
    racket.addChild(edge)
    let strings = SKShapeNode()
    let mesh = CGMutablePath()
    for x in stride(from: -4.5, through: 4.5, by: 2.25) {
      let reach = 8.1 * sqrt(max(0, 1 - pow(x / 5.4, 2)))
      mesh.move(to: CGPoint(x: x, y: 19 - reach))
      mesh.addLine(to: CGPoint(x: x, y: 19 + reach))
    }
    for y in stride(from: -6.0, through: 6.0, by: 2.4) {
      let reach = 5.3 * sqrt(max(0, 1 - pow(y / 8.4, 2)))
      mesh.move(to: CGPoint(x: -reach, y: 19 + y))
      mesh.addLine(to: CGPoint(x: reach, y: 19 + y))
    }
    strings.path = mesh
    strings.strokeColor = .white.withAlphaComponent(0.65)
    strings.lineWidth = 0.45
    racket.addChild(strings)
  }

  private func polygon(_ node: SKShapeNode, _ points: [CGPoint]) {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    node.path = path
  }

  /// Rounded, solid limbs remain legible at court size, with a visible elbow or knee bend.
  private func limb(_ node: SKShapeNode, _ points: [CGPoint], width: CGFloat) {
    let path = CGMutablePath()
    path.addLines(between: points)
    node.path = path.copy(
      strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
  }

  private func elbow(from shoulder: CGPoint, to wrist: CGPoint, outward: CGFloat) -> CGPoint {
    let dx = wrist.x - shoulder.x
    let dy = wrist.y - shoulder.y
    let length = max(1, hypot(dx, dy))
    let bend = min(6, max(1.5, 10 - length * 0.22)) * outward
    return CGPoint(
      x: (shoulder.x + wrist.x) / 2 - dy / length * bend,
      y: (shoulder.y + wrist.y) / 2 + dx / length * bend)
  }

  func draw(time: Double, velocity: Vec, reduceMotion: Bool, split: Double? = nil,
    servePreparing: Bool = false, serveToss: Double? = nil, serveLanding: Double? = nil,
    frustration: Int = 0, affirmation: Bool = false, reactionTime: Double = 0,
    explosiveServe: Bool = false, surprise: Double = 0, acknowledge: Bool = false) {
    var pose =
      reduceMotion
      ? (motion.timeUntilContact != nil || motion.timeAfterContact != nil
        ? motion.contactPose : motion.readyPose) : motion.pose
    if frustration > 0 || affirmation {
      pose = motion.readyPose
      pose.grip = Vec(x: 18, y: frustration > 0 ? 17 : 23)
      pose.racketAngle = -0.65
      pose.shoulderTurn = frustration > 0 ? 0.18 : 0
      pose.kneeBend = frustration > 0 ? 0.85 : 0.15
      pose.supportHandOnGrip = false
    }
    if let landing = serveLanding {
      pose.kneeBend += sin(landing * .pi) * 0.65
    }
    let jump = reduceMotion ? 0 : ServeMotion.jumpHeight(tossProgress: serveToss, landingProgress: serveLanding) * (explosiveServe ? 1.4 : 1)
    let hop = reduceMotion ? 0 : split.map { sin($0 * .pi) } ?? 0
    silhouette.zRotation = surprise * 0.19
    silhouette.position.y = hop * 2.5 + jump
    shadow.setScale(1 - jump * 0.015)
    let running = serveLanding != nil ? 0 : min(1, velocity.length / 6)
    let stride = reduceMotion ? 0 : sin(time * 17) * running
    let lean = clamp(velocity.x / 6, -1, 1) * (courtSide == 0 ? 1.0 : -1.0) * 2
    let shift = pose.weightShift + lean
    let crouch = pose.kneeBend * 3 + hop * 1.5
    let shoulderY = 33 - crouch
    let hipY = 20 - crouch
    let turn = pose.shoulderTurn
    let shoulderWidth = 10 - abs(turn) * 2.7
    let shoulderLeft = CGPoint(x: shift - shoulderWidth, y: shoulderY + turn * 2)
    let shoulderRight = CGPoint(x: shift + shoulderWidth, y: shoulderY - turn * 2)
    let hipLeft = CGPoint(x: shift * 0.5 - 4.3, y: hipY)
    let hipRight = CGPoint(x: shift * 0.5 + 4.3, y: hipY)
    let stanceWidth = 8 + pose.kneeBend * 3 + hop * 2
    let leftFoot = CGPoint(x: -stanceWidth - stride * 2, y: 2 + max(0, stride) * 4)
    let kick = reduceMotion ? 0 : serveLanding.map { sin($0 * .pi) * 11 } ?? 0
    let rightFoot = CGPoint(x: stanceWidth - stride * 2 + kick * 0.3,
      y: 2 + max(0, -stride) * 4 + kick)
    let leftKnee = CGPoint(x: -7 + shift * 0.4, y: 10 - crouch + stride * 2)
    let rightKnee = CGPoint(x: 7 + shift * 0.4, y: 10 - crouch - stride * 2)
    limb(leftLeg, [hipLeft, leftKnee, leftFoot], width: 4.8)
    limb(rightLeg, [hipRight, rightKnee, rightFoot], width: 4.8)
    limb(leftSock, [CGPoint(x: leftFoot.x, y: leftFoot.y + 4), leftFoot], width: 4.9)
    limb(rightSock, [CGPoint(x: rightFoot.x, y: rightFoot.y + 4), rightFoot], width: 4.9)
    for (shoe, foot) in [(leftShoe, leftFoot), (rightShoe, rightFoot)] {
      shoe.path = CGPath(
        roundedRect: CGRect(x: foot.x - 3.5, y: foot.y - 3, width: 8, height: 4.6),
        cornerWidth: 1.8, cornerHeight: 1.8, transform: nil)
      shoe.strokeColor = ink.withAlphaComponent(0.6)
      shoe.lineWidth = 0.6
    }
    polygon(
      shorts,
      [
        CGPoint(x: shift * 0.5 - 7, y: hipY + 3), CGPoint(x: shift * 0.5 + 7, y: hipY + 3),
        CGPoint(x: shift * 0.5 + 7.8, y: hipY - 5), CGPoint(x: shift * 0.5 + 1, y: hipY - 5),
        CGPoint(x: shift * 0.5, y: hipY - 2), CGPoint(x: shift * 0.5 - 1, y: hipY - 5),
        CGPoint(x: shift * 0.5 - 7.8, y: hipY - 5),
      ])
    polygon(
      shirt,
      [
        shoulderLeft, CGPoint(x: shift - 4, y: shoulderY + 3),
        CGPoint(x: shift + 4, y: shoulderY + 3), shoulderRight,
        CGPoint(x: shift * 0.5 + 6.5, y: hipY), CGPoint(x: shift * 0.5 - 6.5, y: hipY),
      ])
    polygon(
      shirtPanel,
      [
        shoulderLeft, CGPoint(x: shoulderLeft.x + 3, y: shoulderLeft.y - 1),
        CGPoint(x: shift * 0.5 - 3.8, y: hipY), CGPoint(x: shift * 0.5 - 6.5, y: hipY),
      ])
    limb(
      hem,
      [CGPoint(x: shift * 0.5 - 6, y: hipY + 0.5), CGPoint(x: shift * 0.5 + 6, y: hipY + 0.5)],
      width: 1)
    limb(
      collar,
      [
        CGPoint(x: shift - 3.5, y: shoulderY + 2), CGPoint(x: shift, y: shoulderY),
        CGPoint(x: shift + 3.5, y: shoulderY + 2),
      ], width: 1.1)
    chestMark.path = CGPath(
      rect: CGRect(x: shift + 3, y: shoulderY - 5, width: 2.4, height: 1.3), transform: nil)
    // A back view for the near player; a face and shirt insignia for the far player.
    chestMark.isHidden = courtSide == 0
    let headX = shift + turn * 1.6 + (frustration > 0 && !reduceMotion ? sin(reactionTime * 8) * 1.4 : 0)
    let headY = shoulderY + (frustration > 0 ? 7.0 : 9.0)
    neck.position = CGPoint(x: shift, y: shoulderY + 3)
    head.position = CGPoint(x: headX, y: headY)
    hair.path = CGPath(
      ellipseIn: CGRect(
        x: headX - 5.2, y: headY + (courtSide == 0 ? -2 : 1),
        width: 10.4, height: courtSide == 0 ? 9 : 5.6), transform: nil)
    limb(
      headband, [CGPoint(x: headX - 4.5, y: headY + 2), CGPoint(x: headX + 4.5, y: headY + 2)],
      width: 1.4)
    let features = CGMutablePath()
    if courtSide == 1 {
      features.move(to: CGPoint(x: headX - 2.6, y: headY))
      features.addLine(to: CGPoint(x: headX - 1.3, y: headY))
      features.move(to: CGPoint(x: headX + 1.3, y: headY))
      features.addLine(to: CGPoint(x: headX + 2.6, y: headY))
      features.move(to: CGPoint(x: headX - 1, y: headY - 3))
      if frustration > 0 { features.addLine(to: CGPoint(x: headX, y: headY - 2)) }
      features.addLine(to: CGPoint(x: headX + 1, y: headY - 3))
    }
    if surprise != 0 { features.addEllipse(in: CGRect(x: headX - 1, y: headY - 4, width: 2.4, height: 3)) }
    face.path = features
    let rightWrist = CGPoint(x: pose.grip.x, y: pose.grip.y)
    let leftWrist: CGPoint
    if acknowledge {
      let lift = reduceMotion ? 1 : StrokeAnimation.ease(reactionTime / 0.25)
      leftWrist = CGPoint(x: shoulderLeft.x - 8, y: shoulderY - 4 + 26 * lift)
    } else if frustration > 0 {
      leftWrist = frustration > 1 ? CGPoint(x: headX - 4, y: headY + 1)
        : CGPoint(x: shoulderLeft.x - 8, y: shoulderY + 2)
    } else if affirmation {
      leftWrist = CGPoint(x: shift - 2, y: shoulderY - 3)
    } else if servePreparing {
      let lift = serveToss.map { StrokeAnimation.ease($0 / 0.35) * (1 - StrokeAnimation.ease(($0 - 0.7) / 0.3)) } ?? 0
      leftWrist = CGPoint(x: -14 + 8 * lift, y: 25 + 31 * lift)
    } else if pose.supportHandOnGrip {
      // Two hands spaced along the handle, never floating away from the racket.
      leftWrist = CGPoint(
        x: rightWrist.x - sin(pose.racketAngle) * 4,
        y: rightWrist.y + cos(pose.racketAngle) * 4)
    } else if motion.style == .overhead && motion.timeUntilContact != nil {
      leftWrist = CGPoint(x: shoulderLeft.x + 5, y: shoulderY + 18)
    } else {
      leftWrist = CGPoint(x: shoulderLeft.x - 5 - turn * 3, y: shoulderY - 8 + abs(turn) * 5)
    }
    for (arm, band, hand, shoulder, wrist, outward) in [
      (leftArm, leftBand, leftHand, shoulderLeft, leftWrist, CGFloat(-1)),
      (rightArm, rightBand, rightHand, shoulderRight, rightWrist, CGFloat(1)),
    ] {
      let joint = elbow(from: shoulder, to: wrist, outward: outward)
      limb(arm, [shoulder, joint, wrist], width: 3.6)
      let bandPoint = CGPoint(
        x: wrist.x + (joint.x - wrist.x) * 0.18,
        y: wrist.y + (joint.y - wrist.y) * 0.18)
      limb(band, [bandPoint, wrist], width: 4.1)
      hand.position = wrist
      arm.zPosition = 7
      band.zPosition = 8
      hand.zPosition = 11
    }
    racket.position = rightWrist
    racket.zRotation = pose.racketAngle
    racket.zPosition = 9
    head.zPosition = 6
    hair.zPosition = 6.1
    headband.zPosition = 6.2
    face.zPosition = 6.3
    let centre = pose.racketCentre
    if !reduceMotion, let elapsed = motion.timeAfterContact, elapsed < 0.18 {
      previousRacketCentres.append(CGPoint(x: centre.x, y: centre.y))
      if previousRacketCentres.count > 5 { previousRacketCentres.removeFirst() }
    } else {
      previousRacketCentres.removeAll()
    }
    let arc = CGMutablePath()
    if previousRacketCentres.count > 1 { arc.addLines(between: previousRacketCentres) }
    racketTrail.path = arc
  }
}
