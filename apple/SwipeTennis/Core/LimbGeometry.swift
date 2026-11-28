import simd

/// A two-link chain in metres. A missed target changes the endpoint, never the bone lengths.
struct LimbGeometry {
  let upper: Float
  let lower: Float

  /// Socket-to-ankle span on this rig for the bend in a reference pose.
  func span(matching upperRay: SIMD3<Float>, lowerRay: SIMD3<Float>) -> Float {
    let product = simd_length(upperRay)*simd_length(lowerRay)
    guard product > 0.00001 else { return upper+lower }
    let cosine = max(-1,min(1,simd_dot(upperRay,lowerRay)/product))
    return sqrt(max(0,upper*upper+lower*lower+2*upper*lower*cosine))
  }

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

/// Carry the elbow plane along a moving shoulder–wrist line. The hinge may
/// turn toward its target while both links retain their solved lengths.
struct ElbowBend {
  private var last: (axis: SIMD3<Float>, radial: SIMD3<Float>, shoulder: SIMD3<Float>, time: Double)?

  mutating func follow(_ target: SIMD3<Float>, shoulder: SIMD3<Float>, wrist: SIMD3<Float>,
                       time: Double?) -> SIMD3<Float> {
    let along = wrist-shoulder
    guard let time, simd_length_squared(along) > 0.000001 else { last = nil; return target }
    let axis = simd_normalize(along)
    let centre = shoulder+axis*simd_dot(target-shoulder,axis)
    let radial = target-centre
    let radius = simd_length(radial)
    guard radius > 0.002 else { last = nil; return target }
    var direction = radial/radius
    if let prior = last, abs(time-prior.time) <= 0.085, simd_distance(shoulder,prior.shoulder) < 0.62 {
      let carried = simd_quatf(from:prior.axis,to:axis).act(prior.radial)
      let turn = atan2(simd_dot(axis,simd_cross(carried,direction)),simd_dot(carried,direction))
      // Allow shoulder rotation during a fast swing, but never rotate a bent elbow
      // through the body in one frame. Near extension the arc is tiny.
      let limit = Float(abs(time-prior.time))*(15+0.35/radius)
      direction = simd_quatf(angle:max(-limit,min(limit,turn)),axis:axis).act(carried)
    }
    last = (axis,direction,shoulder,time)
    return centre+direction*radius
  }
}
