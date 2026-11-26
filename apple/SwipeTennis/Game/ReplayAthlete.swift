import RealityKit
import UIKit

/// A skinned tennis kit assembled on the same joint landmarks drawn on the live court.
@MainActor final class ReplayAthlete {
  let root = Entity()
  private let torso = Entity(), hips = Entity(), face = Entity(), racket = Entity()
  private let skin: SimpleMaterial, fabric: SimpleMaterial
  private let shorts = SimpleMaterial(color: UIColor(red: 0.10, green: 0.15, blue: 0.19, alpha: 1), roughness: 0.9, isMetallic: false)
  private let white = SimpleMaterial(color: .white, roughness: 0.87, isMetallic: false)
  private let sphere: MeshResource
  private let side: Int
  private var limbs: [ModelEntity] = []
  private var shoes: [Entity] = []
  private let stamp: ModelEntity

  init(side: Int, sphere: MeshResource, shadow: ModelEntity) {
    self.side = side; self.sphere = sphere; stamp = shadow
    skin = SimpleMaterial(color: side == 0 ? UIColor(red: 0.68, green: 0.42, blue: 0.29, alpha: 1)
      : UIColor(red: 0.48, green: 0.285, blue: 0.19, alpha: 1), roughness: 0.85, isMetallic: false)
    fabric = SimpleMaterial(color: side == 0 ? UIColor(red: 0.26, green: 0.76, blue: 0.84, alpha: 1)
      : UIColor(red: 0.99, green: 0.42, blue: 0.17, alpha: 1), roughness: 0.92, isMetallic: false)
    for part in [torso, hips, face, racket, stamp] { root.addChild(part) }
    // Cross sections give the shirt a waist, rib cage and sloping shoulder seams.
    let jersey = Self.profile([
      [0.159,-0.27,0.115], [0.181,-0.245,0.119], [0.167,-0.085,0.110],
      [0.19,0.045,0.122], [0.218,0.146,0.136], [0.216,0.195,0.12],
      [0.173,0.226,0.109], [0.087,0.259,0.074]])
    torso.addChild(ModelEntity(mesh: jersey, materials: [fabric]))
    for x: Float in [-0.195,0.195] {
      ellipsoid(torso, [x,0.218,0], [0.087,0.068,0.099], fabric)
    }
    let stripe = Self.profile([[0.178,-0.247,0.118], [0.182,-0.235,0.121]])
    torso.addChild(ModelEntity(mesh: stripe, materials: [fabric]))
    ellipsoid(face, [0, -0.148, 0.008], [0.063, 0.102, 0.063], skin)
    ellipsoid(torso, [0, 0.236, 0], [0.105, 0.030, 0.095], white)
    ellipsoid(torso, [0.12, 0.12, -0.124], [0.025, 0.011, 0.006], white)
    hips.addChild(ModelEntity(mesh: Self.profile([[0.164,-0.103,0.126], [0.194,-0.059,0.138],
      [0.186,0.026,0.132], [0.161,0.063,0.116]]), materials: [shorts]))
    face.addChild(ModelEntity(mesh: Self.profile([[0.047,-0.12,0.064], [0.076,-0.095,0.084],
      [0.094,-0.035,0.099], [0.098,0.025,0.106], [0.094,0.082,0.10],
      [0.061,0.119,0.071], [0.004,0.138,0.006]]), materials: [skin]))
    for x: Float in [-0.096, 0.096] { ellipsoid(face, [x, -0.013,0], [0.015,0.028,0.017], skin) }
    let hair = SimpleMaterial(color: UIColor(red: 0.12, green: 0.081, blue: 0.065, alpha: 1), roughness: 1, isMetallic: false)
    ellipsoid(face, [0, 0.064, 0.012], [0.104, 0.091, 0.106], hair)
    face.addChild(ModelEntity(mesh: Self.profile([[0.102,0.031,0.109], [0.104,0.050,0.111]]), materials: [white]))
    ellipsoid(face, [0, -0.019, -0.099], [0.024, 0.034, 0.025], skin)
    for x: Float in [-0.039, 0.039] { ellipsoid(face, [x, 0.009, -0.097], [0.012, 0.006, 0.006], hair) }
    // Each limb mesh is one unit long, with its proximal end at -0.5.
    func limb(_ sections: [(Float, Float)]) -> MeshResource {
      Self.profile(sections.map { CourtPoint3D($0.1, $0.0, $0.1 * 0.92) })
    }
    let thigh = limb([(-0.55,0.76),(-0.36,1.03),(0,1.0),(0.28,0.82),(0.53,0.68)])
    let cuff = limb([(-0.53,0.89),(-0.3,1.05),(0.37,1.05),(0.54,1.0)])
    let calf = limb([(-0.56,0.88),(-0.37,0.98),(-0.15,1.07),(0.22,0.64),(0.55,0.53)])
    let sock = limb([(-0.54,0.72),(0.12,0.86),(0.5,1.04)])
    let arm = limb([(-0.54,0.82),(-0.28,1.07),(0.05,0.96),(0.55,0.68)])
    let forearm = limb([(-0.56,1.02),(-0.28,1.08),(0.13,0.84),(0.54,0.61)])
    let meshes = [thigh, cuff, calf, sock, arm, cuff, forearm, cuff, sphere]
    for _ in 0..<2 {
      for (mesh, material) in zip(meshes, [skin, shorts, skin, white, skin, fabric, skin, white, skin]) {
        let part = ModelEntity(mesh: mesh, materials: [material])
        root.addChild(part); limbs.append(part)
      }
      let shoe = Entity(); root.addChild(shoe); shoes.append(shoe)
      ellipsoid(shoe, [0, 0.005, -0.046], [0.062, 0.065, 0.142], white)
      ellipsoid(shoe, [0, -0.038, -0.05], [0.064, 0.025, 0.145], shorts)
      ellipsoid(shoe, [0, 0.032, -0.089], [0.043, 0.035, 0.068], fabric)
    }
    let frame = ReplayMeshLines()
    var previous = CourtPoint3D(0, 0.49 + 0.175, 0)
    for i in 1...48 {
      let t = Float(i) * 2 * .pi / 48
      let next = CourtPoint3D(sin(t) * 0.132, 0.49 + cos(t) * 0.175, 0)
      frame.line(previous, next, radius: 0.010); previous = next
    }
    frame.line([0, 0.14, 0], [-0.075, 0.343, 0], radius: 0.008)
    frame.line([0, 0.14, 0], [0.075, 0.343, 0], radius: 0.008)
    racket.addChild(frame.model(color: side == 0 ? .systemIndigo : .darkGray))
    let mesh = ReplayMeshLines()
    for i in -6...6 {
      let x = Float(i) * 0.018
      let reach = 0.17 * sqrt(1 - x*x / (0.132*0.132))
      mesh.line([x, 0.49-reach, 0], [x, 0.49+reach, 0], radius: 0.0014)
    }
    for i in -8...8 {
      let y = Float(i) * 0.019
      let reach = 0.132 * sqrt(1 - y*y / (0.175*0.175))
      mesh.line([-reach, 0.49+y, 0], [reach, 0.49+y, 0], radius: 0.0014)
    }
    racket.addChild(mesh.model(color: .white))
    ellipsoid(racket, [0, 0.058, 0], [0.018, 0.11, 0.019], white)
  }

  /// Elliptical rings in ascending height, with normals following the change in radius.
  private static func profile(_ rings: [CourtPoint3D]) -> MeshResource {
    var vertices: [CourtPoint3D] = [], normals: [CourtPoint3D] = [], indices: [UInt32] = []
    let sides = 20
    for (row, ring) in rings.enumerated() {
      let tangent = rings[min(rings.count-1,row+1)] - rings[max(0,row-1)]
      for n in 0..<sides {
        let a = 2 * Float.pi * Float(n) / Float(sides), c = cos(a), s = sin(a)
        vertices.append([ring.x*c, ring.y, ring.z*s])
        let dy = CourtPoint3D(tangent.x*c, tangent.y, tangent.z*s)
        let da = CourtPoint3D(-ring.x*s, 0, ring.z*c)
        normals.append(simd_normalize(simd_cross(dy, da)))
        if row > 0 {
          let k = UInt32(row*sides+n), next = UInt32(row*sides + (n+1)%sides), stride = UInt32(sides)
          indices += [k-stride,k,next, k-stride,next,next-stride]
        }
      }
    }
    let last = UInt32((rings.count-1) * sides)
    for n in 1..<(sides-1) {
      indices += [0, UInt32(n), UInt32(n+1), last, last+UInt32(n+1), last+UInt32(n)]
    }
    var mesh = MeshDescriptor()
    mesh.positions = MeshBuffers.Positions(vertices); mesh.normals = MeshBuffers.Normals(normals)
    mesh.primitives = .triangles(indices)
    return (try? MeshResource.generate(from: [mesh])) ?? .generateSphere(radius: 0.1)
  }

  private func ellipsoid(_ parent: Entity, _ at: CourtPoint3D, _ radii: CourtPoint3D, _ material: SimpleMaterial) {
    let node = ModelEntity(mesh: sphere, materials: [material])
    node.position = at; node.scale = radii; parent.addChild(node)
  }

  private func segment(_ node: Entity, _ a: CourtPoint3D, _ b: CourtPoint3D, _ radius: Float) {
    let d = b - a, length = max(0.0001, simd_length(d))
    node.position = (a + b) / 2
    node.scale = [radius, length, radius]
    node.orientation = simd_quatf(from: [0, 1, 0], to: d / length)
  }

  func draw(_ p: AthletePose) {
    let hip = (p[.leftHip] + p[.rightHip]) / 2
    let shoulder = (p[.leftShoulder] + p[.rightShoulder]) / 2
    let up = simd_normalize(shoulder - hip)
    func basis(_ x: CourtPoint3D) -> simd_quatf {
      let z = simd_normalize(simd_cross(x, up))
      return simd_quatf(simd_float3x3(columns: (simd_cross(up, z), up, z)))
    }
    hips.position = hip; hips.orientation = basis(p[.rightHip] - p[.leftHip])
    torso.position = (hip + shoulder) / 2; torso.orientation = basis(p[.rightShoulder] - p[.leftShoulder])
    face.position = p[.head]; face.orientation = simd_slerp(hips.orientation, torso.orientation, 0.25)
    let shaft = simd_normalize(p[.strings] - p[.grip])
    let width = simd_normalize(p[.racketEdge] - p[.strings])
    let normal = simd_normalize(simd_cross(width, shaft))
    racket.position = p[.grip]
    racket.orientation = simd_quatf(simd_float3x3(columns: (simd_cross(shaft, normal), shaft, normal)))
    for i in 0..<2 {
      let h = p[i == 0 ? .leftHip : .rightHip], k = p[i == 0 ? .leftKnee : .rightKnee]
      let foot = p[i == 0 ? .leftShoe : .rightShoe]
      let s = p[i == 0 ? .leftShoulder : .rightShoulder], e = p[i == 0 ? .leftElbow : .rightElbow]
      let hand = p[i == 0 ? .leftHand : .grip], j = i * 9
      segment(limbs[j], h, k, 0.091)
      segment(limbs[j+1], h, h + (k-h) * 0.58, 0.105)
      segment(limbs[j+2], k, foot, 0.066)
      segment(limbs[j+3], foot, foot + (k-foot) * 0.36, 0.060)
      segment(limbs[j+4], s, e, 0.064)
      segment(limbs[j+5], s, s + (e-s) * 0.46, 0.076)
      segment(limbs[j+6], e, hand, 0.048)
      segment(limbs[j+7], hand + (e-hand)*0.12, hand + (e-hand)*0.26, 0.045)
      limbs[j+8].position = hand; limbs[j+8].scale = [0.048, 0.060, 0.042]
      shoes[i].position = foot
      shoes[i].orientation = simd_slerp(simd_quatf(angle: side == 0 ? 0 : .pi, axis: [0,1,0]), hips.orientation, 0.32)
    }
    stamp.position = [hip.x, 0.008, hip.z]; stamp.scale = [0.96, 1, 0.65]
  }
}

/// Batches thin court/net/racket pieces into one mesh per material.
@MainActor final class ReplayMeshLines {
  private var vertices: [CourtPoint3D] = []
  private var normals: [CourtPoint3D] = []
  private var indices: [UInt32] = []
  func line(_ a: CourtPoint3D, _ b: CourtPoint3D, radius: Float) {
    let axis = simd_normalize(b-a)
    let ref: CourtPoint3D = abs(axis.y) < 0.9 ? [0,1,0] : [1,0,0]
    let u = simd_normalize(simd_cross(axis, ref)), v = simd_cross(axis, u)
    let base = UInt32(vertices.count)
    for i in 0..<6 {
      let t = Float(i) * .pi / 3
      let n = u*cos(t) + v*sin(t)
      vertices += [a+n*radius, b+n*radius]; normals += [n,n]
      let k = base + UInt32(i * 2), next = base + UInt32((i+1)%6 * 2)
      indices += [k,next,k+1,next,next+1,k+1]
    }
  }
  func box(center: CourtPoint3D, size: CourtPoint3D) {
    let axes: [CourtPoint3D] = [[1,0,0], [0,1,0], [0,0,1]]
    for a in 0..<3 {
      for sign: Float in [-1,1] {
        let normal = axes[a] * sign
        let u = axes[(a+1)%3] * sign, v = axes[(a+2)%3]
        let origin = center + normal * size / 2
        let base = UInt32(vertices.count)
        vertices += [origin-(u+v)*size/2, origin+(u-v)*size/2, origin+(u+v)*size/2, origin+(-u+v)*size/2]
        normals += Array(repeating: normal, count: 4)
        indices += [base,base+1,base+2,base,base+2,base+3]
      }
    }
  }

  func model(color: UIColor) -> ModelEntity {
    var descriptor = MeshDescriptor()
    descriptor.positions = MeshBuffers.Positions(vertices)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.primitives = .triangles(indices)
    let entity = ModelEntity()
    if let mesh = try? MeshResource.generate(from: [descriptor]) {
      entity.model = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: color, roughness: 0.75, isMetallic: false)])
    }
    return entity
  }
}
