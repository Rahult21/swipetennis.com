import Foundation
import SceneKit
import AppKit
import Metal
import simd

// Place the clothed figures from the kit room in a set of seated poses.
// Bake the twelve figures at eight viewpoints into one translucent atlas.
let args=CommandLine.arguments
let input=URL(fileURLWithPath:args[1],isDirectory:true)
let output=URL(fileURLWithPath:args[2])
let standing = args.dropFirst(3).first == "ovation"
let poses = standing ? 2 : 1
let elevations: [Float] = [0.096,0.68,1.27]
let tileW=96, tileH=144, people=12, angles=8
let atlas=CGContext(data:nil,width:tileW*people*poses,height:tileH*angles*elevations.count,bitsPerComponent:8,bytesPerRow:0,
                    space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
let renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
let scene=SCNScene()
renderer.scene=scene
let eye=SCNNode()
eye.camera=SCNCamera(); eye.camera!.usesOrthographicProjection=true; eye.camera!.orthographicScale=standing ? 1.02 : 0.715
eye.camera!.zNear=0.1; eye.camera!.zFar=20
scene.rootNode.addChildNode(eye); renderer.pointOfView=eye
let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity=630
scene.rootNode.addChildNode(ambient)
let key=SCNNode(); key.light=SCNLight(); key.light!.type = .directional; key.light!.intensity=730
key.position=SCNVector3(-3,7,-4); key.look(at:SCNVector3(0,0.63,0)); scene.rootNode.addChildNode(key)
let palette:[NSColor] = [.init(srgbRed:0.53,green:0.60,blue:0.65,alpha:1),.init(white:0.76,alpha:1),
 .init(srgbRed:0.34,green:0.49,blue:0.39,alpha:1),.init(srgbRed:0.65,green:0.42,blue:0.37,alpha:1),
 .init(srgbRed:0.66,green:0.62,blue:0.52,alpha:1),.init(srgbRed:0.39,green:0.43,blue:0.61,alpha:1),
 .init(srgbRed:0.36,green:0.45,blue:0.54,alpha:1),.init(srgbRed:0.71,green:0.70,blue:0.68,alpha:1)]
func tinted(_ texture:String,_ tint:NSColor) -> NSImage {
  let original=NSImage(contentsOf:input.appendingPathComponent(texture))!
  let size=original.size
  return NSImage(size:size,flipped:false) { rect in
    original.draw(in:rect)
    tint.setFill(); rect.fill(using:.multiply)
    return true
  }
}
for beat in 0..<poses {
for number in 0..<people {
 let man=number%2==0
 let name=man ? "Man":"Woman"
 let src=try SCNScene(url:input.appendingPathComponent("Court"+name+".usdz"))
 let body=src.rootNode.childNode(withName:"Athlete",recursively:true)!
 body.removeFromParentNode(); scene.rootNode.addChildNode(body)
 let anchor=body.childNode(withName:"Rig",recursively:true)!
 let bones=Dictionary(uniqueKeysWithValues:anchor.childNodes[0].childNodes.map{($0.name ?? "",$0)})
 var joints=bones
 if bones.isEmpty { anchor.enumerateChildNodes{n,_ in joints[n.name ?? ""]=n} }
 let bind = joints.mapValues{$0.simdPosition}
 let rotation = joints.mapValues{$0.simdOrientation}
 func set(_ id:String,_ p:SIMD3<Float>,_ q:simd_quatf) {
   guard let n=joints[id],let rest=rotation[id] else{return}
   n.simdPosition=p; n.simdOrientation=q*rest
 }
 func bone(_ id:String,_ end:String,_ p:SIMD3<Float>,_ next:SIMD3<Float>) {
   set(id,p,simd_quatf(from:simd_normalize(bind[end]!-bind[id]!),to:simd_normalize(next-p)))
 }
 let yaw=Float(number%5-2)*0.095, lean=Float(number%3)*0.075
 let identity=simd_quatf(angle:0,axis:[0,1,0])
 let chest=simd_quatf(angle:-lean,axis:[1,0,0])
 let head=simd_quatf(angle:yaw,axis:[0,1,0])*chest
 let hip=bind["pelvis"]!
 let hipTarget=SIMD3<Float>(0,standing ? 0.94 : 0.46,0.04)
 func torso(_ joint:String)->SIMD3<Float> {hipTarget+chest.act(bind[joint]!-hip)}
 for joint in ["pelvis","waist","chest","neck","clavL","clavR"] {set(joint,torso(joint),chest)}
 let headAt=torso("head")
 for joint in ["head","eyeL","eyeR","tailBase","tailTip"] { set(joint,headAt+head.act(bind[joint]!-bind["head"]!),head) }
 for side in ["L","R"]{
   let dir:Float=side=="L" ? -1:1
   let thigh=torso("thigh"+side)
   let k=standing ? thigh+[dir*0.025,-0.41,-0.07] : SIMD3<Float>(dir*(0.132+Float(number%3)*0.022),0.45,-0.36)
   let ankle=k+[dir*0.008,standing ? -0.43 : -0.39,0.045+0.017*Float(number%3)]
   bone("thigh"+side,"shin"+side,thigh,k);bone("shin"+side,"foot"+side,k,ankle);set("foot"+side,ankle,identity)
   let shoulder=torso("upperArm"+side)
   var elbow=shoulder+[dir*0.062,-0.22,-0.086]
   var hand=k+[0,0.07,0.092]
   if number%4==0 {hand=elbow+[-dir*0.145,0.094,-0.136]}
   if number%4==2 && side=="L" {hand=headAt+[-0.092,-0.048,-0.132]}
   if standing {
     let lift = Float(number%4)*0.055
     elbow = shoulder+[dir*(0.035 + Float(beat)*0.055),-0.18+lift,-0.21]
     hand = SIMD3<Float>(dir*(beat == 0 ? 0.022 : 0.175),shoulder.y-0.005+lift,-0.34)
   }
   bone("upperArm"+side,"forearm"+side,shoulder,elbow)
   bone("forearm"+side,"hand"+side,elbow,hand)
   let t=simd_distance(bind["twist"+side]!,bind["forearm"+side]!)/simd_distance(bind["hand"+side]!,bind["forearm"+side]!)
   set("twist"+side,elbow+(hand-elbow)*t,simd_quatf(from:simd_normalize(bind["hand"+side]!-bind["forearm"+side]!),to:simd_normalize(hand-elbow)))
   set("hand"+side,hand,simd_quatf(from:simd_normalize(bind["palm"+side]!-bind["hand"+side]!),to:simd_normalize(hand-elbow)))
 }
 let tone=CGFloat([0.82,0.60,0.95,0.72,0.52,0.93][number%6])
 body.enumerateChildNodes{n,_ in
   guard let geometry=n.geometry,let id=n.name else{return}
   let material=SCNMaterial();material.lightingModel = .lambert; material.isDoubleSided=true
   switch id {
   case "Skin","SleeveSkin":
     material.diffuse.contents=tinted(name+"Skin.jpg",NSColor(srgbRed:tone,green:tone*0.91,blue:tone*0.82,alpha:1))
     n.isHidden=id=="SleeveSkin" && number%4 != 3
   case "Hair":material.diffuse.contents=input.appendingPathComponent(name+"Hair.png");material.transparencyMode = .aOne
   case "Shirt","Sleeves":material.diffuse.contents=tinted("CourtKit.jpg",palette[(number*5)%palette.count]);n.isHidden=(id=="Sleeves" && number%4==3)
   case "Shorts":material.diffuse.contents=NSColor(srgbRed:0.22,green:0.24,blue:0.27,alpha:1)
   case "Eyes":material.diffuse.contents=input.appendingPathComponent("AthleteEyes.jpg")
   case "Shoe":material.diffuse.contents=input.appendingPathComponent("CourtShoes.jpg")
   case "Sock":material.diffuse.contents=NSColor(white:0.79,alpha:1)
   case "Collar","SleeveEdge","CollarEdge","Headband","Wristband":material.diffuse.contents=NSColor(white:0.83,alpha:1); n.isHidden=number%4 != 0
   case "Visor":material.diffuse.contents=palette[number%8];n.isHidden=number%4 != 0
   default:n.isHidden=true
   }
   geometry.materials=[material]
 }
 for (tier,pitch) in elevations.enumerated() {
 for angle in 0..<angles {
   let yaw=Float(angle)*2*Float.pi/Float(angles)
   let height: Float = standing ? 0.94 : 0.65
   eye.simdPosition=[3*cos(pitch)*sin(yaw),height+3*sin(pitch),-3*cos(pitch)*cos(yaw)]
   eye.look(at:SCNVector3(0,standing ? 0.94 : 0.65,0),
            up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
   let photo=renderer.snapshot(atTime:Double(number*angles+angle),with:CGSize(width:tileW*2,height:tileH*2),antialiasingMode:.multisampling2X)
   guard let image=photo.cgImage(forProposedRect:nil,context:nil,hints:nil) else{fatalError("Missing seated figure")}
   atlas.draw(image,in:CGRect(x:(beat*people+number)*tileW,y:((elevations.count-tier)*angles-1-angle)*tileH,width:tileW,height:tileH))
 }
 }
 body.removeFromParentNode()
}
}
try NSBitmapImageRep(cgImage:atlas.makeImage()!).representation(using:.png,properties:[:])!.write(to:output)
