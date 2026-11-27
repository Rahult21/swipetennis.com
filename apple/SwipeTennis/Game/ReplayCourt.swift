import Combine
import RealityKit
import SwiftUI

enum ReplayAngle: String, CaseIterable {
  case you = "You", opponent = "Opponent", neutral = "Neutral"
}

@MainActor struct ReplayCourt: UIViewRepresentable {
  let replay: PointReplay
  let surface: CourtSurface
  var venue: TennisVenue? = nil
  var localSide = 0
  let angle: ReplayAngle
  let seconds: Double
  let playing: Bool
  let playbackID: Int
  let reduceMotion: Bool
  var automatic = false
  var liveStadium: CourtReplayView?
  let onReady: () -> Void

  final class Stage: UIView {
    let stadium: CourtReplayView
    weak var liveHost: UIView?

    init(stadium: CourtReplayView) {
      self.stadium = stadium
      self.liveHost = stadium.superview
      super.init(frame: .zero)
      stadium.isReviewing = true
      stadium.playbackID = -1
      stadium.lastTime = -1
      addSubview(stadium)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
      super.layoutSubviews()
      stadium.frame = bounds
    }
  }

  func makeUIView(context: Context) -> Stage {
    let stage = Stage(stadium: liveStadium ?? CourtReplayView(surface: surface, venue: venue, localSide: localSide))
    stage.stadium.whenRendering(onReady)
    return stage
  }

  static func dismantleUIView(_ stage: Stage, coordinator: ()) {
    let stadium = stage.stadium
    stadium.finishReview()
    if let host = stage.liveHost {
      host.insertSubview(stadium, at: 0)
      stadium.frame = host.bounds
      host.setNeedsLayout()
    }
  }

  func updateUIView(_ stage: Stage, context: Context) {
    let view = stage.stadium
    guard let frame = replay.frame(at: seconds) else { return }
    let beat = replay.strikes.last.flatMap { strike in
      strike.power.map { _ in seconds - strike.time }
    }
    let handshake = replay.ceremonyStart.map { seconds >= $0 } ?? false
    view.draw(frame, angle: angle, reduceMotion: reduceMotion, powerBeat: beat, handshake:handshake,
      featuredStrike: automatic && angle == .neutral ? replay.strikes.last : nil, time:seconds)
    for (index, dot) in view.powerTrail.enumerated() {
      let lag = Double(index + 1) * PointReplay.tick * 1.5
      dot.isEnabled = !reduceMotion && (beat ?? -1) >= lag && (beat ?? 2) <= 0.48
      if dot.isEnabled, let past = replay.frame(at: seconds - lag) { dot.position = past.ball }
    }
    if playing, playbackID == view.playbackID, seconds > view.lastTime {
      for hit in replay.strikes where hit.time > view.lastTime && hit.time <= seconds {
        let x = angle == .opponent ? PracticeEngine.width - Double(hit.point.x) : Double(hit.point.x)
        Immersion.shared.playHit(x: x, gain: hit.gain, blocked:hit.blocked)
      }
    }
    view.playbackID = playbackID; view.lastTime = seconds
  }
}

@MainActor final class CourtReplayView: ARView {
  private let court = AnchorEntity(world: .zero)
  private let scenery = Entity()
  private static var venueTemplate: (venue: TennisVenue, guides: Bool, scenery: Entity)?
  private let camera = PerspectiveCamera()
  private let impression: ModelEntity
  private let ball: ModelEntity
  private let shadow: ModelEntity
  private let players: [ReplayAthlete]
  var hasFittedPlayers: Bool { players.allSatisfy(\.usesAnatomicalMesh) }
  let powerTrail: [ModelEntity]
  private var firstFrame: Cancellable?
  private var checkingFrame = false
  private var readinessID = UUID()
  var isReviewing = false
  var playbackID = -1
  var lastTime = -1.0

  init(surface: CourtSurface, venue: TennisVenue? = nil, localSide: Int = 0, studio: Bool = false) {
    let sphere = MeshResource.generateSphere(radius: 1)
    let markColor: UIColor = surface == .clay ? UIColor(red:0.49,green:0.245,blue:0.14,alpha:1)
      : surface == .grass ? UIColor(red:0.35,green:0.40,blue:0.22,alpha:1) : UIColor(white:0.69,alpha:1)
    impression = ModelEntity(mesh:sphere,materials:[SimpleMaterial(color:markColor,roughness:1,isMetallic:false)])
    impression.isEnabled = false
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
    players = [0, 1].map { ReplayAthlete(side: $0, sphere: sphere, shadow: stamp.clone(recursive: true), localSide:localSide) }
    super.init(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    renderOptions.insert(.disableGroundingShadows)
    isUserInteractionEnabled = false
    environment.background = .color(UIColor(red: 0.66, green: 0.79, blue: 0.85, alpha: 1))
    if #available(iOS 18.0, *) { camera.camera.fieldOfViewOrientation = .vertical }
    scene.addAnchor(court)
    court.addChild(camera); court.addChild(ball); court.addChild(shadow); court.addChild(impression)
    powerTrail.forEach { court.addChild($0) }
    players.forEach { court.addChild($0.root) }
    let selected = venue ?? .standard(surface)
    let sun = DirectionalLight()
    let lightPosition: CourtPoint3D
    switch studio ? .harbor : selected {
    case .lawn:
      sun.light.color = UIColor(red:1,green:0.94,blue:0.81,alpha:1)
      sun.light.intensity = 2500; lightPosition = [-9,14,19]
    case .mesa:
      sun.light.color = UIColor(red:1,green:0.86,blue:0.71,alpha:1)
      sun.light.intensity = 2650; lightPosition = [18,16,4]
    case .harbor:
      sun.light.color = UIColor(red:0.95,green:0.98,blue:1,alpha:1)
      sun.light.intensity = 2450; lightPosition = [-6,16,16]
    case .night:
      sun.light.color = UIColor(red:0.84,green:0.90,blue:1,alpha:1)
      sun.light.intensity = 1840; lightPosition = [-13,16,29]
      let rim = DirectionalLight()
      rim.light.intensity = 1180
      rim.light.color = UIColor(red:1,green:0.91,blue:0.80,alpha:1)
      rim.look(at:[4,0,12],from:[19,15,-7],relativeTo:nil)
      court.addChild(rim)
    }
    sun.look(at: [4,0,12], from: lightPosition, relativeTo: nil)
    court.addChild(sun)
    if studio {
      court.addChild(scenery)
      box([4,-0.055,24],[14,0.1,12],UIColor(red:0.18,green:0.28,blue:0.28,alpha:1))
      environment.background = .color(UIColor(red:0.70,green:0.78,blue:0.77,alpha:1))
      let fill = DirectionalLight()
      fill.light.intensity = 950
      fill.light.color = UIColor(red:1,green:0.94,blue:0.88,alpha:1)
      fill.look(at:[4,1,24],from:[6,5,19],relativeTo:nil)
      court.addChild(fill)
      players[1].root.isEnabled = false
    } else {
      let guides = UserDefaults.standard.object(forKey: "guides") as? Bool ?? true
      if selected == .night {
        environment.background = .color(UIColor(red: 0.055, green: 0.075, blue: 0.16, alpha: 1))
      }
      // Reuse immutable meshes and materials when a point cuts to the replay camera.
      if let cached = Self.venueTemplate, cached.venue == selected, cached.guides == guides {
        court.addChild(cached.scenery.clone(recursive: true))
      } else {
        buildCourt(selected, guides: guides)
        Self.venueTemplate = (selected, guides, scenery.clone(recursive: true))
        court.addChild(scenery)
      }
    }
  }
  @MainActor required dynamic init(frame frameRect: CGRect) { fatalError("Use init(surface:)") }
  @MainActor required dynamic init?(coder decoder: NSCoder) { fatalError("Use init(surface:)") }

  func whenRendering(_ ready: @escaping () -> Void) { whenFrameIsReady { _ in ready() } }

  func whenFrameIsReady(_ ready: @escaping (UIImage) -> Void) {
    let id = UUID()
    readinessID = id
    checkingFrame = false
    firstFrame = scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.readinessID == id, self.firstFrame != nil, !self.checkingFrame,
              self.window != nil, self.bounds.width > 0 else { return }
        self.checkingFrame = true
        self.snapshot(saveToHDR: false) { [weak self] image in
          Task { @MainActor in
            guard let self, self.readinessID == id else { return }
            if let image, let frame = image.cgImage, Self.hasCourtPixels(frame) {
              self.firstFrame?.cancel()
              self.firstFrame = nil
              ready(image)
            } else {
              // RealityKit can deliver scene updates while its drawable still contains only sky.
              try? await Task.sleep(for: .milliseconds(100))
            }
            guard self.readinessID == id else { return }
            self.checkingFrame = false
          }
        }
      }
    }
  }

  private static func hasCourtPixels(_ frame: CGImage) -> Bool {
    var pixels = [UInt8](repeating: 0, count: 12*12*4)
    return pixels.withUnsafeMutableBytes { buffer in
      guard let context = CGContext(data: buffer.baseAddress, width: 12, height: 12, bitsPerComponent: 8,
                                    bytesPerRow: 48, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
      context.draw(frame, in: CGRect(x: 0, y: 0, width: 12, height: 12))
      let values = buffer.bindMemory(to: UInt8.self)
      return (0..<3).contains { channel in
        let samples = stride(from: channel, to: values.count, by: 4).map { Int(values[$0]) }
        return (samples.max() ?? 0) - (samples.min() ?? 0) > 28
      }
    }
  }

  func finishReview() {
    readinessID = UUID()
    firstFrame?.cancel()
    firstFrame = nil
    isReviewing = false
    powerTrail.forEach { $0.isEnabled = false }
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
    node.position = at; scenery.addChild(node)
  }
  private func buildCourt(_ venue: TennisVenue, guides: Bool) {
    let surface = venue.surface
    let night = venue == .night
    let green = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
    let base = night ? UIColor(red:0.17,green:0.24,blue:0.53,alpha:1) : surface == .grass ? green : surface == .clay ? UIColor(red: 0.70, green: 0.34, blue: 0.21, alpha: 1) : UIColor(red: 0.18, green: 0.43, blue: 0.61, alpha: 1)
    let surround: UIColor
    switch venue {
    case .lawn: surround = UIColor(red:0.12,green:0.28,blue:0.24,alpha:1)
    case .harbor: surround = UIColor(red:0.14,green:0.39,blue:0.43,alpha:1)
    case .mesa: surround = UIColor(red:0.52,green:0.27,blue:0.18,alpha:1)
    case .night: surround = UIColor(red:0.15,green:0.13,blue:0.26,alpha:1)
    }
    box([4.115,-0.06,11.885], [180,0.09,185], surround)
    let asset: String
    switch venue { case .lawn: asset = "lawn"; case .mesa: asset = "mesa"; case .harbor: asset = "harbor"; case .night: asset = "night" }
    var material = SimpleMaterial(color:base,roughness:surface == .hard ? 0.78 : 0.98,isMetallic:false)
    if let bitmap = UIImage(named:"court-" + asset)?.cgImage,
       let texture = try? TextureResource.generate(from:bitmap,options:.init(semantic:.color)) {
      material.color = .init(tint:.white,texture:.init(texture))
    }
    let playingSurface = ModelEntity(mesh:.generatePlane(width:10.97,depth:23.77),materials:[material])
    playingSurface.position = [4.115,-0.003,11.885]
    scenery.addChild(playingSurface)
    if guides {
      var margin = UnlitMaterial(color:.systemYellow)
      margin.blending = .transparent(opacity:.init(floatLiteral:0.055))
      for x: Float in [0.425,7.805] {
        let lane = ModelEntity(mesh:.generatePlane(width:0.85,depth:23.77), materials:[margin])
        lane.position = [x,-0.001,11.885]; scenery.addChild(lane)
      }
    }
    // Architecture changes with the venue. Keep the player's end and sightlines clear.
    for end: Float in [-1,1] {
      let z: Float = 11.885 + end*27
      switch venue {
      case .lawn:
        for bay in 0..<7 {
          let x = -8 + Float(bay)*4
          box([x,6,z],[3.75,3.4,1.8],surround)
          box([x,7.8,z],[4.1,0.24,2.9],UIColor(white:0.83,alpha:1))
        }
      case .mesa:
        for tower in 0..<6 {
          let x = -10 + Float(tower)*5.4
          box([x,4,z],[1.15,8.0,2.2],surround)
          box([x+2.3,7.9,z],[4.7,0.35,2.2],surround)
        }
      case .harbor:
        for bay in 0..<5 {
          box([-7+Float(bay)*5.3,7.6,z],[4.7,0.18,4.2],.white)
          box([-7+Float(bay)*5.3,5.1,z+end],[0.16,5,0.16],.lightGray)
        }
      case .night:
        for x: Float in [-12,20] {
          box([x,5.8,z],[0.26,11.6,0.26],.darkGray)
          box([x,11.7,z],[3.3,0.62,0.35],.white)
        }
        box([4.1,6.4,z],[33,0.12,0.4],.systemIndigo)
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
    scenery.addChild(mesh.model(color: UIColor(white: 0.13, alpha: 1))); scenery.addChild(tape.model(color: chalk))
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
    scenery.addChild(terraces.model(color: UIColor(red: 0.39,green: 0.43,blue: 0.40,alpha: 1)))
    scenery.addChild(crowd.model())
    scenery.addChild(seats[0].model(color: UIColor(red: 0.11,green: 0.34,blue: 0.32,alpha: 1)))
    scenery.addChild(seats[1].model(color: UIColor(red: 0.24,green: 0.47,blue: 0.42,alpha: 1)))
    let braces = ReplayMeshLines()
    for x: Float in [-11,19.23] {
      box([x,1.12,11.885], [0.20,2.24,44], wall)
      for z in stride(from: -10.0, through: 34.0, by: 3.0) {
        braces.box(center: [x,1.16,Float(z)], size: [0.24,2.32,0.055])
      }
    }
    scenery.addChild(braces.model(color: UIColor(red: 0.24,green: 0.40,blue: 0.37,alpha: 1)))
    // Umpire chair, player benches and tunnel lettering give the stadium a human scale.
    let rails = ReplayMeshLines()
    for x: Float in [10.75,11.45] {
      for z: Float in [11.4,12.2] { rails.line([x,0,z],[x,2.45,z],radius:0.045) }
      rails.line([x,0.1,12.9],[x,2.25,12.15],radius:0.038)
    }
    for step in 0..<7 { let t = Float(step)/7
      rails.line([10.75,0.2+2*t,12.86-0.75*t],[11.45,0.2+2*t,12.86-0.75*t],radius:0.033)
    }
    scenery.addChild(rails.model(color:.lightGray))
    box([11.1,2.25,11.8],[0.85,0.11,1.0],wall); box([11.43,2.54,11.8],[0.11,0.64,1],wall)
    for z: Float in [7.4,16.3] {
      box([11.8,0.48,z],[0.62,0.12,2.25],chalk)
      for dz: Float in [-0.82,0.82] { box([11.8,0.22,z+dz],[0.46,0.44,0.085],wall) }
    }
    let name = ModelEntity(mesh:.generateText(venue.rawValue.uppercased(),extrusionDepth:0.012,
      font:.systemFont(ofSize:0.54,weight:.semibold)),materials:[SimpleMaterial(color:chalk,roughness:0.9,isMetallic:false)])
    name.position = [4.115-name.visualBounds(relativeTo:nil).extents.x/2,1.08,-9.82]
    scenery.addChild(name)
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
        tree.scale = [3.0+distance*0.29,height,3.1]; scenery.addChild(tree)
      }
    }
  }

  func liveCamera(side: Int, intro: Float, nearX: Float, reduceMotion: Bool) {
    let aspect = max(0.32,Float(bounds.width / max(bounds.height,1)))
    let sign: Float = side == 0 ? 1 : -1
    let wide = min(1,max(0,(aspect-0.75)/0.55))
    let fov: Float = 53 + 5*wide
    let target = CourtPoint3D(4.115,0.55,11.885+sign*(2.1+3.4*wide))
    let follow = reduceMotion ? 0 : min(0.95,max(-0.95,(nearX-4.115)*0.23))
    let t = reduceMotion ? 1 : intro
    let direction = simd_normalize(CourtPoint3D(follow*0.11 + (1-t)*0.38,0.75-0.17*wide+(1-t)*2.4,sign))
    let right = simd_normalize(simd_cross([0,1,0],direction)), up = simd_cross(direction,right)
    let tangent = tan(fov * .pi / 360)
    var distance: Float = 12
    for x: Float in [-1.64,9.87] { for z: Float in [-2.4,26.4] {
      let v = CourtPoint3D(x,0,z)-target
      distance = max(distance,simd_dot(direction,v) + max(abs(simd_dot(right,v))/(aspect*tangent),abs(simd_dot(up,v))/tangent)*1.06)
    }}
    camera.camera.fieldOfViewInDegrees = fov
    camera.look(at:target, from: target+direction*(distance+(1-t)*2.8), relativeTo:nil)
  }
  func portraitCamera(azimuth: Float) {
    camera.camera.fieldOfViewInDegrees = 35
    let target = CourtPoint3D(4.115, 0.98, 24.6)
    let eye = target + CourtPoint3D(3.42 * sin(azimuth), 0.26, -3.42 * cos(azimuth))
    camera.look(at:target,from:eye,relativeTo:nil)
  }

  func drawStudio(_ frame: RallyFrame, origin: CourtPoint3D, azimuth: Float, serve: Bool) {
    let centre = CourtPoint3D(origin.x,0,origin.z)
    players[0].draw(frame.near); players[1].draw(frame.far)
    ball.position = frame.ball
    ball.scale = .init(repeating:0.034)
    ball.isEnabled = true
    shadow.isEnabled = true
    shadow.position = [frame.ball.x,0.009,frame.ball.z]
    shadow.scale = [0.18,1,0.13]
    let height: Float = serve ? 1.52 : 1.10
    let target = centre + CourtPoint3D(0,height,0)
    camera.camera.fieldOfViewInDegrees = 38
    let distance: Float = serve ? 4.95 : 3.9
    camera.look(at:target,from:target+[distance*sin(azimuth),0.25,-distance*cos(azimuth)],relativeTo:nil)
  }

  func draw(_ frame: RallyFrame, angle: ReplayAngle, reduceMotion: Bool, powerBeat: Double?, handshake: Bool = false, featuredStrike: RecordedStrike? = nil, time: Double = 0, live: Bool = false) {
    players[0].draw(frame.near,handshake:handshake); players[1].draw(frame.far,handshake:handshake)
    ball.isEnabled = !handshake; shadow.isEnabled = !handshake
    impression.isEnabled = frame.bounce != nil && !handshake
    if let mark = frame.bounce, !handshake {
      let v = mark.visibility
      impression.position = [Float(mark.position.x),0.0001,Float(mark.position.y)]
      impression.scale = [0.055*v,0.001,0.115*v]
      impression.orientation = simd_quatf(angle:mark.direction,axis:[0,1,0])
    }
    ball.position = frame.ball
    shadow.position = [frame.ball.x,0.009,frame.ball.z]
    let shadeSize = 0.13 + 0.045 * min(4,frame.ball.y)
    shadow.scale = [shadeSize,1,shadeSize]
    if live {
      ball.scale = .init(repeating:max(0.044,min(0.084,simd_distance(camera.position,frame.ball)*0.0025)))
      return
    }
    let near = (frame.near[.leftHip] + frame.near[.rightHip]) / 2
    let far = (frame.far[.leftHip] + frame.far[.rightHip]) / 2
    let position: CourtPoint3D, target: CourtPoint3D
    let beat = featuredStrike.map { time - $0.time } ?? powerBeat
    let focus = reduceMotion ? 0 : Float(beat.map {
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
      let hitter = featuredStrike?.hitter == 1 ? far : near
      let facing: Float = featuredStrike?.hitter == 1 ? -1 : 1
      let courtside = hitter + CourtPoint3D(3.55*facing,1.35,-3.15*facing)
      let strikeTarget = CourtPoint3D(hitter.x,1.40,hitter.z-0.26*facing)
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
    if handshake {
      camera.camera.fieldOfViewInDegrees = 42
      camera.look(at:[4.115,1.03,11.885],from:[8.6,2.0,13.55],relativeTo:nil)
    }
    // At the far baseline the physical ball would occupy less than one pixel on smaller phones.
    let radius = max(0.034,min(0.079,simd_distance(position,frame.ball)*0.0023))
    ball.scale = .init(repeating: radius)
  }
}
