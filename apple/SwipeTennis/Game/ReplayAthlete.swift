import RealityKit
import UIKit

/// A single rig drives match play, the three replay cameras and the locker room.
@MainActor final class ReplayAthlete {
  let root = Entity()
  let usesAnatomicalMesh: Bool
  private let athlete: AnatomicalAthlete?
  private let fallback: PrimitiveAthlete?
  private let racket: Entity
  private let side: Int
  private let stamp: ModelEntity
  private let footShadows: [ModelEntity]

  init(side: Int, sphere: MeshResource, shadow: ModelEntity, localSide: Int = 0) {
    let kit = AthleteKit.current(side:side,localSide:localSide)
    athlete = AnatomicalAthlete(kit:kit,side:side)
    usesAnatomicalMesh = athlete != nil
    fallback = athlete == nil ? PrimitiveAthlete(kit:kit,side:side,sphere:sphere) : nil
    self.side = side
    stamp = shadow
    footShadows = [shadow.clone(recursive:true),shadow.clone(recursive:true)]
    racket = CourtRacket.make(color:kit.color)
    if let athlete { root.addChild(athlete.entity) }
    if let fallback { root.addChild(fallback.root) }
    root.addChild(racket); root.addChild(stamp)
    footShadows.forEach { root.addChild($0) }
  }

  func draw(_ p: AthletePose, handshake: Bool = false) {
    athlete?.pose(p,handshake:handshake)
    fallback?.draw(p,handshake:handshake)
    let shaft = simd_normalize(p[.strings]-p[.grip]), width = simd_normalize(p[.racketEdge]-p[.strings])
    let normal = simd_normalize(simd_cross(width,shaft))
    racket.position = p[.grip]
    racket.orientation = simd_quatf(simd_float3x3(columns:(simd_cross(shaft,normal),shaft,normal)))
    if handshake {
      racket.position = p[.leftHand]
      racket.orientation = simd_quatf(angle:side == 0 ? 2.72 : -2.72,axis:[0,0,1])
    }
    let hip = (p[.leftHip]+p[.rightHip])*0.5
    for (i, shadow) in footShadows.enumerated() {
      let foot = p[i == 0 ? .leftShoe : .rightShoe]
      let contact = max(0,1-max(0,foot.y-0.06)/0.35)
      shadow.isEnabled = contact > 0.03
      shadow.position = [foot.x,0.011,foot.z]
      shadow.scale = [0.28*contact,1,0.42*contact]
    }
    stamp.position = [hip.x,0.008,hip.z]; stamp.scale = [0.96,1,0.65]
  }
}

/// Kept for a device that fails to import the bundled USD. It allocates no
/// meshes or streaming buffers when the anatomical model loads successfully.
@MainActor private final class PrimitiveAthlete {
  let root = Entity()
  private let torso = Entity(), hips = Entity(), face = Entity()
  private let skin: SimpleMaterial, fabric: SimpleMaterial
  private let shorts = SimpleMaterial(color:UIColor(red:0.10,green:0.15,blue:0.19,alpha:1),roughness:0.9,isMetallic:false)
  private let white = SimpleMaterial(color:.white,roughness:0.87,isMetallic:false)
  private let garment: ReplayShorts
  private let sphere: MeshResource
  private let kit: AthleteKit
  private let side: Int
  private var pupils: [Entity] = []
  private var limbs: [ModelEntity] = []
  private var shoes: [Entity] = []

  init(kit: AthleteKit, side: Int, sphere: MeshResource) {
    self.kit = kit; self.side = side; self.sphere = sphere
    skin = SimpleMaterial(color:kit.skinTone.tint,roughness:0.85,isMetallic:false)
    fabric = SimpleMaterial(color:kit.color.tint,roughness:0.92,isMetallic:false)
    garment = ReplayShorts(material:shorts)
    for part in [torso, hips, face, garment.model] { root.addChild(part) }
    if kit.skort {
      hips.addChild(ModelEntity(mesh:Self.profile([[0.248,-0.235,0.168],[0.241,-0.20,0.162],[0.19,-0.02,0.134],[0.166,0.06,0.113]]),materials:[fabric]))
    }
    // Cross sections give the shirt a waist, rib cage and sloping shoulder seams.
    let jersey = Self.profile([
      [0.159,-0.27,0.115], [0.181,-0.245,0.119], [0.167,-0.085,0.110],
      [0.19,0.045,0.122], [0.218,0.146,0.136], [0.216,0.195,0.12],
      [0.173,0.226,0.109], [0.087,0.259,0.074]])
    torso.addChild(ModelEntity(mesh: jersey, materials: [Self.jerseyMaterial(color: kit.color.tint, base: fabric)]))
    if kit.model == .woman { torso.scale = [0.92,1,0.98]; face.scale = [0.96,0.97,0.96] }
    if kit.shirt == .polo {
      for sign: Float in [-1,1] {
        let collar = ModelEntity(mesh: .generateBox(size:[0.066,0.068,0.012],cornerRadius:0.009), materials:[white])
        collar.position = [sign*0.046,0.218,-0.091]
        collar.orientation = simd_quatf(angle:sign * 0.52,axis:[0,0,1]); torso.addChild(collar)
      }
    }
    for x: Float in [-0.195,0.195] {
      ellipsoid(torso, [x,0.218,0], [0.087,0.068,0.099], kit.shirt == .sleeveless ? skin : fabric)
    }
    ellipsoid(face, [0, -0.148, 0.008], [0.063, 0.102, 0.063], skin)
    ellipsoid(torso, [0, 0.236, 0], [0.105, 0.030, 0.095], white)
    ellipsoid(torso, [0.12, 0.12, -0.124], [0.025, 0.011, 0.006], white)
    face.addChild(ModelEntity(mesh: Self.profile([[0.047,-0.12,0.064], [0.076,-0.095,0.084],
      [0.094,-0.035,0.099], [0.098,0.025,0.106], [0.094,0.082,0.10],
      [0.061,0.119,0.071], [0.004,0.138,0.006]]), materials: [skin]))
    for x: Float in [-0.096, 0.096] { ellipsoid(face, [x, -0.013,0], [0.015,0.028,0.017], skin) }
    let hair = SimpleMaterial(color: UIColor(red: 0.12, green: 0.081, blue: 0.065, alpha: 1), roughness: 1, isMetallic: false)
    ellipsoid(face, [0, 0.064, 0.012], [0.104, 0.091, 0.106], hair)
    if kit.model == .woman {
      ellipsoid(face, [0,0.032,0.096], [0.057,0.070,0.063], hair)
      ellipsoid(face, [0,-0.05,0.125], [0.042,0.090,0.043], hair)
    }
    if kit.prop == .visor { ellipsoid(face, [0,0.042,-0.089], [0.114,0.012,0.084], fabric) }
    if kit.prop != .plain { face.addChild(ModelEntity(mesh: Self.profile([[0.102,0.031,0.109], [0.104,0.050,0.111]]), materials: [white])) }
    ellipsoid(face, [0, -0.019, -0.099], [0.024, 0.034, 0.025], skin)
    for x: Float in [-0.039, 0.039] {
      ellipsoid(face, [x, 0.008, -0.094], [0.014, 0.0065, 0.008], white)
      let pupil = ModelEntity(mesh:sphere, materials:[hair])
      pupil.position = [x,0.008,-0.101]; pupil.scale = [0.0065,0.006,0.003]
      face.addChild(pupil); pupils.append(pupil)
    }
    for x: Float in [-0.038,0.038] {
      ellipsoid(face,[x,0.019,-0.097],[0.020,0.003,0.005],hair)
    }
    let lips = SimpleMaterial(color: UIColor(red:0.43,green:0.22,blue:0.18,alpha:1),roughness:0.85,isMetallic:false)
    ellipsoid(face,[0,-0.062,-0.091],[0.026,0.004,0.005],lips)
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
      for (mesh, material) in zip(meshes, [skin, white, skin, white, skin, kit.shirt == .sleeveless ? skin : fabric, skin, white, skin]) {
        let part = ModelEntity(mesh: mesh, materials: [material])
        root.addChild(part); limbs.append(part)
      }
      let shoe = Entity(); root.addChild(shoe); shoes.append(shoe)
      ellipsoid(shoe, [0, 0.005, -0.046], [0.062, 0.065, 0.142], white)
      ellipsoid(shoe, [0, -0.038, -0.05], [0.064, 0.025, 0.145], shorts)
      ellipsoid(shoe, [0, 0.032, -0.089], [0.043, 0.035, 0.068], fabric)
      let laces = ReplayMeshLines()
      for row in 0..<3 {
        let z = -0.062 - Float(row)*0.022
        laces.line([-0.029,0.062,z],[0.028,0.062,z-0.013],radius: 0.003)
        laces.line([0.029,0.062,z],[-0.028,0.062,z-0.013],radius: 0.003)
      }
      shoe.addChild(laces.model(color: .white))
    }
  }

  /// UVs wrap the torso from the side seam. The knit, shoulder panels and hems turn with the shirt.
  private static func jerseyMaterial(color: UIColor, base: SimpleMaterial) -> SimpleMaterial {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1; format.opaque = true
    let bounds = CGRect(x: 0,y: 0,width: 512,height: 512)
    let image = UIGraphicsImageRenderer(size: bounds.size,format: format).image { renderer in
      let ctx = renderer.cgContext
      ctx.setFillColor(color.cgColor); ctx.fill(bounds)
      for x: CGFloat in [0,256,512] {
        let panel = UIBezierPath()
        panel.move(to: CGPoint(x: x-72,y: 0)); panel.addLine(to: CGPoint(x: x+72,y: 0))
        panel.addQuadCurve(to: CGPoint(x: x+21,y: 170),controlPoint: CGPoint(x: x+35,y: 94))
        panel.addLine(to: CGPoint(x: x+14,y: 510)); panel.addLine(to: CGPoint(x: x-14,y: 510))
        panel.addLine(to: CGPoint(x: x-21,y: 170)); panel.close()
        UIColor.black.withAlphaComponent(0.19).setFill(); panel.fill()
        UIColor.white.withAlphaComponent(0.50).setStroke(); panel.lineWidth = 2; panel.stroke()
      }
      ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.065).cgColor)
      ctx.setLineWidth(1)
      for y in stride(from: -12, through: 520, by: 5) {
        ctx.move(to: CGPoint(x: 0,y: y)); ctx.addLine(to: CGPoint(x: 512,y: y+12))
      }
      ctx.strokePath()
      ctx.setFillColor(UIColor.black.withAlphaComponent(0.15).cgColor)
      ctx.fill(CGRect(x: 0,y: 491,width: 512,height: 3))
    }
    guard let cg = image.cgImage, let texture = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) else { return base }
    var result = base
    result.color = .init(tint: .white, texture: .init(texture))
    return result
  }

  /// Elliptical rings in ascending height, with normals following the change in radius.
  private static func profile(_ rings: [CourtPoint3D]) -> MeshResource {
    var vertices: [CourtPoint3D] = [], normals: [CourtPoint3D] = [], indices: [UInt32] = []
    let sides = 20, stride = 21
    var uv: [SIMD2<Float>] = []
    let firstY = rings[0].y, span = max(0.00001, rings[rings.count-1].y-firstY)
    for (row, ring) in rings.enumerated() {
      let tangent = rings[min(rings.count-1,row+1)] - rings[max(0,row-1)]
      for n in 0...sides {
        let u = Float(n) / Float(sides), a = 2 * Float.pi * u, c = cos(a), s = sin(a)
        vertices.append([ring.x*c, ring.y, ring.z*s])
        uv.append([u, 1 - (ring.y-firstY)/span])
        let dy = CourtPoint3D(tangent.x*c, tangent.y, tangent.z*s)
        let da = CourtPoint3D(-ring.x*s, 0, ring.z*c)
        normals.append(simd_normalize(simd_cross(dy, da)))
        if row > 0 && n < sides {
          let k = UInt32(row*stride+n), lower = k-UInt32(stride)
          indices += [lower,k,k+1, lower,k+1,lower+1]
        }
      }
    }
    let last = UInt32((rings.count-1) * stride)
    for n in 1..<(sides-1) {
      indices += [0, UInt32(n), UInt32(n+1), last, last+UInt32(n+1), last+UInt32(n)]
    }
    var mesh = MeshDescriptor()
    mesh.positions = MeshBuffers.Positions(vertices); mesh.normals = MeshBuffers.Normals(normals)
    mesh.textureCoordinates = .init(uv)
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

  func draw(_ p: AthletePose, handshake: Bool) {
    garment.draw(p)
    let hip = (p[.leftHip] + p[.rightHip]) / 2
    let shoulder = (p[.leftShoulder] + p[.rightShoulder]) / 2
    let up = simd_normalize(shoulder - hip)
    func basis(_ x: CourtPoint3D) -> simd_quatf {
      let z = simd_normalize(simd_cross(x, up))
      return simd_quatf(simd_float3x3(columns: (simd_cross(up, z), up, z)))
    }
    hips.position = hip; hips.orientation = basis(p[.rightHip] - p[.leftHip])
    torso.position = (hip + shoulder) / 2; torso.orientation = basis(p[.rightShoulder] - p[.leftShoulder])
    face.position = p[.head]
    let forward = simd_quatf(angle: side == 0 ? 0 : .pi, axis: [0,1,0])
    let gaze = handshake ? SIMD2<Float>.zero : p.gaze
    face.orientation = simd_slerp(forward, torso.orientation, 0.18)
      * simd_quatf(angle:-gaze.x * 0.82, axis:[0,1,0]) * simd_quatf(angle:gaze.y * 0.8,axis:[1,0,0])
    for (index, pupil) in pupils.enumerated() {
      pupil.position.x = (index == 0 ? -0.039 : 0.039) + gaze.x * 0.0035
      pupil.position.y = 0.008 + gaze.y * 0.003
    }
    for i in 0..<2 {
      let h = p[i == 0 ? .leftHip : .rightHip], k = p[i == 0 ? .leftKnee : .rightKnee]
      let foot = p[i == 0 ? .leftShoe : .rightShoe]
      let s = p[i == 0 ? .leftShoulder : .rightShoulder], e = p[i == 0 ? .leftElbow : .rightElbow]
      let hand = p[i == 0 ? .leftHand : .grip], j = i * 9
      segment(limbs[j], h + (k-h) * 0.41, k, 0.084)
      segment(limbs[j+1], foot + (k-foot)*0.33, foot + (k-foot)*0.37, 0.062)
      segment(limbs[j+2], k, foot, 0.066)
      segment(limbs[j+3], foot, foot + (k-foot) * 0.36, 0.060)
      segment(limbs[j+4], s + (e-s) * 0.36, e, kit.model == .woman ? 0.054 : 0.062)
      segment(limbs[j+5], s, s + (e-s) * 0.46, 0.076)
      segment(limbs[j+6], e, hand, 0.048)
      segment(limbs[j+7], hand + (e-hand)*0.12, hand + (e-hand)*0.26, 0.045)
      limbs[j+8].position = hand; limbs[j+8].scale = [0.048, 0.060, 0.042]
      shoes[i].position = foot
      let facing = simd_quatf(angle: side == 0 ? 0 : .pi, axis: [0,1,0])
      let hipAxis = p[.rightHip] - p[.leftHip]
      let yaw = simd_quatf(angle: atan2(-hipAxis.z, hipAxis.x), axis: [0,1,0])
      shoes[i].orientation = simd_slerp(facing, yaw, 0.32) * simd_quatf(angle: -p.heelPitch, axis: [1,0,0])
    }
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

  func oval(_ center: CourtPoint3D, radii: CourtPoint3D) {
    let base = UInt32(vertices.count), sectors = 8
    for row in 0...4 {
      let phi = Float(row) * .pi / 4
      for i in 0..<sectors {
        let a = 2 * Float.pi * Float(i) / Float(sectors)
        let n = CourtPoint3D(sin(phi)*cos(a),cos(phi),sin(phi)*sin(a))
        vertices.append(center + radii*n); normals.append(simd_normalize(n / radii))
        if row > 0 {
          let k = base + UInt32(row*sectors+i), next = base + UInt32(row*sectors+(i+1)%sectors), prev = UInt32(sectors)
          indices += [k-prev,next-prev,k, next-prev,next,k]
        }
      }
    }
  }
  func descriptor() -> MeshDescriptor {
    var descriptor = MeshDescriptor()
    descriptor.positions = MeshBuffers.Positions(vertices)
    descriptor.normals = MeshBuffers.Normals(normals)
    descriptor.primitives = .triangles(indices)
    return descriptor
  }
  func model(color: UIColor) -> ModelEntity {
    let entity = ModelEntity()
    if let mesh = try? MeshResource.generate(from: [descriptor()]) {
      entity.model = ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: color, roughness: 0.75, isMetallic: false)])
    }
    return entity
  }
}
