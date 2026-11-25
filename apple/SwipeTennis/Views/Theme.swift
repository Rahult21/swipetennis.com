import SwiftUI

enum TennisTheme {
  static let ink = Color(uiColor: .label)
  static let green = Color(red: 0.15, green: 0.31, blue: 0.23)
  static let cream = Color(uiColor: .systemGroupedBackground)
  static let lime = Color(red: 0.85, green: 0.91, blue: 0.48)
  static let muted = Color(uiColor: .secondaryLabel)
  static let sage = Color(uiColor: .tertiarySystemFill)
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.43, green: 0.85, blue: 0.62, alpha: 1)
      : UIColor(red: 0.12, green: 0.43, blue: 0.28, alpha: 1)
  })
}
struct Eyebrow: View {
  var text: String
  var body: some View {
    Text(text).font(.subheadline.weight(.semibold))
      .foregroundStyle(TennisTheme.muted)
  }
}
struct CourtDrawing: View {
  var path: [CourtPoint] = []
  var landings: [CourtPoint] = []
  var progress: Double = 1
  var body: some View {
    Canvas { context, size in
      func pt(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x / 100 * size.width, y: y / 160 * size.height)
      }
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(TennisTheme.green))
      let rect = CGRect(
        x: size.width * 0.04, y: size.height * 0.05, width: size.width * 0.92,
        height: size.height * 0.9)
      context.fill(Path(rect), with: .color(Color(red: 0.37, green: 0.51, blue: 0.39)))
      for coordinates in [
        [4.0, 8, 96, 8], [4, 152, 96, 152], [4, 8, 4, 152], [96, 8, 96, 152], [12, 8, 12, 152],
        [88, 8, 88, 152], [12, 45, 88, 45], [12, 115, 88, 115], [50, 45, 50, 115],
      ] {
        var line = Path()
        line.move(to: pt(coordinates[0], coordinates[1]))
        line.addLine(to: pt(coordinates[2], coordinates[3]))
        context.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
      }
      var net = Path()
      net.move(to: pt(0, 80))
      net.addLine(to: pt(100, 80))
      context.stroke(net, with: .color(.white), lineWidth: 3)
      let shown = Array(path.prefix(max(0, Int(Double(path.count) * progress))))
      if let first = shown.first {
        var trace = Path()
        trace.move(to: pt(first.x, first.y))
        for p in shown.dropFirst() { trace.addLine(to: pt(p.x, p.y)) }
        context.stroke(
          trace, with: .color(TennisTheme.lime),
          style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        if let end = shown.last {
          let p = pt(end.x, end.y)
          context.fill(
            Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
            with: .color(TennisTheme.lime))
        }
      }
      for landing in landings {
        let p = pt(landing.x, landing.y)
        context.stroke(
          Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)),
          with: .color(TennisTheme.lime), lineWidth: 2)
      }
    }.clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel(
      "Tennis court with \(landings.count) recorded bounces")
  }
}
