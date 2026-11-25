import SwiftUI

enum GestureMark: Equatable {
  case swipe(Double, Double)
  case tap
  case split
  case ready
  case watch
  case circle

  static func shot(_ kind: ShotKind, lateral: Double = 1) -> GestureMark {
    switch kind {
    case .cross: return .swipe(lateral, -1)
    case .line: return .swipe(0, -1)
    case .angle: return .swipe(lateral, 0)
    case .lob: return .swipe(0, 1)
    case .drop: return .circle
    case .slice: return .swipe(lateral == 0 ? 1 : lateral, 1)
    }
  }
}

/// Gesture-first artwork used by the compact live coach.
struct GestureArtwork: View {
  let mark: GestureMark
  var tint: Color = TennisTheme.lime
  var handColor: Color = .white
  var targetRing = false

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let ends = endpoints(size)
      ZStack {
        Canvas { context, _ in
          switch mark {
          case .circle:
            let radius = min(size.width, size.height) * 0.32
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
              width: radius * 2, height: radius * 2)), with: .color(tint),
              style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 3]))
          case .swipe:
            var path = Path()
            path.move(to: ends.0)
            path.addLine(to: ends.1)
            context.stroke(path, with: .color(tint.opacity(0.85)),
              style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 4]))
            let dx = ends.1.x - ends.0.x, dy = ends.1.y - ends.0.y
            let length = max(1, hypot(dx, dy))
            var arrow = Path()
            arrow.move(to: CGPoint(x: ends.1.x - dx / length * 8 - dy / length * 5,
              y: ends.1.y - dy / length * 8 + dx / length * 5))
            arrow.addLine(to: ends.1)
            arrow.addLine(to: CGPoint(x: ends.1.x - dx / length * 8 + dy / length * 5,
              y: ends.1.y - dy / length * 8 - dx / length * 5))
            context.stroke(arrow, with: .color(tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            if targetRing {
              context.stroke(Path(ellipseIn: CGRect(x: ends.1.x - 9, y: ends.1.y - 6,
                width: 18, height: 12)), with: .color(tint), lineWidth: 1.5)
            }
          case .tap, .split:
            for radius in [8.0, 14.0] {
              context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius - 6,
                width: radius * 2, height: radius * 2)), with: .color(tint.opacity(radius == 8 ? 0.9 : 0.35)), lineWidth: 1.5)
            }
          case .ready, .watch: break
          }
        }
        if mark == .ready || mark == .watch {
          Image(systemName: mark == .ready ? "checkmark.circle.fill" : "eye")
            .font(.system(size: 28, weight: .light)).foregroundStyle(tint).position(center)
        } else {
          Image(systemName: "hand.point.up.fill")
            .font(.system(size: 23)).foregroundStyle(handColor.opacity(0.85))
            .position(x: mark == .tap || mark == .split ? center.x + 3 : ends.0.x + 3,
              y: mark == .tap || mark == .split ? center.y + 9 : ends.0.y + 12)
        }
      }
    }.accessibilityHidden(true)
  }

  private func endpoints(_ size: CGSize) -> (CGPoint, CGPoint) {
    if mark == .circle {
      let point = CGPoint(x: size.width / 2 + min(size.width, size.height) * 0.32, y: size.height / 2)
      return (point, point)
    }
    guard case let .swipe(x, y) = mark else { return (.zero, .zero) }
    let length = max(0.01, hypot(x, y))
    let distance = min(size.width * 0.29, size.height * 0.32)
    let center = CGPoint(x: size.width / 2, y: size.height * 0.39)
    let dx = x / length * distance, dy = y / length * distance
    return (CGPoint(x: center.x - dx, y: center.y - dy),
      CGPoint(x: center.x + dx, y: center.y + dy))
  }
}
