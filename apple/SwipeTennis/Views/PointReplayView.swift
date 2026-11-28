import SwiftUI

struct ReplayReview: Identifiable {
  let id = UUID()
  let clip: PointReplay
  let surface: CourtSurface
  let side: Int
  let venue: TennisVenue?
  let winner: Int
  let broadcast: PointBroadcast
  let automatic: Bool
  let stadium: CourtReplayView?
  init(clip: PointReplay, game: PracticeEngine, side: Int = 0,
       automatic: Bool = false, stadium: CourtReplayView? = nil) {
    self.stadium = stadium
    winner = game.coach.records.last?.winner ?? game.scoring.winner ?? clip.strikes.last?.hitter ?? 0
    var shot = clip.winningShot(for:winner)
    let hit = clip.strikes.last
    let localWinner = automatic && side == winner && hit?.hitter == winner && hit?.fault == false
    broadcast = PointBroadcast(shot, celebration: localWinner ? game.pointResolution?.celebration : nil)
    if game.phase == .finished && !automatic { shot.appendHandshake() }
    self.clip = shot
    surface = game.settings.surface
    venue = game.settings.matchVenue
    self.side = side
    self.automatic = automatic
  }
}

struct PointReplayView: View {
  let close: () -> Void
  @Environment(\.scenePhase) private var phase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let review: ReplayReview
  @State private var angle = ReplayAngle.you
  @State private var offset: Double
  @State private var anchor: TimeInterval?
  @State private var resumeAfterScrub = false
  @State private var playbackID = 0
  @State private var decision = false
  @State private var looping = false
  @State private var ready = false
  @State private var highlight: Image?

  init(review: ReplayReview, close: @escaping () -> Void) {
    self.close = close
    self.review = review
    _offset = State(initialValue: 0)
  }
  private var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }
  private var length: Double { review.automatic ? review.broadcast.duration : review.clip.duration }
  private var cursor: Double {
    let elapsed = offset + (anchor.map { max(0, clock - $0) * (review.automatic ? 1 : PointReplay.speed) } ?? 0)
    if looping, let window = review.clip.contactWindow { return PointReplay.loopTime(elapsed,in:window) }
    return min(length,elapsed)
  }
  private func pause() { offset = cursor; anchor = nil }
  private func play() {
    if offset >= length { offset = 0 }
    playbackID += 1; anchor = clock
  }
  private func seek(_ value: Double) {
    let playing = anchor != nil
    offset = value; anchor = playing ? clock : nil; playbackID += 1
  }
  private func inspect(_ time: Double) {
    pause()
    looping = false
    seek(time)
  }
  private func timeText(_ time: Double) -> String {
    String(format: "%d:%04.1f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      TimelineView(.animation(minimumInterval: 1.0 / 60, paused: anchor == nil)) { _ in
        let elapsed = cursor
        let reacting = review.automatic && elapsed < review.broadcast.reactionDuration
        let time = review.automatic ? review.broadcast.sourceTime(at:elapsed) : elapsed
        ReplayCourt(replay: review.clip, surface: review.surface, venue:review.venue, localSide:review.side, angle: review.side == 1 && angle != .neutral ? (angle == .you ? .opponent : .you) : angle, seconds: time,
          playing: anchor != nil, playbackID: playbackID, reduceMotion: reduceMotion, automatic:review.automatic, reactionTime:reacting ? elapsed : nil, celebration:review.broadcast.celebration, winner:review.winner, liveStadium:review.stadium) {
            ready = true
            if (review.automatic || !reduceMotion) && phase == .active { play() }
          }
          .overlay { if !ready { ProgressView().tint(.white).padding(14).background(.black.opacity(0.52),in:Circle()).accessibilityLabel("Preparing replay") } }
          .accessibilityLabel(reacting ? (review.winner == review.side ? "You celebrate on court" : "Opponent celebrates on court") : "\(angle.rawValue) camera")
          .onChange(of: elapsed >= length) { _, ended in if ended { pause(); if review.automatic { close() } } }
      }
      if !review.automatic {
        VStack(spacing: 10) {
          HStack(spacing: 4) {
            ForEach(ReplayAngle.allCases, id: \.self) { view in
              Button { angle = view } label: {
                Text(view.rawValue).font(.subheadline.weight(.semibold))
                  .frame(maxWidth: .infinity, minHeight: 44)
                  .foregroundStyle(view == angle ? Color.white : Color.primary)
                  .background(view == angle ? Color(red: 0.10, green: 0.38, blue: 0.29) : .clear, in: Capsule())
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityAddTraits(view == angle ? .isSelected : [])
              .accessibilityIdentifier("replayCamera\(view.rawValue)")
            }
          }
          .padding(3).background(.quaternary, in: Capsule())
          TimelineView(.animation(minimumInterval: 0.1, paused: anchor == nil)) { _ in
            let time = cursor
            VStack(spacing: 10) {
              HStack(spacing: 12) {
                Button {
                  if anchor != nil { pause() } else { play() }
                } label: {
                  Image(systemName: anchor != nil ? "pause.fill" : time >= review.clip.duration ? "arrow.counterclockwise" : "play.fill")
                    .frame(width: 44,height: 44)
                }.accessibilityLabel(anchor != nil ? "Pause replay" : "Play replay")
                  .accessibilityIdentifier("replayPlay")
                if let window = review.clip.contactWindow {
                  Button {
                    if looping { let here = cursor; looping = false; seek(here) }
                    else { looping = true; seek(window.lowerBound); play() }
                  } label: {
                    Image(systemName:"repeat.1").frame(minWidth:34,minHeight:44)
                  }.foregroundStyle(looping ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(looping ? "Stop looping contact" : "Loop racket contact")
                    .accessibilityAddTraits(looping ? .isSelected : [])
                    .accessibilityIdentifier("loopContact")
                }
                Slider(value: Binding(get: { time }, set: { looping = false; seek($0) }), in: 0...max(PointReplay.tick,review.clip.duration)) { editing in
                  if editing { resumeAfterScrub = anchor != nil; pause() }
                  else if resumeAfterScrub { resumeAfterScrub = false; play() }
                }.accessibilityLabel("Point timeline").accessibilityValue(timeText(time))
                Text("0.5×").font(.subheadline.bold().monospacedDigit())
              }
              HStack {
                Text(timeText(time)).accessibilityIdentifier("replayTime")
                Spacer()
                if let contact = review.clip.strikes.last {
                  Button("Contact", systemImage:"scope") { inspect(contact.time) }
                    .accessibilityLabel("Freeze at racket contact").accessibilityIdentifier("freezeContact")
                }
                if let bounce = review.clip.lastShotBounceTime {
                  Button("Bounce", systemImage:"smallcircle.filled.circle") { inspect(bounce) }
                    .accessibilityLabel("Freeze at ball bounce").accessibilityIdentifier("freezeBounce")
                }
                Spacer()
                Text(timeText(review.clip.duration))
              }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
          }
        }.disabled(!ready).padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
      }
    }
    .frame(maxWidth:.infinity,maxHeight:.infinity)
    .contentShape(Rectangle())
    .accessibilityAddTraits(.isModal)
    .sheet(isPresented:$decision) {
      if let moment = review.clip.decisions[review.side] {
        NavigationStack {
          DecisionReviewView(moment:moment)
            .safeAreaInset(edge:.bottom) {
              if let height = review.clip.heights[review.side] { Text(height.label + " · " + height.cue).font(.subheadline).padding() }
            }
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { decision = false } } }
        }
      }
    }
    .task {
      guard !review.automatic else { return }
      let renderer = ImageRenderer(content: RallyHighlight(review:review))
      renderer.scale = 2
      if let graphic = renderer.uiImage { highlight = Image(uiImage:graphic) }
    }
    .onDisappear { pause() }
    .onChange(of: phase) { _, phase in
      if phase != .active { pause() }
      else if review.automatic && ready { play() }
    }
  }
  private var header: some View {
    HStack(spacing:12) {
      if review.automatic && ready {
        TimelineView(.animation(minimumInterval:0.1,paused:anchor == nil)) { _ in
          Text(cursor < review.broadcast.reactionDuration ? "Courtside" : "Player view")
            .font(.subheadline).accessibilityIdentifier("playingHighlight")
        }
      } else if let highlight {
        ShareLink(item:highlight,preview:SharePreview("SwipeTennis point",image:highlight)) {
          Label("Share highlight",systemImage:"square.and.arrow.up").labelStyle(.iconOnly)
        }
      }
      Spacer()
      Text(review.automatic ? "Point highlight" : "Point-ending shot").font(.headline)
      Spacer()
      if !review.automatic, review.clip.decisions[review.side] != nil {
        Button { pause(); decision = true } label: { Image(systemName:"scope") }
          .accessibilityLabel("Replay the decision")
      }
      Button(review.automatic ? "Skip" : "Done",action:close).frame(minHeight:44)
    }.padding(.horizontal,16).background(.regularMaterial)
  }

}

private struct RallyHighlight: View {
  let review: ReplayReview
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      Text("SwipeTennis").font(.headline)
      Text("Point replay").font(.largeTitle.bold())
      Canvas { context,size in
        func position(_ ball: CourtPoint3D) -> CGPoint {
          let x = CGFloat(ball.x) / PracticeEngine.width
          let y = CGFloat(ball.z) / PracticeEngine.length
          return CGPoint(x:12 + (review.side == 0 ? x : 1-x)*(size.width-24),
                         y:18 + (review.side == 0 ? y : 1-y)*(size.height-36))
        }
        let court = CGRect(origin:.zero,size:size).insetBy(dx:12,dy:18)
        context.stroke(Path(court),with:.color(.white),lineWidth:2)
        var net = Path(); net.move(to:CGPoint(x:0,y:court.midY)); net.addLine(to:CGPoint(x:size.width,y:court.midY))
        context.stroke(net,with:.color(.white.opacity(0.7)),style:StrokeStyle(lineWidth:2,dash:[4,4]))
        var path = Path()
        let frames = review.clip.frames, strideSize = max(1, frames.count/500)
        for index in stride(from:0,to:frames.count,by:strideSize) {
          let p = position(frames[index].ball)
          if index == 0 { path.move(to:p) } else { path.addLine(to:p) }
        }
        context.stroke(path,with:.color(.yellow),lineWidth:2)
        for hit in review.clip.strikes {
          let p = position(hit.point)
          context.fill(Path(ellipseIn:CGRect(x:p.x-4,y:p.y-4,width:8,height:8)),with:.color(.white))
        }
      }.frame(height:350)
      Text("\(review.clip.strikes.count) contacts · \(review.surface.rawValue) court").font(.subheadline)
    }.padding(24).frame(width:300).background(Color(red:0.06,green:0.29,blue:0.22)).foregroundStyle(.white)
  }
}
