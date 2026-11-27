import RealityKit
import UIKit

/// The curved corner rows join the baseline gallery to the side stands.
struct TerraceCorner {
  let x, z: Float
  var baseline: Int { z < 0 ? 0 : 1 }
  var center: CourtPoint3D { [4.115+x*15.115,0,11.885+z*21.885] }
  func outward(_ angle: Float) -> CourtPoint3D { [x*cos(angle),0,z*sin(angle)] }
  func seatPositions(row: Int) -> [CourtPoint3D] {
    let radius = 0.90+Float(row)*0.89
    let count = max(2,Int(radius * .pi / (2*0.74)))
    return (0..<count).compactMap { index in
      let angle = (Float(index)+0.5) * (.pi/2)/Float(count)
      // Leave a stair aisle through the centre of each fan.
      guard abs(angle - .pi/4)*radius > 0.52 else { return nil }
      return center+outward(angle)*radius+[0,2.77+Float(row)*0.48,0]
    }
  }
  static let all = [TerraceCorner(x:-1,z:-1),TerraceCorner(x:1,z:-1),
                    TerraceCorner(x:-1,z:1),TerraceCorner(x:1,z:1)]
}

/// Each three-dimensional seating section selects the corresponding view of
/// twelve seated human figures. One mesh holds a section's entire audience.
@MainActor final class GrandstandAudience {
  private struct Seat {
    let center: CourtPoint3D
    let appearance: Int
    let scale: Float
    let lean: Float
  }
  @MainActor private final class Section {
    let entity = ModelEntity()
    let seats: [Seat]
    let middle: CourtPoint3D
    let facing: Float
    var bearing = -1
    let end: Int
    let id: Int
    init(seats: [Seat], facing: Float, id: Int, end: Int) {
      self.end = end
      self.id = id
      self.seats = seats
      self.middle = seats.reduce(.zero) { $0+$1.center }/Float(seats.count)
      self.facing = facing
    }
  }

  private static let map: TextureResource? = {
    guard let image = UIImage(named:"grandstand-spectators")?.cgImage else { return nil }
    return try? TextureResource.generate(from:image,options:.init(semantic:.color))
  }()
  private static let standingMap: TextureResource? = {
    guard let image = UIImage(named:"grandstand-ovation")?.cgImage else { return nil }
    return try? TextureResource.generate(from:image,options:.init(semantic:.color))
  }()
  private static var meshes: [Int:MeshResource] = [:]
  let root = Entity()
  private let material: UnlitMaterial
  private lazy var ovationMaterial: UnlitMaterial = {
    var standing = material
    standing.color.texture = Self.standingMap.map { .init($0) }
    return standing
  }()
  private var sections: [Section] = []
  private var lastEye: CourtPoint3D?
  private var lastBeat = -1

  static var available: Bool { map != nil }

  init?(night: Bool) {
    guard let map = Self.map else { return nil }
    var fabric = UnlitMaterial()
    fabric.color = .init(tint:UIColor(white:night ? 0.73 : 0.90,alpha:1),texture:.init(map))
    fabric.opacityThreshold = 0.46
    if #available(iOS 18, *) { fabric.faceCulling = .none }
    material = fabric
    var seed: UInt32 = 93
    func sample() -> UInt32 {
      seed = (1664525 &* seed) &+ 1013904223
      return seed >> 8
    }
    for end in 0..<4 {
      let along = end >= 2
      let outward: CourtPoint3D = along ? [end == 2 ? -1 : 1,0,0] : [0,0,end == 0 ? -1 : 1]
      let across: CourtPoint3D = along ? [0,0,1] : [1,0,0]
      let edge = CourtPoint3D(4.115,0,11.885)+outward*(along ? 15.115 : 21.885)
      let count = along ? 58 : 40, yaw = atan2(outward.x,outward.z)
      for first in stride(from:0,to:count,by:12) {
        var people: [Seat] = []
        for row in 0..<7 {
          let center = edge+outward*(0.9+Float(row)*0.89)+[0,2.35+Float(row)*0.48+0.42,0]
          for i in (first+1)..<min(first+12,count) {
            let x = (Float(i)+0.5-Float(count)*0.5)*0.74
            let seat = Seat(center:center+across*x,appearance:Int(sample()%12),
                            scale:0.88+Float(sample()%24)*0.01,lean:Float(Int(sample()%9)-4)*0.011)
            people.append(seat)
          }
        }
        guard !people.isEmpty else { continue }
        let section = Section(seats:people,facing:yaw,id:sections.count,end:end)
        sections.append(section)
        if #available(iOS 18, *) { section.entity.components.set(DynamicLightShadowComponent(castsShadow:false)) }
        root.addChild(section.entity)
      }
    }
    for corner in TerraceCorner.all {
      let seats = (0..<7).flatMap { row in corner.seatPositions(row:row).map { center in
        Seat(center:center,appearance:Int(sample()%12),scale:0.88+Float(sample()%24)*0.01,
             lean:Float(Int(sample()%9)-4)*0.011)
      } }
      let section = Section(seats:seats,facing:atan2(corner.x,corner.z),id:sections.count,end:corner.baseline)
      if #available(iOS 18, *) { section.entity.components.set(DynamicLightShadowComponent(castsShadow:false)) }
      sections.append(section)
      root.addChild(section.entity)
    }
    face(camera:[4.115,3,28])
  }

  func hideBaselineStand(_ end: Int?) {
    for section in sections { section.entity.isEnabled = section.end != end }
  }

  func face(camera: CourtPoint3D, ovation: Double? = nil, reduceMotion: Bool = false) {
    let beat = ovation.map { reduceMotion ? 0 : Int($0 * 7) } ?? -1
    if beat == lastBeat, let previous = lastEye, simd_distance_squared(camera,previous)<0.16 { return }
    lastBeat = beat
    lastEye = camera
    for section in sections {
      let toEye = camera-section.middle
      let local = simd_quatf(angle:-section.facing,axis:[0,1,0]).act(toEye)
      let radians = atan2(local.x,-local.z)
      let angle = (Int((radians/(.pi/4)).rounded())+8)%8
      // Stand in small waves so adjacent sections do not applaud in unison.
      let standing = beat >= 0 && (reduceMotion || beat >= section.id % 5) && Self.standingMap != nil
      let pose = standing ? 1+(beat+section.id)%4 : 0
      let pitch = atan2(toEye.y,max(0.001,hypot(toEye.x,toEye.z)))
      let tier = pitch < 0.39 ? 0 : pitch < 0.98 ? 1 : 2
      let bearing = (tier*8+angle)*5+pose
      if section.bearing == bearing { continue }
      let key = section.id*120+bearing
      if Self.meshes[key] == nil { Self.meshes[key] = mesh(section,angle:angle,pose:pose,tier:tier) }
      if let mesh = Self.meshes[key] {
        section.entity.model = .init(mesh:mesh,materials:[standing ? ovationMaterial : material])
        section.bearing = bearing
      }
    }
  }

  private func mesh(_ section: Section, angle: Int, pose: Int, tier: Int) -> MeshResource? {
    let y = Float(angle)*Float.pi/4-section.facing
    let right = CourtPoint3D(-cos(y),0,-sin(y))
    let pitch:Float = [0.096,0.68,1.27][tier]
    let vertical = CourtPoint3D(-sin(y)*sin(pitch),cos(pitch),cos(y)*sin(pitch))
    var positions: [CourtPoint3D] = [], uv: [SIMD2<Float>] = [], indices: [UInt32] = []
    for seat in section.seats {
      let halfHeight:Float = pose == 0 ? 0.715 : 1.02
      let center = seat.center+[0,halfHeight*seat.scale-0.525,0]+right*seat.lean
      let w = right*(halfHeight*2/3*seat.scale), h = vertical*halfHeight*seat.scale
      let base = UInt32(positions.count)
      positions += [center-w-h,center+w-h,center+w+h,center-w+h]
      let clap = (pose+seat.appearance/3+Int(abs(seat.lean)*100))%4 >= 2
      let tile = seat.appearance+(pose > 0 && clap ? 12 : 0)
      let columns:Float = pose == 0 ? 12 : 24
      let u = Float(tile)/columns, v = Float(tier*8+angle)/24
      let u0 = u+0.0005, u1 = u+1/columns-0.0005
      let v0 = 1-v-1.0/24+0.0006, v1 = 1-v-0.0006
      uv += [[u0,v0],[u1,v0],[u1,v1],[u0,v1]]
      indices += [base,base+1,base+2,base,base+2,base+3]
    }
    var data = MeshDescriptor()
    data.positions = .init(positions); data.textureCoordinates = .init(uv); data.primitives = .triangles(indices)
    return try? MeshResource.generate(from:[data])
  }
}
