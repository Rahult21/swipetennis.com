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

/// Service arms bend in one plane. Retarget to the palm so the wrist stays
/// attached even when the racket drops behind the head or points straight up.
struct ServiceArm {
  struct Rotations {
    let upper, forearm, elbowHalf: simd_quatf
  }
  private var elbow = ElbowBend()

  mutating func solve(upper: SIMD3<Float>, forearmToPalm: SIMD3<Float>, knuckles: SIMD3<Float>,
                      shoulder: SIMD3<Float>, clavicle: simd_quatf, palm: SIMD3<Float>, guide: SIMD3<Float>,
                      fallback: SIMD3<Float>, handle: SIMD3<Float>?, time: Double?) -> Rotations {
    let a = simd_length(upper), b = simd_length(forearmToPalm)
    let chain = LimbGeometry(upper:a,lower:b)
    let ray = chain.reachable(from:shoulder,toward:palm)-shoulder
    // Leave space for the biceps and forearm at the bottom of the racket drop.
    let foldedReach = sqrt(a*a+b*b+2*a*b*cos(148 * Float.pi/180))
    let target = shoulder+simd_normalize(ray)*max(foldedReach,simd_length(ray))
    // Keep the bent elbow outside the rib cage as the hand crosses from
    // the front of the body into the racket drop.
    let axis = simd_normalize(ray)
    let outside = clavicle.act(SIMD3<Float>(upper.x > 0 ? 0.85 : -0.85,-0.42,0.38))
    let projected = outside-axis*simd_dot(outside,axis)
    let observed = guide-shoulder
    let pole = projected+(observed-axis*simd_dot(observed,axis))*1.8
    let hinge = chain.hinge(from:shoulder,to:target,guide:shoulder+pole,fallback:fallback)
    let e = elbow.follow(hinge,shoulder:shoulder,wrist:target,time:time)
    let posedUpper = e-shoulder, posedLower = target-e
    let restNormal = simd_normalize(simd_cross(upper,forearmToPalm))
    let normal = simd_normalize(simd_cross(posedUpper,posedLower))
    // Raise the upper arm through the side of the shoulder so its resting
    // and overhead directions never have to define a half-turn on their own.
    let armAxis = simd_normalize(posedUpper)
    let lateral = SIMD3<Float>(upper.x > 0 ? 1 : -1,0,0)
    let abduction = simd_quatf(from:simd_normalize(upper),to:lateral)
    let swing = simd_quatf(from:clavicle.act(lateral),to:armAxis)*clavicle*abduction
    let from = swing.act(restNormal)
    let swivel = atan2(simd_dot(armAxis,simd_cross(from,normal)),max(0.45,simd_dot(from,normal)))
    let humerus = simd_quatf(angle:swivel,axis:armAxis)*swing
    let unbend = simd_quatf(from:simd_normalize(forearmToPalm),to:simd_normalize(upper))
    let flex = simd_quatf(from:armAxis,to:simd_normalize(posedLower))
    let identity = simd_quatf(real:1,imag:.zero)
    // Skin the elbow along the flexion arc. Halfway along the actual bend
    // stays continuous on a power serve even when total rotation passes 180°.
    let halfFlex = simd_slerp(identity,flex,0.5)
    var elbowHalf = halfFlex*humerus*simd_slerp(identity,unbend,0.5)
    var forearm = flex*humerus*unbend
    if let handle {
      // Pronation turns around the elbow-to-grip line. The shaft carries
      // progressively less roll information as it lines up with the forearm.
      let axis = simd_normalize(posedLower)
      let across = forearm.act(simd_normalize(knuckles))
      let x = simd_dot(across,handle)-simd_dot(across,axis)*simd_dot(handle,axis)
      let y = simd_dot(axis,simd_cross(across,handle))
      let roll = atan2(y,1+max(0,x))
      forearm = simd_quatf(angle:roll,axis:axis)*forearm
      elbowHalf = simd_quatf(angle:roll*0.5,axis:halfFlex.act(armAxis))*elbowHalf
    }
    return Rotations(upper:humerus,forearm:forearm,elbowHalf:elbowHalf)
  }
}
