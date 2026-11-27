import RealityKit
import UIKit

/// Drives the same skinned asset in the match, slow-motion replay and kit studio.
/// The USD joints are siblings under an identity root. A recorded joint can be
/// positioned directly, without inheriting a second rotation from its parent.
@MainActor final class AnatomicalAthlete {
  private enum Joint: String, CaseIterable {
    case root, pelvis, chest, neck, head
    case upperArmL, forearmL, handL, thighL, shinL, footL
    case upperArmR, forearmR, handR, thighR, shinR, footR
    case palmL, gripAxisL, palmR, gripAxisR
    case eyeL, eyeR, toeL, toeR, heelL, heelR
    case waist, clavL, clavR, twistL, twistR, tailBase, tailTip
  }
  let entity: ModelEntity
  private let rest: [SIMD3<Float>]
  private let bindRotation: [simd_quatf]
  private var transforms: [Transform]
  private let index: [Joint:Int]
  private let shoulderMid, hipMid: SIMD3<Float>
  private let side: Int
  private static var models: [String:ModelEntity] = [:]
  private static var maps: [String:TextureResource] = [:]

  init?(kit: AthleteKit, side: Int) {
    self.side = side
    let name = kit.model == .man ? "CourtMan" : "CourtWoman"
    if Self.models[name] == nil, let url = Bundle.main.url(forResource:name,withExtension:"usdz"),
       let asset = try? Entity.load(contentsOf:url), let model = asset.findEntity(named:"Athlete") as? ModelEntity {
      Self.models[name] = model
    }
    guard let copy = Self.models[name]?.clone(recursive:true) else { return nil }
    entity = copy
    var keys: [Joint:Int] = [:]
    for (i,path) in copy.jointNames.enumerated() {
      if let name = path.split(separator:"/").last, let joint = Joint(rawValue:String(name)) { keys[joint] = i }
    }
    guard keys.count == Joint.allCases.count else { return nil }
    transforms = copy.jointTransforms
    rest = transforms.map(\.translation)
    bindRotation = transforms.map(\.rotation)
    index = keys
    shoulderMid = (rest[keys[.upperArmL]!] + rest[keys[.upperArmR]!]) * 0.5
    hipMid = (rest[keys[.thighL]!] + rest[keys[.thighR]!]) * 0.5
    if var component = copy.model {
      // iOS 17 exposes the original mesh child names but not Material.name.
      let parts = copy.children.map(\.name).filter { $0 != "Rig" }
      component.materials = component.materials.enumerated().map { i, material in
        if #available(iOS 18.0, *), let name = material.name { return Self.material(name,kit:kit) }
        return i < parts.count ? Self.material(parts[i],kit:kit) : material
      }
      copy.model = component
    }
  }

  private static func texture(_ name: String) -> MaterialParameters.Texture? {
    if let cached = maps[name] { return .init(cached) }
    guard let url = Bundle.main.url(forResource:name,withExtension:nil),
          let map = try? TextureResource.load(contentsOf:url, options:.init(semantic:name.contains("Normal") ? .normal : .color)) else { return nil }
    maps[name] = map
    return .init(map)
  }

  private static func material(_ name: String, kit: AthleteKit) -> PhysicallyBasedMaterial {
    let body = kit.model == .man ? "Man" : "Woman"
    var mat = PhysicallyBasedMaterial()
    mat.roughness = .init(floatLiteral:0.8)
    var color = UIColor.white
    var image: String?
    var hidden = false
    switch name {
    case "Skin":
      let tones: [SkinTone:UIColor] = [.porcelain:.white,
        .honey:UIColor(red:0.91,green:0.81,blue:0.72,alpha:1),
        .bronze:UIColor(red:0.79,green:0.64,blue:0.54,alpha:1),
        .umber:UIColor(red:0.64,green:0.47,blue:0.38,alpha:1),
        .espresso:UIColor(red:0.46,green:0.33,blue:0.28,alpha:1)]
      color = tones[kit.skinTone] ?? .white; image = body+"Skin.jpg"
      mat.roughness = .init(floatLiteral:0.63)
    case "Hair":
      image = body+"Hair.png"
      mat.faceCulling = .none
      mat.opacityThreshold = 0.37
    case "Wristband":
      color = kit.wristband == .match ? kit.color.tint : .white
      hidden = kit.wristband == .none; image = "CourtKit.jpg"
    case "Eyes":
      image = "AthleteEyes.jpg"; mat.roughness = .init(floatLiteral:0.27)
    case "Shoe": image = "CourtShoes.jpg"
    case "Sock":
      color = UIColor(white:0.90,alpha:1)
    case "Shorts","Skort":
      switch kit.bottomColor {
      case .graphite: color = UIColor(red:0.22,green:0.26,blue:0.31,alpha:1)
      case .white: color = UIColor(white:0.97,alpha:1)
      case .match: color = kit.color.tint
      }
      image = "CourtKit.jpg"; hidden = name == "Skort" && !kit.skort
    case "Shirt","Sleeves":
      color = kit.color.tint; image = "CourtKit.jpg"
      hidden = name == "Sleeves" && kit.shirt == .sleeveless
    case "Collar","CollarEdge","SleeveEdge":
      color = kit.color == .white ? UIColor(red:0.12,green:0.30,blue:0.25,alpha:1) : UIColor(white:0.92,alpha:1)
      hidden = kit.shirt != .polo
    case "Headband": hidden = kit.prop == .plain
    case "Visor": color = kit.color.tint; hidden = kit.prop != .visor
    default: break
    }
    mat.baseColor = .init(tint:color,texture:image.flatMap(texture))
    if ["Shirt","Sleeves","Shorts"].contains(name), let normal = texture("CourtKitNormal.jpg") {
      mat.normal = .init(texture:normal)
    }
    if hidden {
      mat.blending = .transparent(opacity:.init(floatLiteral:0))
      mat.opacityThreshold = 0.99
    }
    return mat
  }

  private func anchor(_ joint: Joint) -> SIMD3<Float> { rest[index[joint]!] }
  private func set(_ joint: Joint, at point: SIMD3<Float>, rotation: simd_quatf) {
    let i = index[joint]!
    transforms[i].rotation = rotation * bindRotation[i]
    transforms[i].translation = point
  }

  private func align(_ joint: Joint, end: Joint, from a: SIMD3<Float>, to b: SIMD3<Float>, base: simd_quatf, pole: (rest:SIMD3<Float>,pose:SIMD3<Float>)? = nil) -> simd_quatf {
    let direction = b-a
    var rotation: simd_quatf
    if simd_length_squared(direction) > 0.00001 {
      let bind = base.act(simd_normalize(anchor(end)-anchor(joint)))
      rotation = simd_quatf(from:bind,to:simd_normalize(direction)) * base
    } else { rotation = base }
    if let pole, simd_length_squared(direction)>0.00001 {
      let axis = simd_normalize(direction)
      let src = rotation.act(pole.rest), dst = pole.pose
      let x = src-axis*simd_dot(src,axis), y = dst-axis*simd_dot(dst,axis)
      if min(simd_length_squared(x),simd_length_squared(y))>0.0007 {
        let twist = atan2(simd_dot(axis,simd_cross(x,y)),simd_dot(x,y))
        rotation = simd_quatf(angle:max(-1.12,min(1.12,twist)),axis:axis)*rotation
      }
    }
    set(joint,at:a,rotation:rotation)
    transforms[index[joint]!].scale.y = max(0.72,min(1.48,simd_length(direction)/simd_distance(anchor(end),anchor(joint))))
    return rotation
  }

  func pose(_ p: AthletePose, handshake: Bool) {
    let hip = (p[.leftHip]+p[.rightHip])*0.5
    let shoulder = (p[.leftShoulder]+p[.rightShoulder])*0.5
    let up = simd_normalize(shoulder-hip)
    func basis(_ line: SIMD3<Float>) -> simd_quatf {
      let x = simd_normalize(line)
      let z = simd_normalize(simd_cross(x,up))
      return simd_quatf(simd_float3x3(columns:(x,simd_cross(z,x),z)))
    }
    let hips = basis(p[.rightHip]-p[.leftHip]), chest = basis(p[.rightShoulder]-p[.leftShoulder])
    let facing = simd_quatf(angle:side == 0 ? 0 : .pi,axis:[0,1,0])
    let gaze = handshake ? SIMD2<Float>.zero : p.gaze
    let head = simd_slerp(facing,chest,0.22) * simd_quatf(angle:-gaze.x * 0.84,axis:[0,1,0])
      * simd_quatf(angle:gaze.y*0.8,axis:[1,0,0])
    set(.pelvis,at:hip+hips.act(anchor(.pelvis)-hipMid),rotation:hips)
    let middle = simd_slerp(hips,chest,0.52)
    let waistFraction = (anchor(.waist).y-hipMid.y)/(shoulderMid.y-hipMid.y)
    let spineMid = hip+(shoulder-hip)*waistFraction
    let waistRest = hipMid+(shoulderMid-hipMid)*waistFraction
    set(.waist,at:spineMid+middle.act(anchor(.waist)-waistRest),rotation:middle)
    set(.chest,at:shoulder+chest.act(anchor(.chest)-shoulderMid),rotation:chest)
    let neck = shoulder+chest.act(anchor(.neck)-shoulderMid)
    set(.neck,at:neck,rotation:simd_slerp(chest,head,0.5))
    let headCenter = neck+head.act(anchor(.head)-anchor(.neck))
    set(.head,at:headCenter,rotation:head)
    let base = headCenter+head.act(anchor(.tailBase)-anchor(.head))
    let sway = head * simd_quatf(angle:p.hairSway.x,axis:[0,0,1]) * simd_quatf(angle:p.hairSway.y,axis:[1,0,0])
    set(.tailBase,at:base,rotation:sway)
    let tip = base+sway.act(anchor(.tailTip)-anchor(.tailBase))
    set(.tailTip,at:tip,rotation:sway*simd_quatf(angle:p.hairSway.x*0.55,axis:[0,0,1]))
    let eyes = head * simd_quatf(angle:-gaze.x*0.16,axis:[0,1,0]) * simd_quatf(angle:gaze.y*0.12,axis:[1,0,0])
    for eye in [Joint.eyeL,.eyeR] {
      set(eye,at:headCenter+head.act(anchor(eye)-anchor(.head)),rotation:eyes)
    }
    // The shaft passes through the baked palm landmark, between thumb and
    // curled fingers. The elbow fixes the roll around that shaft.
    func handBasis(_ axis: SIMD3<Float>, towardWrist: SIMD3<Float>) -> simd_quatf {
      let y = simd_normalize(axis)
      var x = towardWrist-y*simd_dot(towardWrist,y)
      if simd_length_squared(x)<0.000001 { x = simd_cross(y,abs(y.x)<0.8 ? [1,0,0] : [0,0,1]) }
      x = simd_normalize(x)
      return simd_quatf(simd_float3x3(columns:(x,y,simd_cross(x,y))))
    }
    let footFacing = simd_slerp(facing,hips,0.27)
    for right in [false,true] {
      let upper: Joint = right ? .upperArmR : .upperArmL, fore: Joint = right ? .forearmR : .forearmL
      let hand: Joint = right ? .handR : .handL
      let thigh: Joint = right ? .thighR : .thighL, shin: Joint = right ? .shinR : .shinL
      let foot: Joint = right ? .footR : .footL
      let palmJoint: Joint = right ? .palmR : .palmL
      let across: Joint = right ? .gripAxisR : .gripAxisL
      let e = p[right ? .rightElbow : .leftElbow]
      let clav: Joint = right ? .clavR : .clavL
      let pivot = shoulder+chest.act(anchor(clav)-shoulderMid)
      let socket = shoulder+chest.act(anchor(upper)-shoulderMid)
      let arm = simd_normalize(e-socket)
      // The shoulder blade rises with an overhead arm and glides forward on
      // a two-handed drive. The shirt collar follows the collarbone weights.
      let elevation = max(0,simd_dot(arm,up)+0.12)
      let ahead = chest.act([0,0,-1])
      let glide = up*(elevation*0.055)+ahead*max(0,simd_dot(arm,ahead))*0.024
      let clavRotation = simd_quatf(from:simd_normalize(socket-pivot),
                                    to:simd_normalize(socket+glide-pivot))*chest
      set(clav,at:pivot,rotation:clavRotation)
      let s = pivot+clavRotation.act(anchor(upper)-anchor(clav))
      let palm = p[right ? .grip : .leftHand]
      let offset = anchor(hand)-anchor(palmJoint)
      let handRotation: simd_quatf
      let wristPoint: CourtPoint3D
      let onGrip = !handshake && (right || simd_distance(palm,p[.grip])<0.12)
      if onGrip {
        let from = handBasis(anchor(across)-anchor(palmJoint),towardWrist:offset)
        let to = handBasis(p[.strings]-p[.grip],towardWrist:e-palm)
        handRotation = to*from.inverse
        wristPoint = palm+handRotation.act(offset)
      } else {
        let forearmAxis = chest.act(simd_normalize(anchor(hand)-anchor(fore)))
        let wrist = simd_quatf(from:forearmAxis,to:simd_normalize(palm-e))*chest
        wristPoint = palm+wrist.act(offset)
        handRotation = wrist
      }
      _ = align(upper,end:fore,from:s,to:e,base:chest,
                pole:(anchor(hand)-anchor(fore),wristPoint-e))
      let proximal = align(fore,end:hand,from:e,to:wristPoint,base:chest)
      let twist: Joint = right ? .twistR : .twistL
      let t = min(1,simd_distance(anchor(twist),anchor(fore))/simd_distance(anchor(hand),anchor(fore)))
      let axis = simd_normalize(wristPoint-e)
      let delta = handRotation*proximal.inverse
      // Resolve only the wrist's twist about the long bones of the forearm.
      let signedRoll = atan2(simd_dot(delta.imag,axis),delta.real)*2
      let roll = atan2(sin(signedRoll),cos(signedRoll))
      let sleeve = simd_quatf(angle:max(-1.48,min(1.48,roll))*t,axis:axis)*proximal
      set(twist,at:e+(wristPoint-e)*t,rotation:sleeve)
      set(hand,at:wristPoint,rotation:handRotation)
      let h = hip+hips.act(anchor(thigh)-hipMid), k = p[right ? .rightKnee : .leftKnee]
      let feet = footFacing * simd_quatf(angle:p.shoeYaw[right ? 1 : 0],axis:[0,1,0])
        * simd_quatf(angle:-p.heelPitch,axis:[1,0,0])
      let shoe = p[right ? .rightShoe : .leftShoe]
      let toe = anchor(right ? .toeR : .toeL)-anchor(foot)
      let heel = anchor(right ? .heelR : .heelL)-anchor(foot)
      // The planted toe remains on its spot while the heel rolls up.
      var ankle = shoe + footFacing.act(toe) - feet.act(toe)
      let lift = max(0,shoe.y-0.06-0.14*sin(p.heelPitch))
      ankle.y = lift-min(feet.act(toe).y,feet.act(heel).y)
      _ = align(thigh,end:shin,from:h,to:k,base:hips,pole:(anchor(foot)-anchor(shin),ankle-k))
      _ = align(shin,end:foot,from:k,to:ankle,base:hips)
      set(foot,at:ankle,rotation:feet)
    }
    entity.jointTransforms = transforms
  }
}
