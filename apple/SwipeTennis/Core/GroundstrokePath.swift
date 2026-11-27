import simd

/// One continuous string-bed path, expressed in the player's right/up/forward
/// coordinates. Shared tangents carry the racket through impact and extension.
struct GroundstrokePath {
  let strings, shaft: CourtPoint3D

  init(time t: Float, backhand: Bool, strike: CourtPoint3D, rush: Float, power: Bool) {
    let s: Float = backhand ? -1 : 1
    let low = max(0,min(1,(1.10-strike.y)/0.85))
    let ready: CourtPoint3D = [0.12,1.44,0.43]
    let set: CourtPoint3D = [s*(0.54-0.09*rush),backhand ? 1.58 : 1.69,-0.40+0.13*rush]
    let drop: CourtPoint3D = [s*(0.73-0.09*rush),max(0.30,strike.y-0.23),-0.44+0.14*rush]
    let extensionPoint = strike + CourtPoint3D(-0.16*s,0.20, power ? 0.36 : 0.26)
    let wrap: CourtPoint3D = [-s*(backhand ? 0.52 : 0.56), (backhand ? 1.81 : 1.74)+(power ? 0.08 : 0),-0.01+0.10*rush]
    let intoDrop: CourtPoint3D = [s*0.56,-0.5,2.6]
    let through = (extensionPoint-drop) / 0.205
    let out: CourtPoint3D = [-s*3.6,3.9,0.55]
    let endSet: CourtPoint3D = [s*0.38,-0.29,-0.95]

    func ease(_ t: Float, _ a: Float, _ b: Float) -> Float {
      let u = max(0,min(1,(t-a)/(b-a)))
      return u*u*(3-2*u)
    }
    func arc(_ from: CourtPoint3D, _ to: CourtPoint3D, _ start: Float, _ end: Float,
             _ v0: CourtPoint3D, _ v1: CourtPoint3D) -> CourtPoint3D {
      let dt = end-start, u = max(0,min(1,(t-start)/dt))
      return from+(to-from)*(u*u*(3-2*u)) + dt*u*(1-u)*((1-u)*v0-u*v1)
    }
    if t < -0.31 {
      strings = arc(ready,set,-0.79,-0.31,.zero,endSet)
    } else if t < -0.143 {
      strings = arc(set,drop,-0.31,-0.143,endSet,intoDrop)
    } else if t < 0 {
      strings = arc(drop,strike,-0.143,0,intoDrop,through)
    } else if t < 0.062 {
      strings = arc(strike,extensionPoint,0,0.062,through,out)
    } else if t < 0.245 {
      strings = arc(extensionPoint,wrap,0.062,0.245,out,.zero)
    } else {
      strings = arc(wrap,ready,0.34,0.58,.zero,.zero)
    }

    func blade(_ a: CourtPoint3D, _ b: CourtPoint3D, _ start: Float, _ end: Float) -> CourtPoint3D {
      let from = simd_normalize(a), turn = simd_quatf(from:from,to:simd_normalize(b))
      return simd_slerp(simd_quatf(real:1,imag:.zero),turn,ease(t,start,end)).act(from)
    }
    let neutral: CourtPoint3D = [-0.12,0.88,0.42]
    let upright: CourtPoint3D = [s*0.22,0.83,-0.50]
    let laidBack: CourtPoint3D = [s*0.47,-0.21,-0.86]
    let contact: CourtPoint3D = [s*0.91,0.13-low*0.50,0.39]
    let lift: CourtPoint3D = [s*0.36,0.58,0.73]
    let finish: CourtPoint3D = [-s*0.78,0.34,-0.52]
    if t < -0.31 { shaft = blade(neutral,upright,-0.79,-0.31) }
    else if t < -0.137 { shaft = blade(upright,laidBack,-0.31,-0.137) }
    else if t < 0 { shaft = blade(laidBack,contact,-0.137,0) }
    else if t < 0.078 { shaft = blade(contact,lift,0,0.078) }
    else if t < 0.245 { shaft = blade(lift,finish,0.078,0.245) }
    else { shaft = blade(finish,neutral,0.34,0.58) }
  }
}
