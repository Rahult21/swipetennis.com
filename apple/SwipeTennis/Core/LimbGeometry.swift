import simd

/// A two-link chain in metres. A missed target changes the endpoint, never the bone lengths.
struct LimbGeometry {
  let upper: Float
  let lower: Float

  func reachable(from root: SIMD3<Float>, toward target: SIMD3<Float>) -> SIMD3<Float> {
    let ray = target-root, length = simd_length(ray)
    let axis = length > 0.00001 ? ray/length : SIMD3<Float>(0,-1,0)
    return root + axis*min((upper+lower)*0.997,max(abs(upper-lower)+0.0001,length))
  }

  func hinge(from root: SIMD3<Float>, to end: SIMD3<Float>, guide: SIMD3<Float>,
             fallback: SIMD3<Float>) -> SIMD3<Float> {
    let ray = reachable(from:root,toward:end)-root
    let distance = simd_length(ray), axis = ray/distance
    func projected(_ v: SIMD3<Float>) -> SIMD3<Float> { v-axis*simd_dot(v,axis) }
    var pole = projected(fallback)
    if simd_length_squared(pole) < 0.00001 {
      pole = simd_cross(axis,abs(axis.x) < 0.8 ? [1,0,0] : [0,0,1])
    }
    // Ease toward the anatomical pole through the near-straight singularity.
    // At other angles the measured elbow or knee sets the bend plane.
    var bend = projected(guide-root)
    let influence = max(0,1-simd_length(bend)/0.035)
    bend += simd_normalize(pole)*0.035*influence*influence
    if simd_length_squared(bend)<0.00000001 { bend = pole }
    let along = max(-upper,min(upper,(distance*distance+upper*upper-lower*lower)/(2*distance)))
    return root+axis*along+simd_normalize(bend)*sqrt(max(0,upper*upper-along*along))
  }
}
