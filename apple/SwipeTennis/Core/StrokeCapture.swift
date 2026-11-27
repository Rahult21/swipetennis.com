import Foundation
import simd

/// Each clip is sampled at 50 Hz, from 0.82 s before its contact landmark.
/// Axes are anatomical right, up, and courtward on both ends of the court.
struct CapturedStroke {
  enum Kind: String { case serve, smash, forehand, backhand, volley }
  var hipYaw, chestYaw, tilt: Float
  var hand, elbow, support, supportElbow, rearFoot: CourtPoint3D

  private static let tracks: [Kind:[Self]] = {
    #if SWIFT_PACKAGE
    let bundle = Bundle.module
    #else
    let bundle = Bundle.main
    #endif
    guard let url = bundle.url(forResource:"court-strokes",withExtension:"csv"),
          let csv = try? String(contentsOf:url,encoding:.utf8) else { return [:] }
    var tracks: [Kind:[Self]] = [:]
    for line in csv.split(separator:"\n").dropFirst() {
      let fields = line.split(separator:",")
      guard let first = fields.first, let kind = Kind(rawValue:String(first)) else { continue }
      let v = fields.dropFirst(2).compactMap { Float($0) }
      guard v.count == 18 else { continue }
      func point(_ i: Int) -> CourtPoint3D { [v[i],v[i+1],v[i+2]] }
      tracks[kind,default:[]].append(Self(hipYaw:v[0],chestYaw:v[1],tilt:v[2],hand:point(3),elbow:point(6),
                                        support:point(9),supportElbow:point(12),rearFoot:point(15)))
    }
    return tracks
  }()

  static func sample(_ kind: Kind, at t: Float) -> Self? {
    guard let track = tracks[kind], !track.isEmpty else { return nil }
    let frame = max(0,min(Float(track.count-1),(t+0.82)*50))
    let i = Int(frame), a = track[i], b = track[min(i+1,track.count-1)], k = frame-Float(i)
    func angle(_ a: Float,_ b: Float) -> Float { a+atan2(sin(b-a),cos(b-a))*k }
    return Self(hipYaw:angle(a.hipYaw,b.hipYaw),chestYaw:angle(a.chestYaw,b.chestYaw),tilt:a.tilt+(b.tilt-a.tilt)*k,
                hand:a.hand+(b.hand-a.hand)*k,elbow:a.elbow+(b.elbow-a.elbow)*k,
                support:a.support+(b.support-a.support)*k,supportElbow:a.supportElbow+(b.supportElbow-a.supportElbow)*k,
                rearFoot:a.rearFoot+(b.rearFoot-a.rearFoot)*k)
  }
}
