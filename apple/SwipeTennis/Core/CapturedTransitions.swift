import Foundation

/// Displacements from the first sample of each recorded motion, expressed in metres.
struct CapturedOffset {
  var pelvis: Float = 0
  var left = SIMD2<Float>.zero
  var right = SIMD2<Float>.zero
  var hand = SIMD2<Float>.zero
}

struct CapturedTransitions {
  private static let tracks: [String: [CapturedOffset]] = {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    guard let url = bundle.url(forResource:"tennis-transitions",withExtension:"csv"),
          let csv = try? String(contentsOf:url,encoding:.utf8) else { return [:] }
    var result: [String:[CapturedOffset]] = [:]
    for line in csv.split(separator:"\n").dropFirst() {
      let fields = line.split(separator:",")
      let v = fields.dropFirst().compactMap { Float($0) }
      guard v.count == 7 else { continue }
      result[String(fields[0]), default:[]].append(CapturedOffset(pelvis:v[0],left:[v[3],v[1]],right:[v[4],v[2]],hand:[v[5],v[6]]))
    }
    return result
  }()
  static func sample(_ clip: String, seconds: Float) -> CapturedOffset {
    guard let frames = tracks[clip], !frames.isEmpty else { return CapturedOffset() }
    let cursor = max(0,min(seconds*50,Float(frames.count-1)))
    let index = Int(cursor), t = cursor-Float(index)
    let a = frames[index], b = frames[min(index+1,frames.count-1)]
    return CapturedOffset(pelvis:a.pelvis+(b.pelvis-a.pelvis)*t, left:a.left+(b.left-a.left)*t,
                          right:a.right+(b.right-a.right)*t, hand:a.hand+(b.hand-a.hand)*t)
  }
  private var lastSpeed: Float = 0
  private var braking = false
  private var returning = false
  private var elapsed: Float = 2
  private var clip = "plant"

  mutating func step(speed:Float, remaining:Double, recovering:Bool, dt:Float) -> CapturedOffset {
    let brake = speed > 2.1 && speed < lastSpeed && remaining < Double(speed)*0.65
    let runBack = recovering && speed > 1.25
    if brake && !braking { clip = "plant"; elapsed = 0 }
    else if runBack && !returning { clip = "recover"; elapsed = 0 }
    braking = brake; returning = runBack; lastSpeed = speed
    elapsed += dt
    let duration:Float = clip == "plant" ? 0.38 : 0.72
    guard elapsed < duration else { return CapturedOffset() }
    var pose = Self.sample(clip,seconds:elapsed)
    let weight = min(1,(duration-elapsed)/0.10)
    pose.left *= weight; pose.right *= weight; pose.pelvis *= weight
    return pose
  }
}

/// A measured left-foot-to-left-foot cycle expressed in the runner's heading.
struct RunningStride {
  let hand, elbow, freeHand, freeElbow, trunk: CourtPoint3D

  private static let samples: [Self] = {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    guard let url = bundle.url(forResource:"running-stride",withExtension:"csv"),
      let csv = try? String(contentsOf:url,encoding:.utf8) else { return [] }
    return csv.split(separator:"\n").dropFirst().compactMap { row in
      let values = row.split(separator:",").compactMap { Float($0) }
      guard values.count == 15 else { return nil }
      func vector(_ i: Int) -> CourtPoint3D { [values[i],values[i+1],values[i+2]] }
      return Self(hand:vector(0),elbow:vector(3),freeHand:vector(6),freeElbow:vector(9),trunk:vector(12))
    }
  }()

  static func sample(phase: Float) -> Self? {
    guard !samples.isEmpty else { return nil }
    let position = phase*Float(samples.count), index = Int(position)
    let a = samples[index % samples.count], b = samples[(index+1) % samples.count]
    let t = position-Float(index)
    func blend(_ u: CourtPoint3D, _ v: CourtPoint3D) -> CourtPoint3D { u+(v-u)*t }
    return Self(hand:blend(a.hand,b.hand),elbow:blend(a.elbow,b.elbow),freeHand:blend(a.freeHand,b.freeHand),
                freeElbow:blend(a.freeElbow,b.freeElbow),trunk:blend(a.trunk,b.trunk))
  }
}
