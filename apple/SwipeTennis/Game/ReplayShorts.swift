import RealityKit

/// Stream a small, fixed topology garment. The iOS 17 path uses the same vertices and triangles.
@MainActor final class ReplayShorts {
  let model = ModelEntity()
  private var updateMesh: (([CourtPoint3D], [CourtPoint3D]) -> Void)?
  private let material: SimpleMaterial

  init(material: SimpleMaterial) {
    self.material = material
    if #available(iOS 18, *) {
      let shape = TennisShorts.mesh
      var descriptor = LowLevelMesh.Descriptor()
      descriptor.vertexCapacity = shape.vertexCount
      descriptor.vertexAttributes = [
        .init(semantic: .position, format: .float3, offset: 0),
        .init(semantic: .normal, format: .float3, layoutIndex: 1, offset: 0)]
      descriptor.vertexLayouts = [0,1].map { .init(bufferIndex: $0, bufferStride: MemoryLayout<CourtPoint3D>.stride) }
      descriptor.indexCapacity = shape.indices.count
      if let mesh = try? LowLevelMesh(descriptor: descriptor), let resource = try? MeshResource(from: mesh) {
        mesh.withUnsafeMutableIndices { data in shape.indices.withUnsafeBytes { data.copyMemory(from: $0) } }
        mesh.parts.replaceAll([.init(indexCount: shape.indices.count, topology: .triangle, materialIndex: 0,
          bounds: BoundingBox(min: [-10,-1,-10], max: [19,4,34]))])
        model.model = ModelComponent(mesh: resource, materials: [material])
        updateMesh = { points, normals in
          mesh.withUnsafeMutableBytes(bufferIndex: 0) { buffer in points.withUnsafeBytes { buffer.copyMemory(from: $0) } }
          mesh.withUnsafeMutableBytes(bufferIndex: 1) { buffer in normals.withUnsafeBytes { buffer.copyMemory(from: $0) } }
        }
      }
    }
  }

  func draw(_ pose: AthletePose) {
    let shape = TennisShorts.mesh, points = shape.positions(for: pose)
    var normals = Array(repeating: CourtPoint3D.zero, count: points.count)
    for i in stride(from: 0, to: shape.indices.count, by: 3) {
      let a = Int(shape.indices[i]), b = Int(shape.indices[i+1]), c = Int(shape.indices[i+2])
      let normal = simd_cross(points[b]-points[a], points[c]-points[a])
      normals[a] += normal; normals[b] += normal; normals[c] += normal
    }
    normals = normals.map { simd_length_squared($0) > 0.000000001 ? simd_normalize($0) : [0,1,0] }
    if let updateMesh { updateMesh(points, normals); return }
    var descriptor = MeshDescriptor()
    descriptor.positions = .init(points); descriptor.normals = .init(normals)
    descriptor.primitives = .triangles(shape.indices)
    if let mesh = try? MeshResource.generate(from: [descriptor]) {
      model.model = ModelComponent(mesh: mesh, materials: [material])
    }
  }
}
