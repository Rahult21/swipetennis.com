import simd

/// One continuous string-bed path, expressed in the player's right/up/forward
/// coordinates. Shared tangents carry the racket through impact and extension.
struct GroundstrokePath {
  let strings, shaft: CourtPoint3D

  init(time t: Float, backhand: Bool, strike: CourtPoint3D, rush: Float, power: Bool, shoulderHeight: Float = 1.45) {
    let s: Float = backhand ? -1 : 1
    let low = max(0,min(1,(1.10-strike.y)/0.85))
    func ease(_ t: Float, _ a: Float, _ b: Float) -> Float {
      let u = max(0,min(1,(t-a)/(b-a)))
      return u*u*(3-2*u)
    }
    func arc(_ from: CourtPoint3D, _ to: CourtPoint3D, _ start: Float, _ end: Float,
             _ v0: CourtPoint3D, _ v1: CourtPoint3D) -> CourtPoint3D {
      let dt = end-start, u = max(0,min(1,(t-start)/dt))
      return from+(to-from)*(u*u*(3-2*u)) + dt*u*(1-u)*((1-u)*v0-u*v1)
    }
    func blade(_ a: CourtPoint3D, _ b: CourtPoint3D, _ start: Float, _ end: Float) -> CourtPoint3D {
      let from = simd_normalize(a), turn = simd_quatf(from:from,to:simd_normalize(b))
      return simd_slerp(simd_quatf(real:1,imag:.zero),turn,ease(t,start,end)).act(from)
    }
    // Animate the handle through the hitting corridor. Rotating a racket
    // around the string bed makes the wrists reverse direction on low balls.
    let room = max(0,min(1,s*strike.x/0.72))
    let neutral: CourtPoint3D = [-0.12,0.88,0.42]
    let upright: CourtPoint3D = backhand ? [-0.34,0.86,-0.38] : [0.17,0.78,-0.61]
    let lag: CourtPoint3D = backhand ? [-0.52,-0.33,-0.78] : [0.48,-0.55,-0.78]
    let face = simd_normalize(CourtPoint3D(s*(0.40+0.57*room),0.20-1.14*low,0.48-0.16*room))
    let lift: CourtPoint3D = [s*0.75,0.12+0.18*(1-low),0.67]
    let wrap: CourtPoint3D = backhand ? [0.59,0.55,-0.64] : [-0.54,0.20,-0.81]
    let settle: CourtPoint3D = backhand ? [0.39,0.72,-0.54] : [-0.50,-0.16,-0.85]
    let setTime: Float = backhand ? -0.32 : -0.265
    let lagTime: Float = backhand ? -0.12 : -0.103
    // Carry the turning racket head through the ball with a shared angular
    // tangent. Easing to a stop on the contact key makes the impact look soft.
    let flat = simd_normalize(lift)-simd_normalize(lag)
    let release = simd_normalize(flat-face*simd_dot(flat,face)) * (power ? 18 : 15)
    if t < setTime { shaft = blade(neutral,upright,-0.79,setTime) }
    else if t < lagTime { shaft = blade(upright,lag,setTime,lagTime) }
    else if !backhand && t < 0 {
      shaft = simd_normalize(arc(simd_normalize(lag),face,lagTime,0,.zero,release))
    } else if !backhand && t < 0.085 {
      shaft = simd_normalize(arc(face,simd_normalize(lift),0,0.085,release,.zero))
    } else if t < 0 { shaft = blade(lag,face,lagTime,0) }
    else if t < 0.085 { shaft = blade(face,lift,0,0.085) }
    else if t < 0.29 { shaft = blade(lift,wrap,0.085,0.29) }
    else if t < 0.36 { shaft = blade(wrap,settle,0.29,0.36) }
    else { shaft = blade(settle,neutral,0.36,0.58) }

    let ready = CourtPoint3D(0.12,1.44,0.43)-simd_normalize(neutral)*0.49
    let set = backhand ? CourtPoint3D(-0.37+0.07*rush,1.16,-0.15+0.09*rush)
      : CourtPoint3D(0.38-0.06*rush,shoulderHeight+0.015-0.04*rush,-0.69+0.23*rush)
    let drop = CourtPoint3D(s*(backhand ? 0.41 : 0.54),max(0.77,min(1.36,strike.y+0.14)),
      (backhand ? -0.19 : -0.42)+0.10*rush)
    let contact = strike-face*0.49
    let extensionPoint = contact+CourtPoint3D(-s*(backhand ? 0.115 : 0.14),0.135,power ? 0.23 : backhand ? 0.16 : 0.21)
    let finish = CourtPoint3D(-s*(backhand ? 0.32 : 0.29),backhand ? 1.66 : 1.70,0.19)
    let carry = finish+CourtPoint3D(-s*0.025,-0.035,-0.10)
    let setVelocity = backhand ? CourtPoint3D(-0.26,-0.38,-0.56) : CourtPoint3D(0.64,-0.64,-0.60)
    let dropVelocity = CourtPoint3D(-s*0.14,-0.10,1.45)
    let contactVelocity = backhand ? CourtPoint3D(1.65,1.65,4.55) : CourtPoint3D(-2.1,2.35,power ? 8.5 : 7.2)
    let extensionVelocity = CourtPoint3D(-s*1.45,2.28,0.63)
    let finishVelocity = CourtPoint3D(-s*0.48,0.36,-1.05)
    let carryVelocity = CourtPoint3D(s*0.32,-0.76,0.22)
    let hand: CourtPoint3D
    let dropTime: Float = backhand ? -0.145 : -0.118
    let turn = CourtPoint3D(0.38,1.51,0.02)
    let turning = CourtPoint3D(0.50,0.38,-2.4)
    if !backhand && t < -0.49 { hand = arc(ready,turn,-0.79,-0.49,.zero,turning) }
    else if t < setTime {
      hand = backhand ? arc(ready,set,-0.79,setTime,.zero,setVelocity)
        : arc(turn,set,-0.49,setTime,turning,setVelocity)
    }
    else if t < dropTime { hand = arc(set,drop,setTime,dropTime,setVelocity,dropVelocity) }
    else if t < 0 { hand = arc(drop,contact,dropTime,0,dropVelocity,contactVelocity) }
    else if t < 0.062 { hand = arc(contact,extensionPoint,0,0.062,contactVelocity,extensionVelocity) }
    else if t < 0.255 { hand = arc(extensionPoint,finish,0.062,0.255,extensionVelocity,finishVelocity) }
    else if t < 0.36 { hand = arc(finish,carry,0.255,0.36,finishVelocity,carryVelocity) }
    else { hand = arc(carry,ready,0.36,0.58,carryVelocity,.zero) }
    strings = hand+shaft*0.49
  }
}
