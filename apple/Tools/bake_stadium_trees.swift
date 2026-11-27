// swift bake_stadium_trees.swift output.png
import AppKit
import simd

struct Generator {
  var bits: UInt64
  mutating func next() -> Float {
    bits = bits &* 6364136223846793005 &+ 1442695040888963407
    return Float(bits >> 40) / 16_777_216
  }
}
struct Twig { let a,b:SIMD3<Float>; let width:Float }
struct Leaf { let p:SIMD3<Float>; let radius, light, angle:Float }
let tile = 480, count=6
let canvas=CGContext(data:nil,width:tile*count,height:tile*2,bitsPerComponent:8,bytesPerRow:0,
                     space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
for variant in 0..<count {
  var random=Generator(bits:UInt64(4569+variant*2409)), wood:[Twig]=[], leaves:[Leaf]=[]
  func branch(_ at:SIMD3<Float>,_ axis:SIMD3<Float>,_ length:Float,_ radius:Float,_ depth:Int) {
    let end=at+simd_normalize(axis)*length
    wood.append(Twig(a:at,b:end,width:radius))
    if depth<=2 {
      let spread=length*(depth==2 ? 0.49 : 0.76)
      for _ in 0..<(depth==2 ? 32 : 67) {
        let u=random.next()*2-1, a=random.next()*2*Float.pi
        let r=spread*pow(random.next(),0.40), h=sqrt(1-u*u)
        let n=SIMD3<Float>(h*cos(a),u,h*sin(a)), p=end+n*r
        let light=0.25 + 0.36*(simd_dot(n,simd_normalize(SIMD3<Float>(-0.55,0.91,-0.19)))+1)*0.5 + random.next()*0.20
        leaves.append(Leaf(p:p,radius:0.026+random.next()*0.044,light:light,angle:a))
      }
    }
    if depth==0 { return }
    let forks=depth>3 ? 4 : 3
    let phase=random.next()*Float.pi*2
    for j in 0..<forks {
      let a=phase+2*Float.pi*(Float(j)+0.18*random.next())/Float(forks)
      let wide=(variant%3==0 ? 0.92 : variant%3==1 ? 0.62 : 0.79)*(0.55+random.next()*0.76)
      let mix=SIMD3<Float>(wide*cos(a),0.22+random.next()*0.47,wide*sin(a))
      let child=simd_normalize(axis*(depth==5 ? 0.41 : 0.73)+mix)
      let origin=at+(end-at)*(0.55+random.next()*0.45)
      branch(origin,child,length*(0.65+random.next()*0.17),radius*0.56,depth-1)
    }
  }
  branch([0,0,0],[0.018,1,0.03],2.1,0.104,5)
  let loX=leaves.map{$0.p.x}.min()!,hiX=leaves.map{$0.p.x}.max()!,high=leaves.map{$0.p.y}.max()!
  let fit=min(0.94*Float(tile)/(hiX-loX+0.2),0.95*Float(tile)/(high+0.2))
  let topZ = (leaves.map{$0.p.z}.min()!+leaves.map{$0.p.z}.max()!)/2
  for overhead in [false,true] {
  func point(_ v:SIMD3<Float>)->CGPoint {
    if overhead {
      return CGPoint(x:CGFloat(variant*tile+tile/2)+CGFloat((v.x-(loX+hiX)/2)*fit),
                     y:CGFloat(tile/2)+CGFloat((v.z-topZ)*fit))
    }
    return CGPoint(x:CGFloat(variant*tile+tile/2)+CGFloat((v.x-(loX+hiX)/2)*fit),y:CGFloat(tile+4)+CGFloat(v.y*fit))
  }
  canvas.saveGState()
  canvas.clip(to:CGRect(x:variant*tile,y:overhead ? 0 : tile,width:tile,height:tile))
  canvas.setLineCap(.round)
  for twig in wood.sorted(by:{$0.b.z>$1.b.z}) {
    let amount=CGFloat(min(1,twig.b.y/high))
    canvas.setStrokeColor(CGColor(red:0.20+0.10*amount,green:0.19+0.10*amount,blue:0.15+0.08*amount,alpha:1))
    canvas.setLineWidth(CGFloat(max(0.44,twig.width*2*fit)));canvas.move(to:point(twig.a));canvas.addLine(to:point(twig.b));canvas.strokePath()
  }
  let sorted=overhead ? leaves.sorted{$0.p.y<$1.p.y} : leaves.sorted{$0.p.z>$1.p.z}
  for leaf in sorted {
    let back=leaf.p.z*0.3, north=leaf.p.y/high, flank = -leaf.p.x/(hiX-loX)
    let lit=CGFloat(max(0,min(1,leaf.light*(0.43+0.49*north+0.18*flank)-0.09*back)))
    let yellow:CGFloat=variant%3==2 ? 0.068:0
    canvas.setFillColor(CGColor(red:0.09+lit*(0.21+yellow),green:0.16+lit*0.32,blue:0.095+lit*0.14,alpha:1))
    let at=point(leaf.p),r=CGFloat(leaf.radius*fit)
    canvas.fillEllipse(in:CGRect(x:at.x-r,y:at.y-r*0.78,width:2*r,height:r*(1.1+CGFloat(abs(sin(leaf.angle)))*0.61)))
  }
  canvas.restoreGState()
  }
}
let output=URL(fileURLWithPath:CommandLine.arguments[1])
try NSBitmapImageRep(cgImage:canvas.makeImage()!).representation(using:.png,properties:[:])!.write(to:output)
