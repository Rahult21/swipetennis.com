import Combine
import RealityKit
import SwiftUI

enum ReplayAngle: String, CaseIterable {
  case you = "You", opponent = "Opponent", neutral = "Neutral"
}

@MainActor struct ReplayCourt: UIViewRepresentable {
  let replay: PointReplay
  let surface: CourtSurface
  let angle: ReplayAngle
  let seconds: Double
  let playing: Bool
  let playbackID: Int
  let reduceMotion: Bool
  let onReady: () -> Void

  func makeUIView(context: Context) -> CourtReplayView {
    let view = CourtReplayView(surface: surface)
    view.whenRendering(onReady)
    return view
  }
  func updateUIView(_ view: CourtReplayView, context: Context) {
    guard let frame = replay.frame(at: seconds) else { return }
    let beat = replay.strikes.last.flatMap { strike in
      strike.power.map { _ in seconds - strike.time }
    }
    view.draw(frame, angle: angle, reduceMotion: reduceMotion, powerBeat: beat)
    for (index, dot) in view.powerTrail.enumerated() {
      let lag = Double(index + 1) * PointReplay.tick * 1.5
      dot.isEnabled = !reduceMotion && (beat ?? -1) >= lag && (beat ?? 2) <= 0.48
      if dot.isEnabled, let past = replay.frame(at: seconds - lag) { dot.position = past.ball }
    }
    if playing, playbackID == view.playbackID, seconds > view.lastTime {
      for hit in replay.strikes where hit.time > view.lastTime && hit.time <= seconds {
        let x = angle == .opponent ? PracticeEngine.width - Double(hit.point.x) : Double(hit.point.x)
        Immersion.shared.playHit(x: x, gain: hit.gain)
      }
    }
    view.playbackID = playbackID; view.lastTime = seconds
  }
}

@MainActor final class CourtReplayView: ARView {
  private let court = AnchorEntity(world: .zero)
  private let camera = PerspectiveCamera()
  private let ball: ModelEntity
  private let shadow: ModelEntity
  private let players: [ReplayAthlete]
  let powerTrail: [ModelEntity]
  private var firstFrame: Cancellable?
  var playbackID = -1
  var lastTime = -1.0

  init(surface: CourtSurface) {
    let sphere = MeshResource.generateSphere(radius: 1)
    ball = ModelEntity(mesh: sphere, materials: [SimpleMaterial(color: UIColor(red: 0.90, green: 0.99, blue: 0.16, alpha: 1), roughness: 0.85, isMetallic: false)])
    powerTrail = (0..<6).map { index in
      let material = UnlitMaterial(color: UIColor(red: 0.96, green: 0.98, blue: 0.52, alpha: 0.45 - CGFloat(index)*0.055))
      let dot = ModelEntity(mesh: sphere, materials: [material])
      dot.scale = .init(repeating: 0.035 - Float(index)*0.004)
      dot.isEnabled = false
      return dot
    }
    let stamp = Self.shadowStamp()
    shadow = stamp
    players = [0, 1].map { ReplayAthlete(side: $0, sphere: sphere, shadow: stamp.clone(recursive: true)) }
    super.init(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    isUserInteractionEnabled = false
    environment.background = .color(UIColor(red: 0.66, green: 0.79, blue: 0.85, alpha: 1))
    if #available(iOS 18.0, *) { camera.camera.fieldOfViewOrientation = .vertical }
    scene.addAnchor(court)
    court.addChild(camera); court.addChild(ball); court.addChild(shadow)
    powerTrail.forEach { court.addChild($0) }
    players.forEach { court.addChild($0.root) }
    let sun = DirectionalLight()
    sun.light.intensity = 2300
    sun.look(at: [4,0,12], from: [-6,13,18], relativeTo: nil)
    court.addChild(sun)
    buildCourt(surface)
  }
  @MainActor required dynamic init(frame frameRect: CGRect) { fatalError("Use init(surface:)") }
  @MainActor required dynamic init?(coder decoder: NSCoder) { fatalError("Use init(surface:)") }

  func whenRendering(_ ready: @escaping () -> Void) {
    firstFrame = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.firstFrame != nil, self.bounds.width > 0 else { return }
        self.firstFrame?.cancel(); self.firstFrame = nil
        ready()
      }
    }
  }

  private static func shadowStamp() -> ModelEntity {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
    let image = renderer.image { context in
      let colors = [UIColor.black.withAlphaComponent(0.46).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0,1]) {
        context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 32,y: 32), startRadius: 0,
          endCenter: CGPoint(x: 32,y: 32), endRadius: 32, options: [])
      }
    }
    var mat = UnlitMaterial()
    if let cg = image.cgImage, let texture = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) {
      mat.color = .init(tint: .white, texture: .init(texture))
    } else { mat.color = .init(tint: .black.withAlphaComponent(0.18)) }
    mat.blending = .transparent(opacity: .init(floatLiteral: 1))
    return ModelEntity(mesh: .generatePlane(width: 1, depth: 1), materials: [mat])
  }

  private func box(_ at: CourtPoint3D, _ size: CourtPoint3D, _ color: UIColor) {
    let node = ModelEntity(mesh: .generateBox(size: size), materials: [SimpleMaterial(color: color, roughness: 1, isMetallic: false)])
    node.position = at; court.addChild(node)
  }
  private func buildCourt(_ surface: CourtSurface) {
    let green = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
    let base = surface == .grass ? green : surface == .clay ? UIColor(red: 0.70, green: 0.34, blue: 0.21, alpha: 1) : UIColor(red: 0.18, green: 0.43, blue: 0.61, alpha: 1)
    let surround = UIColor(red: 0.12, green: 0.28, blue: 0.24, alpha: 1)
    box([4.115,-0.06,11.885], [180,0.09,185], surround)
    box([4.115,-0.014,11.885], [10.97,0.022,23.77], base)
    if surface == .grass {
      for i in stride(from: 0, to: 8, by: 2) {
        box([4.115,-0.003,23.77*(Float(i)+0.5)/8], [10.97,0.004,23.77/8], UIColor(red: 0.205, green: 0.45, blue: 0.335, alpha: 1))
      }
    }
    let chalk = UIColor(white: 0.94, alpha: 1)
    for x: Float in [-1.37,0,8.23,9.60] { box([x,0.002,11.885], [0.05,0.005,23.77], chalk) }
    for z: Float in [0,23.77] {
      box([4.115,0.003,z], [10.97,0.005,0.10], chalk)
      box([4.115,0.004,z == 0 ? 0.07 : z-0.07], [0.05,0.005,0.14], chalk)
    }
    for z: Float in [5.485,18.285] { box([4.115,0.003,z], [8.23,0.005,0.05], chalk) }
    box([4.115,0.004,11.885], [0.05,0.005,12.8], chalk)
    let mesh = ReplayMeshLines(), tape = ReplayMeshLines()
    let x0: Float = -2.28, width: Float = 12.79, netZ: Float = 11.885
    func height(_ u: Float) -> Float { 0.914 + 0.156 * pow(2*u-1, 2) }
    for i in 0...154 {
      let u = Float(i)/154, x = x0 + u * width
      mesh.line([x,0.025,netZ], [x,height(u),netZ], radius: 0.0045)
    }
    for i in 0..<16 {
      let a = Float(i)/16, b = Float(i+1)/16
      for j in 1...12 {
        let y = Float(j)/13
        mesh.line([x0+a*width, height(a)*y, netZ], [x0+b*width, height(b)*y, netZ], radius: 0.004)
      }
      tape.line([x0+a*width,height(a),netZ], [x0+b*width,height(b),netZ], radius: 0.025)
    }
    court.addChild(mesh.model(color: UIColor(white: 0.13, alpha: 1))); court.addChild(tape.model(color: chalk))
    for x in [x0, x0+width] { box([x,0.54,netZ], [0.085,1.08,0.085], surround) }
    let wall = UIColor(red: 0.075, green: 0.20, blue: 0.19, alpha: 1)
    let seats = [ReplayMeshLines(), ReplayMeshLines()]
    let crowd = ReplayCrowd()
    let terraces = ReplayMeshLines()
    // Each stand faces the court. Breaks between seating sections remain open as aisles.
    for end in 0..<4 {
      let sideStand = end >= 2
      let outward: CourtPoint3D = sideStand ? [end == 2 ? -1 : 1,0,0] : [0,0,end == 0 ? -1 : 1]
      let across: CourtPoint3D = sideStand ? [0,0,1] : [1,0,0]
      let boundary = CourtPoint3D(4.115,0,11.885) + outward * (sideStand ? 15.115 : 21.885)
      let count = sideStand ? 58 : 40
      let width = Float(count)*0.74
      let yaw = atan2(outward.x,outward.z)
      func size(_ w: Float, _ h: Float, _ d: Float) -> CourtPoint3D { sideStand ? [d,h,w] : [w,h,d] }
      if !sideStand {
        box(boundary + [0,1.12,0],size(width,2.24,0.28),wall)
        box(boundary + [0,2.25,0],size(width,0.06,0.30),chalk)
      }
      for row in 0..<7 {
        let rise = 2.35 + Float(row)*0.48
        let center = boundary + outward*(0.9 + Float(row)*0.89)
        terraces.box(center: center+[0,rise/2,0], size: size(width,rise,0.90))
        for seat in 0..<count where seat % 12 != 0 {
          let position = center + across*((Float(seat)+0.5)*0.74-width/2) + [0,rise+0.42,0]
          let batch = seats[(seat/12+row/3)%2]
          batch.box(center: position, size: size(0.54,0.10,0.42))
          batch.box(center: position + outward*0.19 + [0,0.17,0], size: size(0.54,0.35,0.07))
          crowd.seat(at: position + [0,0.05,0], yaw: yaw)
        }
      }
    }
    court.addChild(terraces.model(color: UIColor(red: 0.39,green: 0.43,blue: 0.40,alpha: 1)))
    court.addChild(crowd.model())
    court.addChild(seats[0].model(color: UIColor(red: 0.11,green: 0.34,blue: 0.32,alpha: 1)))
    court.addChild(seats[1].model(color: UIColor(red: 0.24,green: 0.47,blue: 0.42,alpha: 1)))
    let braces = ReplayMeshLines()
    for x: Float in [-11,19.23] {
      box([x,1.12,11.885], [0.20,2.24,44], wall)
      for z in stride(from: -10.0, through: 34.0, by: 3.0) {
        braces.box(center: [x,1.16,Float(z)], size: [0.24,2.32,0.055])
      }
    }
    court.addChild(braces.model(color: UIColor(red: 0.24,green: 0.40,blue: 0.37,alpha: 1)))
    let canopy = MeshResource.generateSphere(radius: 1)
    let leaves = [UIColor(red: 0.15, green: 0.31, blue: 0.25, alpha: 1),
      UIColor(red: 0.22, green: 0.38, blue: 0.29, alpha: 1),
      UIColor(red: 0.28, green: 0.42, blue: 0.32, alpha: 1)].map {
        SimpleMaterial(color: $0, roughness: 1, isMetallic: false)
      }
    for end in 0...1 {
      for i in 0..<19 {
        let distance = Float((i*11 + end*3) % 5)
        let height = 3.6 + Float((i*5+end) % 7)*0.36
        let tree = ModelEntity(mesh: canopy, materials: [leaves[(i+end)%leaves.count]])
        tree.position = [-32+Float(i)*4.1, 3.9, end == 0 ? -20-distance : 43.77+distance]
        tree.scale = [3.0+distance*0.29,height,3.1]; court.addChild(tree)
      }
    }
  }

  func draw(_ frame: RallyFrame, angle: ReplayAngle, reduceMotion: Bool, powerBeat: Double?) {
    players[0].draw(frame.near); players[1].draw(frame.far)
    ball.position = frame.ball
    shadow.position = [frame.ball.x,0.009,frame.ball.z]
    let shadeSize = 0.13 + 0.045 * min(4,frame.ball.y)
    shadow.scale = [shadeSize,1,shadeSize]
    let near = (frame.near[.leftHip] + frame.near[.rightHip]) / 2
    let far = (frame.far[.leftHip] + frame.far[.rightHip]) / 2
    let position: CourtPoint3D, target: CourtPoint3D
    let focus = reduceMotion ? 0 : Float(powerBeat.map {
      StrokeAnimation.ease(($0 + 1.65) / 0.80) * (1 - StrokeAnimation.ease(($0 - 0.085) / 0.74))
    } ?? 0)
    if angle == .neutral {
      let wideTarget = CourtPoint3D(4.115,0.48,14.0)
      let direction = simd_normalize(CourtPoint3D(0.13,1.04,1))
      let right = simd_normalize(simd_cross([0,1,0],direction)), up = simd_cross(direction,right)
      let tanY = tan(Float.pi/6), aspect = max(0.32,Float(bounds.width/max(1,bounds.height)))
      var distance: Float = 15
      for x: Float in [-1.65,9.88] { for z: Float in [-2.2,26.2] {
        let v = CourtPoint3D(x,0,z) - wideTarget
        let margin = max(abs(simd_dot(v,right))/(tanY*aspect),abs(simd_dot(v,up))/tanY)
        distance = max(distance,simd_dot(v,direction)+margin*1.025)
      } }
      let widePosition = wideTarget + direction * distance
      // An independent three-quarter view reads the shoulder turn and airborne feet,
      // then eases back into the full-court shot as the winner travels away.
      let courtside = near + CourtPoint3D(3.55,1.35,-3.15)
      let strikeTarget = CourtPoint3D(near.x,1.46,near.z-0.26)
      position = widePosition + (courtside - widePosition) * focus
      target = wideTarget + (strikeTarget - wideTarget) * focus
      camera.camera.fieldOfViewInDegrees = 60 - 12 * focus
    } else {
      let own = angle == .you ? near : far, other = angle == .you ? far : near
      let sign: Float = angle == .you ? 1 : -1
      let x = reduceMotion ? Float(4.115) : own.x
      let z = reduceMotion ? (angle == .you ? Float(24) : -0.5) : own.z
      position = [x-0.88*sign,2.35,z+3.65*sign]
      target = [x*0.66+other.x*0.34,0.64 + focus*0.65,z-6.8*sign]
      camera.camera.fieldOfViewInDegrees = 58
    }
    camera.look(at: target, from: position, relativeTo: nil)
    // At the far baseline the physical ball would occupy less than one pixel on smaller phones.
    let radius = max(0.034,min(0.079,simd_distance(position,frame.ball)*0.0023))
    ball.scale = .init(repeating: radius)
  }
}
