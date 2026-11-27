import simd

/// Solves the joint between two fixed endpoints with this athlete's own bone
/// proportions. The animation supplies the bend plane; the skin supplies the lengths.
struct LimbGeometry {
  let upper: Float
  let lower: Float

  func hinge(from root: SIMD3<Float>, to end: SIMD3<Float>, guide: SIMD3<Float>,
             fallback: SIMD3<Float>) -> SIMD3<Float> {
    let ray = end - root
    let distance = max(0.0001, simd_length(ray))
    let axis = simd_length_squared(ray) > 0.00000001 ? ray / distance : SIMD3<Float>(0,-1,0)
    func projected(_ v: SIMD3<Float>) -> SIMD3<Float> { v-axis*simd_dot(v,axis) }
    var bend = projected(guide-root)
    if simd_length_squared(bend) < 0.000025 { bend = projected(fallback) }
    if simd_length_squared(bend) < 0.000025 {
      bend = simd_cross(axis,abs(axis.x) < 0.8 ? [1,0,0] : [0,0,1])
    }
    // At maximal reach leave a few degrees at the elbow or knee. If a game
    // contact exceeds rest reach, distribute the extension across both bones.
    let stretch = max(1, distance / ((upper + lower)*0.997))
    let a = upper*stretch, b = lower*stretch
    let along = max(-a,min(a,(distance*distance+a*a-b*b)/(2*distance)))
    return root + axis*along + simd_normalize(bend)*sqrt(max(0,a*a-along*along))
  }
}
