import RealityKit
import UIKit

/// Reuse seated figure meshes across the stands, with one transform per occupied seat.
@MainActor final class ReplayCrowd {
  private static var cached: ModelEntity?
  private var instances: [MeshResource.Instance] = []
  private static let shirts: [UIColor] = [
    .init(red: 0.78, green: 0.84, blue: 0.85, alpha: 1), .init(red: 0.25, green: 0.42, blue: 0.59, alpha: 1),
    .init(red: 0.79, green: 0.40, blue: 0.31, alpha: 1), .init(red: 0.26, green: 0.43, blue: 0.37, alpha: 1),
    .init(red: 0.79, green: 0.66, blue: 0.44, alpha: 1), .init(red: 0.55, green: 0.58, blue: 0.72, alpha: 1),
    .init(red: 0.30, green: 0.32, blue: 0.38, alpha: 1), .init(red: 0.86, green: 0.80, blue: 0.70, alpha: 1)]
  private static let skin: [UIColor] = [
    .init(red: 0.79, green: 0.58, blue: 0.44, alpha: 1), .init(red: 0.58, green: 0.38, blue: 0.25, alpha: 1),
    .init(red: 0.41, green: 0.26, blue: 0.20, alpha: 1), .init(red: 0.85, green: 0.67, blue: 0.55, alpha: 1)]
  private static let trousers = UIColor(red: 0.19, green: 0.22, blue: 0.26, alpha: 1)
  private static let hair = UIColor(red: 0.18, green: 0.14, blue: 0.12, alpha: 1)
  private static let variants = 24

  func seat(at position: CourtPoint3D, yaw: Float) {
    guard Self.cached == nil else { return }
    let index = instances.count
    var hash = UInt32(index + 1) &* 0x9e3779b9
    hash = (hash ^ (hash >> 16)) &* 0x85ebca6b
    let variation = Int(hash % UInt32(Self.variants))
    let height = 0.87 + Float((hash >> 8) % 27) * 0.01
    let turn = yaw + (Float((hash >> 17) % 17) - 8) * 0.023
    let scale = 0.89 + Float((hash >> 24) % 19) * 0.01
    let place = Transform(scale: [scale,height,scale], rotation: simd_quatf(angle: turn, axis: [0,1,0]),
      translation: position + [Float((hash >> 12)%9)*0.009-0.036,0,0])
    instances.append(.init(id: "seat-\(index)", model: "fan-\(variation)", at: place.matrix))
  }

  func model() -> ModelEntity {
    if let cached = Self.cached { return cached.clone(recursive: false) }
    var contents = MeshResource.Contents()
    let palette = Self.shirts + Self.skin + [Self.trousers, Self.hair]
    for v in 0..<Self.variants {
      let cloth = ReplayMeshLines(), body = ReplayMeshLines(), pants = ReplayMeshLines(), hair = ReplayMeshLines()
      let lean = Float(v%3)*0.05, tilt = Float(v%5-2)*0.032
      let neck = CourtPoint3D(tilt,0.55,-lean)
      cloth.oval([0,0.29,-lean/2], radii: [0.211,0.31,0.13])
      body.oval(neck + [0,0.125,0], radii: [0.103,0.143,0.109])
      hair.oval(neck + [0,0.208,0.012], radii: [0.107,0.077,0.109])
      if v % 4 == 0 { cloth.oval(neck + [0,0.195,-0.055], radii: [0.12,0.035,0.147]) }
      for side: Float in [-1,1] {
        let shoulder = neck + [side*0.163,-0.08,0], elbow = neck + [side*0.235,-0.29,-0.08]
        let hand = CourtPoint3D(side*0.112,0.13,-0.26-lean)
        cloth.line(shoulder,elbow,radius: 0.072); body.line(elbow,hand,radius: 0.046)
        let knee = CourtPoint3D(side*0.135,-0.02,-0.33)
        pants.line([side*0.12,0.04,0],knee,radius: 0.095)
        pants.line(knee,knee+[0,-0.38,-0.045],radius: 0.066)
      }
      let colors = [v % Self.shirts.count, Self.shirts.count + (v/3 + v)%Self.skin.count, palette.count-2, palette.count-1]
      let pieces = zip([cloth,body,pants,hair], colors).map { geometry, color -> MeshDescriptor in
        var descriptor = geometry.descriptor()
        descriptor.materials = .allFaces(UInt32(color))
        return descriptor
      }
      if let spectator = try? MeshResource.Model(id: "fan-\(v)", descriptors: pieces) { contents.models.insert(spectator) }
    }
    contents.instances = .init(instances)
    let group = ModelEntity()
    if let mesh = try? MeshResource.generate(from: contents) {
      group.model = ModelComponent(mesh: mesh, materials: palette.map { SimpleMaterial(color: $0, roughness: 1, isMetallic: false) })
      Self.cached = group
    }
    return group.clone(recursive: false)
  }
}
