import simd

/// One waistband, a shared crotch seam and two hems. Both renderers use the same closed surface.
struct TennisShorts {
  private struct Vertex {
    var rest: CourtPoint3D
    var leg: Float
    var weight: Float
  }
  static let mesh = TennisShorts()
  private var vertices: [Vertex] = []
  private(set) var indices: [UInt32] = []
  private(set) var silhouetteGroups: [[UInt32]] = []
  var vertexCount: Int { vertices.count }

  private init() {
    let n = 16
    func vertex(_ p: CourtPoint3D, leg: Float = 0, weight: Float = 0) -> UInt32 {
      vertices.append(Vertex(rest: p, leg: leg, weight: weight))
      return UInt32(vertices.count - 1)
    }
    func join(_ upper: [UInt32], _ lower: [UInt32], reversed: Bool = false) {
      for i in upper.indices {
        let j = (i + 1) % upper.count
        let face = [upper[i], upper[j], lower[i], upper[j], lower[j], lower[i]]
        indices += reversed ? Array(face.reversed()) : face
      }
    }
    let angles = (0..<n).map { Float($0) * 2 * .pi / Float(n) }
    let waist = angles.map { vertex([0.196*cos($0), 0.076, 0.143*sin($0)]) }
    let seat = angles.map { vertex([0.220*cos($0), -0.035, 0.158*sin($0)]) }
    let fork = angles.map { vertex([0.225*cos($0), -0.095, 0.158*sin($0)],
      leg: cos($0) < 0 ? -1 : 1, weight: 0.19 * abs(cos($0))) }
    join(waist, seat); join(seat, fork)
    silhouetteGroups = [waist + seat + fork]
    let cap = vertex([0,0.076,0])
    for i in 0..<n { indices += [cap, waist[(i+1)%n], waist[i]] }
    // The inner edge is welded from front to back and belongs to both legs.
    var seam: [Int: UInt32] = [:]
    for i in (n/4+1)..<(3*n/4) {
      let a = angles[i]
      seam[i] = vertex([0,-0.095 + 0.073*cos(a),0.158*sin(a)])
    }
    for sign: Float in [-1,1] {
      var ring: [UInt32] = []
      for i in 0..<n {
        let outerIndex = sign > 0 ? i : (n/2 - i + n) % n
        ring.append(seam[i] ?? fork[outerIndex])
      }
      var silhouette = ring
      for (y, radius, depth, weight): (Float,Float,Float,Float) in [
        (-0.155,0.122,0.136,0.61), (-0.242,0.118,0.125,0.96), (-0.252,0.119,0.126,1)
      ] {
        let next = angles.map { a in
          vertex([sign*(0.14 + radius*cos(a)), y, depth*sin(a)], leg: sign, weight: weight)
        }
        join(ring, next, reversed: sign < 0)
        ring = next
        silhouette += next
      }
      silhouetteGroups.append(silhouette)
      let end = vertex([sign*0.14,-0.251,0], leg: sign, weight: 1)
      for i in 0..<n {
        let face = [ring[i],ring[(i+1)%n],end]
        indices += sign < 0 ? Array(face.reversed()) : face
      }
    }
  }

  func positions(for pose: AthletePose) -> [CourtPoint3D] {
    let hip = (pose[.leftHip] + pose[.rightHip]) / 2
    let right = simd_normalize(pose[.rightHip] - pose[.leftHip])
    let up = CourtPoint3D(0,1,0), back = simd_normalize(simd_cross(right, up))
    let leftTurn = simd_quatf(from: -up, to: simd_normalize(pose[.leftKnee] - pose[.leftHip]))
    let rightTurn = simd_quatf(from: -up, to: simd_normalize(pose[.rightKnee] - pose[.rightHip]))
    let leftScale = simd_distance(pose[.leftHip], pose[.leftKnee])/0.47
    let rightScale = simd_distance(pose[.rightHip], pose[.rightKnee])/0.47
    return vertices.map { vertex in
      let v = vertex.rest
      let rest = hip + right*v.x + up*v.y + back*v.z
      guard vertex.weight > 0 else { return rest }
      let pivot = vertex.leg < 0 ? pose[.leftHip] : pose[.rightHip]
      let rotation = vertex.leg < 0 ? leftTurn : rightTurn
      let scale = vertex.leg < 0 ? leftScale : rightScale
      let alongThigh = rest - pivot + up * (v.y * (scale-1))
      return rest + (pivot + rotation.act(alongThigh) - rest) * vertex.weight
    }
  }
}
