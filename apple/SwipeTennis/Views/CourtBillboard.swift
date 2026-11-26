import SwiftUI

/// One compact courtside strip contains coaching, the score, and match controls.
struct CourtBillboard: View {
  @Environment(\.verticalSizeClass) private var heightClass
  let game: PracticeEngine
  let paused: Bool
  var miss: CoachMiss? = nil
  let onLeave: () -> Void
  let onHelp: () -> Void
  let onPause: () -> Void

  var body: some View {
    let wide = heightClass == .compact
    let header = wide ? AnyLayout(VStackLayout(spacing:3)) : AnyLayout(HStackLayout(spacing:0))
    let panel = wide ? AnyLayout(VStackLayout(spacing:4)) : AnyLayout(HStackLayout(spacing:12))
    return VStack(spacing: wide ? 8 : 0) {
      header {
        VStack(alignment: .leading, spacing: 3) {
          if let miss {
            Text(miss.label).tracking(0.6).font(.system(size: 8, weight: .bold))
              .foregroundStyle(Color(red: 1, green: 0.73, blue: 0.35))
            Text(miss.correction).font(.system(size: 10, weight: .medium))
              .lineLimit(2).fixedSize(horizontal: false, vertical: true)
          } else {
            Text("Courtside coach").font(.caption2.weight(.semibold))
            Text(phaseLabel).font(.caption2).monospacedDigit()
              .foregroundStyle(.white.opacity(0.6))
          }
        }.padding(.leading, 12)
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("coachMissFeedback")
        if !wide { Spacer(minLength:0) }
        HStack(spacing:0) {
        control("xmark", label: "Leave practice", action: onLeave)
        control("questionmark.circle", label: "Illustrated court guide", action: onHelp)
          .accessibilityIdentifier("courtGuide")
        control(paused ? "play.fill" : "pause.fill",
          label: paused ? "Resume practice" : "Pause practice", action: onPause)
        }
      }.frame(height: wide ? 91 : 44)
      panel {
        Group {
          if game.needsSimulation && !paused {
            GestureArtwork(mark: artwork.mark, tint: artwork.color, targetRing: artwork.ring)
          } else {
            Image(systemName: paused ? "pause.circle" : game.phase == .finished ? "trophy" : "tennisball")
              .font(.system(size: 30, weight: .light)).foregroundStyle(TennisTheme.lime)
          }
        }.frame(width: 78, height: 47)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(paused ? "Paused" : "\(game.instruction.title). \(game.instruction.detail)")
          .accessibilityIdentifier("courtsideBillboard")
        if !wide { Rectangle().fill(.white.opacity(0.15)).frame(width:1,height:44) }
        score
      }.frame(height: wide ? 119 : 56).padding(.horizontal, 12).padding(.bottom, 6)
    }.frame(maxHeight:wide ? .infinity : nil).foregroundStyle(.white)
      .background(Color(red: 0.055, green: 0.105, blue: 0.09))
  }

  private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.body)
    }.buttonStyle(.bordered).buttonBorderShape(.circle).tint(.white)
      .frame(minWidth: 44, minHeight: 44).accessibilityLabel(label)
  }

  private var score: some View {
    VStack(spacing: 1) {
      HStack(spacing: 8) {
        Text("COACH \(game.coach.pointScore >= 0 ? "+" : "")\(game.coach.pointScore)")
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("ENERGY").frame(width: 34)
        if game.scoring.format == .tennis { Text("G").frame(width: 24) }
        Text("PTS").frame(width: 36)
      }.font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
      ForEach(0..<2) { side in
        HStack(spacing: 8) {
          Image(systemName: game.scoring.server == side ? "tennisball.fill" : "circle")
            .font(.system(size: 8)).foregroundStyle(game.scoring.server == side ? TennisTheme.lime : .white.opacity(0.3))
            .accessibilityLabel(game.scoring.server == side ? "Serving" : "Receiving")
          Text(game.name(side)).font(.system(size: 12, weight: .medium))
            .lineLimit(1).minimumScaleFactor(0.65).frame(maxWidth: .infinity, alignment: .leading)
          let energy = game.players[side].energyLevel
          ProgressView(value: energy).frame(width: 34)
            .tint(energy < 0.35 ? .orange : TennisTheme.lime)
            .accessibilityLabel("Energy").accessibilityValue("\(Int(energy * 100)) percent")
          if game.scoring.format == .tennis {
            Text("\(game.scoring.games[side])").font(.system(size: 14, weight: .medium)).frame(width: 24)
              .accessibilityLabel("\(game.scoring.games[side]) games")
          }
          Text(game.phase == .finished && game.scoring.format == .tennis ? "–" : game.scoring.pointLabel(side))
            .font(.system(size: 19, weight: .semibold, design: .rounded)).frame(width: 36)
        }.monospacedDigit().accessibilityElement(children: .combine)
      }
    }.accessibilityIdentifier("practiceScoreboard")
  }

  private var artwork: (mark: GestureMark, color: Color, ring: Bool) {
    switch game.coachCue {
    case .move(let direction, _): return (.swipe(direction.x, direction.y), .yellow, true)
    case .tapShot: return (.tap, .yellow, true)
    case .shot(let kind, let lateral): return (.shot(kind, lateral: lateral), TennisTheme.lime, false)
    case .split(let timed): return (.split, timed ? .mint : .white, false)
    case .ready: return (.ready, TennisTheme.lime, false)
    case .watch: return (.watch, .white.opacity(0.7), false)
    case .aimServe: return (.swipe(1, 0), .cyan, true)
    case .hitServe: return (.tap, .cyan, true)
    }
  }

  private var phaseLabel: String {
    if paused { return "PAUSED" }
    if game.isResolvingPoint {
      if game.phase == .serveFault { return "FAULT · SECOND SERVE" }
      return game.pointResolution?.impact.map { $0.isNet ? "NET" : "OUT" } ?? "POINT OVER"
    }
    if game.phase == .finished { return "MATCH COMPLETE" }
    guard game.phase == .serving, let serve = game.servePreparation else { return "RALLY \(game.rally)" }
    if serve.isTossing { return serve.number == 2 ? "SECOND SERVE · TOSS" : "FIRST SERVE · TOSS" }
    if serve.requested { return "SERVE SET" }
    if game.humanServing { return serve.number == 2 ? "SECOND SERVE · AIM" : "FIRST SERVE · AIM" }
    if serve.number == 2 { return "SECOND SERVE · STEP IN" }
    return "OPPONENT · \(max(1, Int(ceil(ServePreparation.opponentAimDuration - serve.elapsed))))"
  }
}
