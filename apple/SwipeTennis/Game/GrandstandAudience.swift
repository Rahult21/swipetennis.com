import RealityKit
import UIKit

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
    let id: Int
    init(seats: [Seat], facing: Float, id: Int) {
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
  private static var meshes: [Int:MeshResource] = [:]
  let root = Entity()
  private let material: UnlitMaterial
  private var sections: [Section] = []
  private var lastEye: CourtPoint3D?

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
        let section = Section(seats:people,facing:yaw,id:sections.count)
        sections.append(section)
        if #available(iOS 18, *) { section.entity.components.set(DynamicLightShadowComponent(castsShadow:false)) }
        root.addChild(section.entity)
      }
    }
    face(camera:[4.115,3,28])
  }

  func face(camera: CourtPoint3D) {
    if let previous = lastEye, simd_distance_squared(camera,previous)<0.16 { return }
    lastEye = camera
    for section in sections {
      let toEye = camera-section.middle
      let local = simd_quatf(angle:-section.facing,axis:[0,1,0]).act(toEye)
      let radians = atan2(local.x,-local.z)
      let angle = (Int((radians/(.pi/4)).rounded())+8)%8
      if section.bearing == angle { continue }
      let key = section.id*8+angle
      if Self.meshes[key] == nil { Self.meshes[key] = mesh(section,angle:angle) }
      if let mesh = Self.meshes[key] {
        section.entity.model = .init(mesh:mesh,materials:[material])
        section.bearing = angle
      }
    }
  }

  private func mesh(_ section: Section, angle: Int) -> MeshResource? {
    let y = Float(angle)*Float.pi/4-section.facing
    let right = CourtPoint3D(-cos(y),0,-sin(y))
    var positions: [CourtPoint3D] = [], uv: [SIMD2<Float>] = [], indices: [UInt32] = []
    for seat in section.seats {
      let center = seat.center+[0,0.19*seat.scale,0]+right*seat.lean
      let w = right*(0.475*seat.scale), h = CourtPoint3D(0,0.715*seat.scale,0)
      let base = UInt32(positions.count)
      positions += [center-w-h,center+w-h,center+w+h,center-w+h]
      let u = Float(seat.appearance)/12, v = Float(angle)/8
      let u0 = u+0.0005, u1 = u+1.0/12-0.0005
      let v0 = 1-v-1.0/8+0.0006, v1 = 1-v-0.0006
      uv += [[u0,v0],[u1,v0],[u1,v1],[u0,v1]]
      indices += [base,base+1,base+2,base,base+2,base+3]
    }
    var data = MeshDescriptor()
    data.positions = .init(positions); data.textureCoordinates = .init(uv); data.primitives = .triangles(indices)
    return try? MeshResource.generate(from:[data])
  }
}
