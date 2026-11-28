import RealityKit
import UIKit

/// Drives the same skinned asset in the match, slow-motion replay and kit studio.
/// Major joints are siblings under an identity root, so recorded positions are
/// applied directly. Each hand carries its own local finger chains.
@MainActor final class AnatomicalAthlete {
  private enum Joint: String, CaseIterable {
    case root, pelvis, chest, neck, head, jaw, upperLip
    case upperArmL, forearmL, handL, thighL, shinL, footL
    case upperArmR, forearmR, handR, thighR, shinR, footR
    case palmL, gripAxisL, palmR, gripAxisR
    case lidTopL, lidTopR, lidBottomL, lidBottomR
    case eyeL, eyeR, toeL, toeR, heelL, heelR
    case deltoidL, deltoidR, elbowCapL, elbowCapR, hipCapL, hipCapR, kneeCapL, kneeCapR
    case deltoidInnerL, deltoidOuterL, deltoidInnerR, deltoidOuterR
    case elbowCapInnerL, elbowCapOuterL, elbowCapInnerR, elbowCapOuterR
    case hipCapInnerL, hipCapOuterL, hipCapInnerR, hipCapOuterR
    case kneeCapInnerL, kneeCapOuterL, kneeCapInnerR, kneeCapOuterR
    case browL, browR, cheekL, cheekR
    case waist, clavL, clavR, twistL, twistR, tailBase, tailTip
  }
  struct SoleContact {
    let toe, heel: SIMD3<Float>
  }
  private(set) var soles = Array(repeating: SoleContact(toe: .zero, heel: .zero), count: 2)
  private(set) var palms = [SIMD3<Float>](repeating:.zero,count:2)
  private let modelScale: Float
  let entity: ModelEntity
  private let rest: [SIMD3<Float>]
  private let bindRotation: [simd_quatf]
  private var transforms: [Transform]
  private let index: [Joint:Int]
  private struct Finger {
    let index, side: Int
    let axis: SIMD3<Float>
    let bend: Float
    let fist: simd_quatf
  }
  private var elbowBends = [ElbowBend(),ElbowBend()]
  private let fingers: [Finger]
  private let arms, legs: [LimbGeometry]
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
    let bindPoints = transforms.map(\.translation)
    let bodyHeight = (bindPoints[keys[.upperArmR]!].y + bindPoints[keys[.upperArmL]!].y
                      - bindPoints[keys[.thighR]!].y - bindPoints[keys[.thighL]!].y)*0.5
    modelScale = 0.49/bodyHeight
    let scale = modelScale
    rest = bindPoints.map { $0*scale }
    copy.scale = SIMD3(repeating:scale)
    bindRotation = transforms.map(\.rotation)
    index = keys
    // Close the fingers toward this mesh's palm. The thumb opposes the
    // index and middle knuckles instead of bending about their shared axis.
    // Imported digit offsets are local to their parent, unlike the arm joints.
    let names = Dictionary(uniqueKeysWithValues:copy.jointNames.enumerated().map { (String($0.element.split(separator:"/").last!),$0.offset) })
    guard (1...5).allSatisfy({ n in (1...3).allSatisfy { names["digit\(n)\($0)L"] != nil } }) else { return nil }
    let points = rest
    func digitOffset(_ finger: Int,_ segment: Int) -> SIMD3<Float> {
      points[names["digit\(finger)\(segment)L"]!]
    }
    let knuckles = (2...5).map { digitOffset($0,1) }
    let along = simd_normalize(knuckles.reduce(.zero,+)*0.25)
    let across = simd_normalize(knuckles[0]-knuckles[3])
    let inward = simd_normalize(simd_cross(-across,along))
    var fistRotations: [Int:simd_quatf] = [:]
    for digit in 1...5 {
      var parent = simd_quatf(real:1,imag:.zero), at = digitOffset(digit,1)
      for segment in 1...3 {
        let resting = digitOffset(digit,min(3,segment+1))
        let direction: SIMD3<Float>
        if digit == 1 {
          // The pad lies over the folded index, with the tip toward the middle finger.
          let opposition = [knuckles[0]+inward*0.017,
                            knuckles[0]+inward*0.033+along*0.007,
                            knuckles[1]+inward*0.028+along*0.004]
          direction = simd_normalize(opposition[segment-1]-at)
        } else {
          let rays = [inward*0.91+along*0.42,-along*0.97+inward*0.24,-along*0.67-inward*0.74]
          direction = simd_normalize(rays[segment-1])
        }
        let bone = simd_quatf(from:simd_normalize(resting),to:direction)
        fistRotations[digit*10+segment] = parent.inverse*bone
        parent = bone; at += direction*simd_length(resting)
      }
    }
    var fingerRig: [Finger] = []
    for (i,path) in copy.jointNames.enumerated() {
      guard let label = path.split(separator:"/").last, label.hasPrefix("digit") else { continue }
      let digits = Array(label.dropFirst(5))
      guard digits.count == 3, let finger = digits[0].wholeNumberValue,
        let segment = digits[1].wholeNumberValue, (1...3).contains(segment) else { continue }
      let right = digits[2] == "R"
      let line = rest[keys[right ? .gripAxisR : .gripAxisL]!]-rest[keys[right ? .palmR : .palmL]!]
      let angles: [Float] = [0.71,1.08,0.77]
      let bend = angles[segment-1]*(finger == 1 ? 0.32 : 0.95+Float(finger-2)*0.035)
      fingerRig.append(Finger(index:i,side:right ? 1 : 0,axis:simd_normalize(line),bend:bend*(right ? 1 : -1),fist:fistRotations[finger*10+segment]!))
    }
    fingers = fingerRig
    shoulderMid = (rest[keys[.upperArmL]!] + rest[keys[.upperArmR]!]) * 0.5
    hipMid = (rest[keys[.thighL]!] + rest[keys[.thighR]!]) * 0.5
    let joints = rest
    func chain(_ start: Joint, _ middle: Joint, _ end: Joint) -> LimbGeometry {
      LimbGeometry(upper: simd_distance(joints[keys[start]!],joints[keys[middle]!]),
                   lower: simd_distance(joints[keys[middle]!],joints[keys[end]!]))
    }
    arms = [chain(.upperArmL,.forearmL,.handL), chain(.upperArmR,.forearmR,.handR)]
    legs = [chain(.thighL,.shinL,.footL), chain(.thighR,.shinR,.footR)]
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
    let surface = name == "Wristband" && kit.wristband == .none ? "Skin" : name
    switch surface {
    case "Skin","TankSkin","CrewSkin":
      hidden = (name == "TankSkin" && kit.shirt != .sleeveless) || (name == "CrewSkin" && kit.shirt == .sleeveless)
      let tones: [SkinTone:UIColor] = [.porcelain:.white,
        .honey:UIColor(red:0.91,green:0.81,blue:0.72,alpha:1),
        .bronze:UIColor(red:0.79,green:0.64,blue:0.54,alpha:1),
        .umber:UIColor(red:0.64,green:0.47,blue:0.38,alpha:1),
        .espresso:UIColor(red:0.46,green:0.33,blue:0.28,alpha:1)]
      color = tones[kit.skinTone] ?? .white; image = body+"Skin.jpg"
      mat.roughness = .init(floatLiteral:0.63)
    case "Brows","Lashes":
      image = name == "Brows" ? body+"Brows.png" : "CourtLashes.png"
      mat.faceCulling = .none
      mat.opacityThreshold = 0.32
    case "Hair":
      image = body+"Hair.png"
      mat.faceCulling = .none
      mat.opacityThreshold = 0.37
    case "Wristband":
      color = kit.wristband == .match ? kit.color.tint : .white
      mat.roughness = .init(floatLiteral:0.95)
    case "Teeth": image = "CourtTeeth.jpg"; mat.roughness = .init(floatLiteral:0.46)
    case "Eyes":
      image = "AthleteEyes.jpg"; mat.roughness = .init(floatLiteral:0.27)
    case "Shoe": image = "CourtShoes.jpg"
    case "Sock":
      color = UIColor(white:0.90,alpha:1)
    case "Shorts","Liner","Skort":
      switch kit.bottomColor {
      case .graphite: color = UIColor(red:0.22,green:0.26,blue:0.31,alpha:1)
      case .white: color = UIColor(white:0.97,alpha:1)
      case .match: color = kit.color.tint
      }
      image = "CourtKit.jpg"
      hidden = name == "Shorts" ? kit.skort : !kit.skort
    case "Tank","TankBinding":
      hidden = kit.shirt != .sleeveless
      color = name == "TankBinding" ? kit.color.tint.sidePanelTint : kit.color.tint
      mat.roughness = .init(floatLiteral:0.88)
    case "SidePanel":
      hidden = kit.shirt == .sleeveless
      color = kit.color.tint.sidePanelTint
      image = "CourtKit.jpg"
    case "Shirt","Sleeves":
      color = kit.color.tint; image = "CourtKit.jpg"
      hidden = kit.shirt == .sleeveless
    case "Collar":
      color = kit.color.tint.sidePanelTint
      hidden = kit.shirt != .polo
    case "CollarEdge","SleeveEdge":
      color = kit.color == .white ? UIColor(red:0.12,green:0.30,blue:0.25,alpha:1) : UIColor(white:0.92,alpha:1)
      hidden = kit.shirt != .polo
    case "Headband": hidden = kit.prop == .plain
    case "Visor": color = kit.color.tint; hidden = kit.prop != .visor
    default: break
    }
    mat.baseColor = .init(tint:color,texture:image.flatMap(texture))
    if ["Tank","TankBinding","Shirt","SidePanel","Sleeves","Shorts","Liner","Skort","Sock","Collar","CollarEdge"].contains(name) { mat.faceCulling = .none }
    if ["Shirt","SidePanel","Sleeves","Shorts","Liner"].contains(name), let normal = texture("CourtKitNormal.jpg") {
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
    transforms[i].translation = point/modelScale
  }

  /// The mesh bake weights each vertex between adjacent frames on this arc.
  /// All frames rotate rigidly around the same anatomical joint centre.
  private func setBendArc(_ joints: (Joint,Joint,Joint), at pivot: SIMD3<Float>, from a: simd_quatf, to b: simd_quatf) {
    let half = simd_slerp(a,b,0.5)
    set(joints.0,at:pivot,rotation:simd_slerp(a,half,0.5))
    set(joints.1,at:pivot,rotation:half)
    set(joints.2,at:pivot,rotation:simd_slerp(half,b,0.5))
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
        let from = simd_normalize(x), to = simd_normalize(y)
        // A nearly straight limb carries little roll information. Suppress
        // that correction gradually, including when the bend planes oppose.
        let confidence = min(1, simd_length(y) / 0.115)
        let twist = atan2(simd_dot(axis,simd_cross(from,to)),max(0.40,simd_dot(from,to)))
        rotation = simd_quatf(angle:twist*confidence,axis:axis)*rotation
      }
    }
    set(joint,at:a,rotation:rotation)
    return rotation
  }

  func pose(_ p: AthletePose, handshake: Bool) {
    var hip = (p[.leftHip]+p[.rightHip])*0.5
    let capturedShoulder = (p[.leftShoulder]+p[.rightShoulder])*0.5
    let hipAxis = simd_normalize(p[.rightHip]-p[.leftHip])
    let sign: Float = side == 0 ? 1 : -1
    let hipYaw = atan2(-hipAxis.z*sign,hipAxis.x*sign)
    let facing = simd_quatf(angle:side == 0 ? 0 : .pi,axis:[0,1,0])
    // Heading follows the hips. A torso lean must not tip an otherwise
    // planted shoe through the court while the support knee is flexing.
    let footFacing = facing*simd_quatf(angle:hipYaw*(handshake ? 1 : 0.27),axis:[0,1,0])
    func footTarget(_ i: Int) -> (rotation: simd_quatf, ankle: SIMD3<Float>, toe: SIMD3<Float>, heel: SIMD3<Float>) {
      let right = i == 1
      let foot = anchor(right ? .footR : .footL)
      let toe = anchor(right ? .toeR : .toeL)-foot
      let heel = anchor(right ? .heelR : .heelL)-foot
      let heading: simd_quatf
      if !handshake, let recorded = p.soleHeading {
        heading = facing*simd_quatf(angle:recorded[i],axis:[0,1,0])
      } else { heading = footFacing*simd_quatf(angle:p.shoeYaw[i],axis:[0,1,0]) }
      let toeAtPlant = heading*simd_quatf(angle:p.toePivotYaw[i],axis:[0,1,0])
      let rotation = heading*simd_quatf(angle:-p.heelPitch-p.footRoll[i],axis:[1,0,0])
      let shoe = p[right ? .rightShoe : .leftShoe]
      // Pivot around the forefoot and land on whichever sole marker is lower.
      var ankle = shoe+toeAtPlant.act(toe)-rotation.act(toe)
      let clearance = max(0,shoe.y-0.06-0.14*sin(p.heelPitch))
      ankle.y = clearance-min(rotation.act(toe).y,rotation.act(heel).y)
      return (rotation,ankle,toe,heel)
    }
    let feetTargets = (left:footTarget(0),right:footTarget(1))
    var settle: Float = 0
    for i in 0...1 {
      let right = i == 1
      let referenceHip = p[right ? .rightHip : .leftHip]
      let knee = p[right ? .rightKnee : .leftKnee]
      var referenceAnkle = p[right ? .rightShoe : .leftShoe]
      referenceAnkle.y += 0.18*max(0,sin(p.heelPitch+p.footRoll[i])-sin(p.heelPitch))
      let span = legs[i].span(matching:knee-referenceHip,lowerRay:referenceAnkle-knee)
      let socket = hip+hipAxis*(anchor(right ? .thighR : .thighL).x-hipMid.x)
      let ankle = right ? feetTargets.right.ankle : feetTargets.left.ankle
      let d = socket-ankle
      let reach = min(span,(legs[i].upper+legs[i].lower)*0.995)
      let height = sqrt(max(0,reach*reach-d.x*d.x-d.z*d.z))
      settle = max(settle,d.y-height)
    }
    hip.y -= min(0.21,settle)
    // On a cut the short rig may still be too far from the planted ankle.
    // Transfer the pelvis toward that support leg instead of hauling its sole
    // off the ground. Each correction preserves the rig's segment lengths.
    for _ in 0..<2 {
      for i in 0...1 {
        let ankle = i == 1 ? feetTargets.right.ankle : feetTargets.left.ankle
        let socket = hip+hipAxis*(anchor(i == 1 ? .thighR : .thighL).x-hipMid.x)
        let leg = socket-ankle
        let limit = (legs[i].upper+legs[i].lower)*0.993
        let distance = simd_length(leg)
        if distance > limit { hip -= leg*(1-limit/distance) }
      }
    }
    let chestLine = simd_normalize(p[.rightShoulder]-p[.leftShoulder])
    let socket = capturedShoulder+chestLine*(anchor(.upperArmR).x-shoulderMid.x)
    let handRay = p[.grip]-socket, handDistance = simd_length(handRay)
    let radius = arms[1].upper+arms[1].lower+simd_distance(anchor(.handR),anchor(.palmR))
    let reachLean = handRay/max(handDistance,0.001)*min(0.10,max(0,handDistance-radius+0.015))
    let shoulder = hip+simd_normalize(capturedShoulder+reachLean-hip)*simd_distance(shoulderMid,hipMid)
    let up = simd_normalize(shoulder-hip)
    func basis(_ line: SIMD3<Float>) -> simd_quatf {
      let x = simd_normalize(line)
      let z = simd_normalize(simd_cross(x,up))
      return simd_quatf(simd_float3x3(columns:(x,simd_cross(z,x),z)))
    }
    let hips = basis(p[.rightHip]-p[.leftHip]), chest = basis(p[.rightShoulder]-p[.leftShoulder])
    let gaze = handshake ? SIMD2<Float>.zero : p.gaze
    let head = simd_slerp(handshake ? hips : facing,chest,0.22) * simd_quatf(angle:-gaze.x * 0.84,axis:[0,1,0])
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
    set(.jaw,at:headCenter+head.act(anchor(.jaw)-anchor(.head)),
        rotation:head*simd_quatf(angle:-p.jawOpen*0.20,axis:[1,0,0]))
    let lip = anchor(.upperLip)-anchor(.head)+SIMD3<Float>(0,p.jawOpen*0.002,-p.lipRound*0.005)
    set(.upperLip,at:headCenter+head.act(lip),rotation:head)
    for (lid,angle) in [(Joint.lidTopL,-0.46),(.lidTopR,-0.46),(.lidBottomL,0.10),(.lidBottomR,0.10)] {
      set(lid,at:headCenter+head.act(anchor(lid)-anchor(.head)),
          rotation:head*simd_quatf(angle:Float(angle)*p.blink,axis:[1,0,0]))
    }
    for right in [false,true] {
      let sign: Float = right ? 1 : -1
      let brow: Joint = right ? .browR : .browL
      let cheek: Joint = right ? .cheekR : .cheekL
      let gather = SIMD3<Float>(-sign*0.002,-0.003,0)*p.focus
      let lift = SIMD3<Float>(sign*0.0035,0.004,-0.0015)*p.reactionFist
      set(brow,at:headCenter+head.act(anchor(brow)-anchor(.head)+gather),rotation:head)
      set(cheek,at:headCenter+head.act(anchor(cheek)-anchor(.head)+lift),rotation:head)
    }
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
    let lateral = chest.act([1,0,0]), anterior = chest.act([0,0,-1])
    func outsideTorso(_ target: SIMD3<Float>, right: Bool) -> SIMD3<Float> {
      let depth = (shoulder.y-target.y)/max(0.18,shoulder.y-hip.y)
      let fade = min(1,max(0,(depth+0.07)*12))*min(1,max(0,(1.22-depth)*10))
      guard fade > 0 else { return target }
      let center = shoulder+(hip-shoulder)*min(1,max(0,depth))
      let relative = target-center
      let x = simd_dot(relative,lateral), z = simd_dot(relative,anterior)
      let width: Float = 0.175 - 0.018*min(1,max(0,depth)), thickness: Float = 0.128
      let radius = hypot(x/width,z/thickness)
      guard radius < 1 else { return target }
      let bias: Float = max(0,0.35-radius)
      let outward = SIMD2<Float>(x/width+(right ? bias : -bias),z/thickness+bias)
      let direction = outward/max(0.001,simd_length(outward))
      return target+(lateral*(direction.x*width-x)+anterior*(direction.y*thickness-z))*fade
    }
    // The elbow can sit outside the shirt while the upper arm still cuts
    // across the chest. Test the links as well as the hinge, then rotate the
    // bent elbow about the shoulder–wrist line. Both bone lengths stay fixed.
    func clearElbow(_ elbow: SIMD3<Float>, socket: SIMD3<Float>, wrist: SIMD3<Float>, right: Bool) -> SIMD3<Float> {
      let sign: Float = right ? 1 : -1
      if min(simd_dot(elbow-shoulder,lateral)*sign,simd_dot(wrist-shoulder,lateral)*sign) > 0.20 { return elbow }
      func clearance(_ point: SIMD3<Float>) -> Float {
        let depth = (shoulder.y-point.y)/max(0.20,shoulder.y-hip.y)
        guard depth > 0.01 && depth < 1.07 else { return 2 }
        let relative = point-(shoulder+(hip-shoulder)*depth)
        let x = simd_dot(relative,lateral)/(0.192-0.018*depth)
        let z = simd_dot(relative,anterior)
        let front = z/(z >= 0 ? 0.181 : 0.150)
        return x*x+front*front
      }
      func pathMargin(_ e: SIMD3<Float>) -> Float {
        min(clearance(socket+(e-socket)*0.37),clearance(socket+(e-socket)*0.72),
            clearance(e),clearance((e+wrist)*0.5))
      }
      let initial = pathMargin(elbow)
      guard initial < 1 else { return elbow }
      let axis = simd_normalize(wrist-socket)
      let center = socket+axis*simd_dot(elbow-socket,axis)
      let radial = elbow-center, radius = simd_length(radial)
      guard radius > 0.001 else { return elbow }
      let away = anterior*0.92+lateral*(0.64*sign)-up*0.14
      let preferred = away-axis*simd_dot(away,axis)
      guard simd_length_squared(preferred) > 0.0001 else { return elbow }
      let destination = simd_normalize(preferred)
      let turn = atan2(simd_dot(axis,simd_cross(radial,destination)),simd_dot(radial,destination))
      let final = center+destination*radius
      let gain = pathMargin(final)-initial
      guard gain > 0.001 else { return elbow }
      let amount = min(1,(1-initial)/gain)
      return center+simd_quatf(angle:turn*amount,axis:axis).act(radial)
    }
    var gripCorrection = SIMD3<Float>.zero
    for right in [true,false] {
      let upper: Joint = right ? .upperArmR : .upperArmL, fore: Joint = right ? .forearmR : .forearmL
      let hand: Joint = right ? .handR : .handL
      let thigh: Joint = right ? .thighR : .thighL, shin: Joint = right ? .shinR : .shinL
      let foot: Joint = right ? .footR : .footL
      let palmJoint: Joint = right ? .palmR : .palmL
      let across: Joint = right ? .gripAxisR : .gripAxisL
      let index = right ? 1 : 0
      let elbowGuide = outsideTorso(p[right ? .rightElbow : .leftElbow],right:right)
      let clav: Joint = right ? .clavR : .clavL
      let pivot = shoulder+chest.act(anchor(clav)-shoulderMid)
      let socket = shoulder+chest.act(anchor(upper)-shoulderMid)
      let arm = simd_normalize(elbowGuide-socket)
      // The shoulder blade rises with an overhead arm and glides forward on
      // a two-handed drive. The shirt collar follows the collarbone weights.
      let elevation = max(0,simd_dot(arm,up)+0.12)
      let ahead = chest.act([0,0,-1])
      let targetHand = p[right ? .grip : .leftHand]
      let acrossBody = min(1,max(0,-simd_dot(targetHand-shoulder,lateral)*(right ? 1 : -1)/0.32))
      let glide = up*(elevation*0.055)+ahead*(max(0,simd_dot(arm,ahead))*0.024+0.082*acrossBody)
      let clavRotation = simd_quatf(from:simd_normalize(socket-pivot),
                                    to:simd_normalize(socket+glide-pivot))*chest
      set(clav,at:pivot,rotation:clavRotation)
      let s = pivot+clavRotation.act(anchor(upper)-anchor(clav))
      let targetPalm = p[right ? .grip : .leftHand] + (right ? .zero : gripCorrection*p.supportGrip)
      let clearPalm = outsideTorso(targetPalm,right:right)
      let palm = clearPalm+(targetPalm-clearPalm)*(right ? p.airborneReach : p.supportGrip)
      let offset = anchor(hand)-anchor(palmJoint)
      // Align the knuckles with the forearm when the hand is free. Using the
      // bind-pose forearm alone leaves the wrist cocked as the running arm swings.
      let palmDirection = simd_normalize(palm-elbowGuide)
      let restHand = simd_normalize(anchor(palmJoint)-anchor(hand))
      let natural = simd_quatf(from:chest.act(restHand),to:palmDirection)*chest
      let attachment: Float = handshake ? (right ? 0 : 1) : right ? 1 : p.supportGrip
      let bend = chest.act([right ? 0.6 : -0.6,-0.6,0.5])
      func orientHand(elbow: SIMD3<Float>) -> simd_quatf {
        let alongArm = simd_normalize(palm-elbow)
        let open = simd_quatf(from:natural.act(restHand),to:alongArm)*natural
        guard attachment > 0 else { return open }
        let handle = handshake ? p.handshakeRacketAxis : simd_normalize(p[.strings]-p[.grip])
        let knuckles = simd_normalize(anchor(across)-anchor(palmJoint))
        // A tennis handle crosses the palm diagonally. Let that diagonal
        // vary between the knuckle line and the heel of the hand as the
        // racket lays back, without moving the grip off the handle.
        let diagonal = max(-0.44,min(0.44,simd_dot(handle,alongArm)-simd_dot(knuckles,restHand)))
        let gripAxis = simd_normalize(knuckles+restHand*diagonal)
        let bind = handBasis(gripAxis,towardWrist:offset)
        let aligned = simd_quatf(from:open.act(gripAxis),to:handle)*open
        let wrist = elbow-palm
        let projected = wrist-handle*simd_dot(wrist,handle)
        let confidence = min(1,simd_length(projected)/0.14)
        let facing = simd_slerp(aligned,handBasis(handle,towardWrist:projected)*bind.inverse,
                                 confidence*confidence*(3-2*confidence))
        let held = simd_slerp(open,facing,attachment*attachment*(3-2*attachment))
        // At the deepest racket drop and a low volley, let the handle sit
        // farther across the fingers before forcing a retroflexed wrist.
        // The wrist is behind the palm by |offset|. The sine rule converts
        // the wrist limit to an angle measured from the elbow to the palm.
        let limit: Float = 1.13
        let lever = max(0.001,simd_distance(palm,elbow))
        let allowed = max(0,limit-asin(min(1,simd_length(offset)*sin(limit)/lever)))
        let palmAxis = held.act(restHand)
        let turn = simd_quatf(from:palmAxis,to:alongArm)
        guard turn.angle > allowed, turn.angle > 0.001 else { return held }
        return simd_slerp(simd_quatf(real:1,imag:.zero),turn,1-allowed/turn.angle)*held
      }
      // The offset from the grip centre to the wrist changes with pronation.
      // Resolve it against the retargeted elbow, then keep that palm fixed.
      let palmChain = LimbGeometry(upper: arms[index].upper, lower: arms[index].lower+simd_length(offset))
      let freeElbow = palmChain.hinge(from:s,to:palm,guide:elbowGuide,fallback:bend)
      var handRotation = orientHand(elbow:freeElbow)
      var wristPoint = palm+handRotation.act(offset)
      if attachment > 0 {
        let provisional = arms[index].hinge(from:s,to:wristPoint,guide:elbowGuide,fallback:bend)
        handRotation = orientHand(elbow:provisional)
        wristPoint = palm+handRotation.act(offset)
      }
      wristPoint = arms[index].reachable(from:s,toward:wristPoint)
      palms[index] = wristPoint-handRotation.act(offset)
      if right { gripCorrection = palms[index]-palm }
      let guide = arms[index].hinge(from:s,to:wristPoint,guide:elbowGuide,fallback:bend)
      let posed = arms[index].hinge(from:s,to:wristPoint,guide:outsideTorso(guide,right:right),fallback:bend)
      let clear = clearElbow(posed,socket:s,wrist:wristPoint,right:right)
      let e = elbowBends[index].follow(clear,shoulder:s,wrist:wristPoint,time:handshake ? nil : p.sampleTime)
      let upperRotation = align(upper,end:fore,from:s,to:e,base:chest,
                pole:(anchor(hand)-anchor(fore),wristPoint-e))
      let proximal = align(fore,end:hand,from:e,to:wristPoint,base:upperRotation)
      setBendArc(right ? (.deltoidInnerR,.deltoidR,.deltoidOuterR) : (.deltoidInnerL,.deltoidL,.deltoidOuterL),
           at:s,from:clavRotation,to:upperRotation)
      setBendArc(right ? (.elbowCapInnerR,.elbowCapR,.elbowCapOuterR) : (.elbowCapInnerL,.elbowCapL,.elbowCapOuterL),
           at:e,from:upperRotation,to:proximal)
      let twist: Joint = right ? .twistR : .twistL
      let t = min(1,simd_distance(anchor(twist),anchor(fore))/simd_distance(anchor(hand),anchor(fore)))
      let axis = simd_normalize(wristPoint-e)
      let delta = handRotation*proximal.inverse
      // Resolve only the wrist's twist about the long bones of the forearm.
      let signedRoll = atan2(simd_dot(delta.imag,axis),delta.real)*2
      // Beyond anatomical pronation the wrist supplies no reliable roll
      // sign. Ease to neutral through that seam during a frame-by-frame seek.
      let roll = atan2(sin(signedRoll),max(0.18,cos(signedRoll)))
      let sleeve = simd_quatf(angle:max(-1.48,min(1.48,roll))*t,axis:axis)*proximal
      set(twist,at:e+(wristPoint-e)*t,rotation:sleeve)
      set(hand,at:wristPoint,rotation:handRotation)
      let h = hip+hips.act(anchor(thigh)-hipMid)
      let target = right ? feetTargets.right : feetTargets.left
      let feet = target.rotation
      let ankle = legs[index].reachable(from:h,toward:target.ankle)
      let k = legs[index].hinge(from: h, to: ankle, guide: p[right ? .rightKnee : .leftKnee],
                                fallback: feet.act([right ? 0.12 : -0.12,0,-1]))
      let femur = align(thigh,end:shin,from:h,to:k,base:hips,pole:(anchor(foot)-anchor(shin),ankle-k))
      let tibia = align(shin,end:foot,from:k,to:ankle,base:femur)
      setBendArc(right ? (.hipCapInnerR,.hipCapR,.hipCapOuterR) : (.hipCapInnerL,.hipCapL,.hipCapOuterL),
           at:h,from:hips,to:femur)
      setBendArc(right ? (.kneeCapInnerR,.kneeCapR,.kneeCapOuterR) : (.kneeCapInnerL,.kneeCapL,.kneeCapOuterL),
           at:k,from:femur,to:tibia)
      set(foot,at:ankle,rotation:feet)
      soles[index] = SoleContact(toe: ankle+feet.act(target.toe), heel: ankle+feet.act(target.heel))
    }
    for finger in fingers {
      let curl = p.fingerCurl[finger.side]
      let fist = finger.side == 0 ? p.reactionFist : 0
      let relaxed = simd_quatf(angle:finger.bend*curl,axis:finger.axis)
      transforms[finger.index].rotation = simd_slerp(relaxed,finger.fist,fist)*bindRotation[finger.index]
    }
    // At the apex the feet are free. Carry the whole jumper the final few
    // centimetres to the recorded strings; there is no bone stretch or foot slide.
    let airborneOffset = (p[.grip]-palms[1])*p.airborneReach
    entity.position = airborneOffset
    for i in 0..<2 {
      palms[i] += airborneOffset
      soles[i] = SoleContact(toe:soles[i].toe+airborneOffset,heel:soles[i].heel+airborneOffset)
    }
    entity.jointTransforms = transforms
  }
}


private extension UIColor {
  var sidePanelTint: UIColor {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
    getRed(&r, green:&g, blue:&b, alpha:&a)
    return UIColor(red:r*0.65,green:g*0.75,blue:b*0.81,alpha:a)
  }
}
