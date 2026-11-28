import SwiftUI

/// The court continues beneath this control, with the touch target inside the safe area.
struct CourtControlIcon: View {
  let symbol: String
  var body: some View {
    Image(systemName: symbol).font(.system(size: 16, weight: .bold))
      .foregroundStyle(.white).frame(width: 32, height: 32)
      .background(.black.opacity(0.38), in: Circle())
      .overlay(Circle().strokeBorder(.white.opacity(0.50), lineWidth: 1))
      .frame(width: 44, height: 44).contentShape(Rectangle())
  }
}

struct PausedCourtCoach: View {
  let game: PracticeEngine
  let miss: CoachMiss?
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        GestureArtwork(mark: artwork.mark, tint: artwork.color, targetRing: artwork.ring)
          .frame(width: 48, height: 40).accessibilityHidden(true)
        VStack(alignment: .leading) {
          Text(game.instruction.title).font(.subheadline.bold())
          Text(game.instruction.detail).font(.caption)
        }
        Spacer()
      }
      Text("Coachability \(game.coach.pointScore > 0 ? "+" : "")\(game.coach.pointScore) CP").font(.caption.bold())
      if let miss { Text(miss.correction).font(.caption) }
      if let serve = game.displayedServeGauges {
        Text("\(game.name(serve.server)) serving · Speed \(serve.profile.speed.label) · Spin \(serve.profile.spin.label)")
          .font(.caption)
      }
      HStack(spacing: 20) {
        ForEach(0..<2) { side in
          let energy = game.players[side].energyLevel
          VStack(alignment: .leading, spacing: 4) {
            Text("\(game.name(side)) · \(Int(energy*100))% energy").font(.caption2)
            ProgressView(value: energy).tint(energy < 0.35 ? .orange : .mint)
          }
        }
      }
    }.padding(12).foregroundStyle(.white)
      .background(Color(red: 0.08, green: 0.19, blue: 0.17), in: RoundedRectangle(cornerRadius: 14))
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
    case .hitServe: return (.swipe(0, -1), .cyan, true)
    }
  }
}
