import RealityKit
import UIKit

@MainActor enum CourtRacket {
  private static var templates: [KitColor:Entity] = [:]

  static func make(color: KitColor) -> Entity {
    if let cached = templates[color] { return cached.clone(recursive:true) }
    let racket = Entity()
    let graphite = UIColor(red:0.115,green:0.14,blue:0.17,alpha:1)
    let offWhite = UIColor(red:0.88,green:0.90,blue:0.84,alpha:1)
    let hoop = ReplayMeshLines(), accents = ReplayMeshLines(), strings = ReplayMeshLines(), wrap = ReplayMeshLines()
    func rim(_ i: Int) -> CourtPoint3D {
      let a = Float(i)*2 * .pi/80
      return [0.132*sin(a),0.49+0.175*cos(a),0]
    }
    for i in 0..<80 {
      let colored = (13..<23).contains(i) || (57..<67).contains(i)
      (colored ? accents : hoop).line(rim(i),rim(i+1),radius:0.009)
    }
    for sign: Float in [-1,1] {
      let nodes: [CourtPoint3D] = [[0,0.125,0],[0.014*sign,0.196,0],[0.044*sign,0.254,0],[0.093*sign,0.365,0]]
      for i in 0..<(nodes.count-1) { hoop.line(nodes[i],nodes[i+1],radius:0.009-Float(i)*0.0008) }
    }
    for i in 0..<16 {
      let x = (Float(i)-7.5)*0.0157
      let dy = 0.172*sqrt(1-x*x/(0.132*0.132))
      strings.line([x,0.49-dy,0],[x,0.49+dy,0],radius:0.00078)
    }
    for i in 0..<19 {
      let y = (Float(i)-9)*0.0174
      let dx = 0.130*sqrt(1-y*y/(0.175*0.175))
      strings.line([-dx,0.49+y,0.0006],[dx,0.49+y,0.0006],radius:0.00078)
    }
    racket.addChild(hoop.model(color:graphite))
    racket.addChild(accents.model(color:color.tint))
    racket.addChild(strings.model(color:offWhite))
    // A flared butt cap and an overlapping spiral stay visible beneath the fingers.
    let handle = ReplayMeshLines()
    handle.line([0,-0.053,0],[0,0.14,0],radius:0.0175)
    handle.line([0,-0.059,0],[0,-0.044,0],radius:0.0205)
    racket.addChild(handle.model(color:UIColor(white:0.9,alpha:1)))
    func seam(_ i: Int) -> CourtPoint3D {
      let t = Float(i)/120, angle = t*Float.pi*18
      return [0.0176*cos(angle),-0.047+0.18*t,0.0176*sin(angle)]
    }
    for i in 0..<120 { wrap.line(seam(i),seam(i+1),radius:0.0008) }
    racket.addChild(wrap.model(color:UIColor(white:0.63,alpha:1)))
    templates[color] = racket
    return racket.clone(recursive:true)
  }
}
