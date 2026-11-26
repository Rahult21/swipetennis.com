import SpriteKit

/// A small articulated vector athlete. Limbs, hands and racket share the same pose, rather
/// than animating a detached racket sprite. Works at both court and enlarged preview scales.
@MainActor final class PlayerFigure: SKNode {
  let courtSide: Int
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
  }

  required init?(coder: NSCoder) { fatalError("Use init(courtSide:)") }

  func reset() {
    previousRacketCentres.removeAll()
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

  func draw(pose: AthletePose, project: (CourtPoint3D) -> CGPoint, in scene: SKNode,
    frustration: Int, surprise: Bool, trail: Bool) {
    func joint(_ name: BodyJoint) -> CGPoint { silhouette.convert(project(pose[name]), from: scene) }
    let leftFoot = joint(.leftShoe), rightFoot = joint(.rightShoe)
    let leftKnee = joint(.leftKnee), rightKnee = joint(.rightKnee)
    let hipLeft = joint(.leftHip), hipRight = joint(.rightHip)
    let shoulderLeft = joint(.leftShoulder), shoulderRight = joint(.rightShoulder)
    let shoulderY = (shoulderLeft.y + shoulderRight.y) / 2, hipY = (hipLeft.y + hipRight.y) / 2
    let shift = (shoulderLeft.x + shoulderRight.x) / 2
    shadow.setScale(max(0.65, 1 - CGFloat(min(pose[.leftShoe].y, pose[.rightShoe].y)) / 2))
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
        hipRight, hipLeft,
      ])
    polygon(
      shirtPanel,
      [
        shoulderLeft, CGPoint(x: shoulderLeft.x + 3, y: shoulderLeft.y - 1),
        CGPoint(x: hipLeft.x + 2, y: hipLeft.y), hipLeft,
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
    let headX = joint(.head).x, headY = joint(.head).y
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
    if surprise { features.addEllipse(in: CGRect(x: headX - 1, y: headY - 4, width: 2.4, height: 3)) }
    face.path = features
    let rightWrist = joint(.grip)
    for (arm, band, hand, shoulder, wrist, joint) in [
      (leftArm, leftBand, leftHand, shoulderLeft, joint(.leftHand), joint(.leftElbow)),
      (rightArm, rightBand, rightHand, shoulderRight, rightWrist, joint(.rightElbow)),
    ] {
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
    let centre = joint(.strings), edge = joint(.racketEdge)
    let dx = centre.x - rightWrist.x, dy = centre.y - rightWrist.y
    let shaft = max(0.01, hypot(dx, dy))
    racket.zRotation = atan2(-dx, dy)
    racket.yScale = shaft / 19
    racket.xScale = max(0.19, abs((edge.x - centre.x) * dy - (edge.y - centre.y) * dx) / shaft / 6.5)
    racket.zPosition = 9
    head.zPosition = 6
    hair.zPosition = 6.1
    headband.zPosition = 6.2
    face.zPosition = 6.3
    if trail {
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
