import Foundation

enum QuickCircle {
  static func matches(_ points: [Vec], duration: Double) -> Bool {
    guard points.count >= 10, duration >= 0.08, duration <= 0.9,
      let first = points.first, let last = points.last else { return false }
    let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
    let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
    let width = maxX - minX, height = maxY - minY
    guard width >= 22, height >= 22, max(width, height) <= 220,
      width / height >= 0.5, width / height <= 2,
      first.distance(to: last) <= max(width, height) * 0.38 else { return false }
    let centre = Vec(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    var rotation = 0.0, path = 0.0
    for i in 1..<points.count {
      var turn = atan2(points[i].y - centre.y, points[i].x - centre.x)
        - atan2(points[i - 1].y - centre.y, points[i - 1].x - centre.x)
      if turn > .pi { turn -= 2 * .pi }
      if turn < -.pi { turn += 2 * .pi }
      rotation += turn
      path += points[i].distance(to: points[i - 1])
    }
    return abs(rotation) >= 1.65 * .pi && abs(rotation) <= 2.6 * .pi
      && path >= 2.4 * max(width, height) && path <= 4.5 * max(width, height)
  }
}

enum SlicePath {
  static func isNetPost(_ point: Vec) -> Bool {
    abs(point.y - PracticeEngine.net) <= 1.6
      && min(abs(point.x + 1.65), abs(point.x - PracticeEngine.width - 1.65)) <= 1.4
  }
  static func matches(from: Vec, to: Vec, side: Int) -> Bool {
    guard isNetPost(from) else { return false }
    let leftPost = from.x < PracticeEngine.width / 2
    let oppositeCorner = leftPost ? to.x >= PracticeEngine.width - 2.2 : to.x <= 2.2
    let baselineEnd = side == 0 ? to.y >= PracticeEngine.length - 3.2 : to.y <= 3.2
    return oppositeCorner && baselineEnd
  }
}

/// Randomize which chase fails in each group, while preserving the requested success ratio.
struct DropShotReturns {
  private var slot = 0
  private var missSlot = 0
  private var level: Difficulty?
  mutating func next(difficulty: Difficulty, random: () -> Double) -> Bool {
    let count = difficulty == .easy ? 3 : difficulty == .medium ? 4 : 5
    if level != difficulty { slot = 0; level = difficulty }
    if slot == 0 { missSlot = Int(clamp(random(), 0, 0.999999) * Double(count)) }
    let succeeds = slot != missSlot
    slot = (slot + 1) % count
    return succeeds
  }
}

extension ShotKind {
  var strokeStyle: TennisStrokeStyle {
    switch self {
    case .lob: return .lob
    case .drop: return .drop
    case .slice: return .slice
    default: return .groundstroke
    }
  }
}

extension PracticeEngine {
  func canDrawDrop(_ side: Int) -> Bool {
    guard let epoch = shotGestureEpoch(side) else { return false }
    return dropGestureEpoch[side] == epoch
  }
  mutating func selectTouchShot(_ kind: ShotKind, side: Int, epoch: Int?) {
    guard let epoch, epoch == shotGestureEpoch(side), canChooseShot(side),
      kind != .drop || canDrawDrop(side) else { return }
    choose(side, kind)
    dropGestureEpoch[side] = nil
  }
}
