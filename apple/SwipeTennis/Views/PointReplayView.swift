import SwiftUI

struct ReplayReview: Identifiable {
  let id = UUID()
  let clip: PointReplay
  let surface: CourtSurface
}

struct PointReplayView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var phase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let review: ReplayReview
  @State private var angle = ReplayAngle.you
  @State private var offset: Double
  @State private var anchor: TimeInterval?
  @State private var resumeAfterScrub = false
  @State private var playbackID = 0
  @State private var ready = false

  init(review: ReplayReview) {
    self.review = review
    _offset = State(initialValue: review.clip.opening)
  }
  private var clock: TimeInterval { ProcessInfo.processInfo.systemUptime }
  private var cursor: Double {
    min(review.clip.duration, offset + (anchor.map { max(0, clock - $0) * PointReplay.speed } ?? 0))
  }
  private func pause() { offset = cursor; anchor = nil }
  private func play() {
    if offset >= review.clip.duration { offset = 0 }
    playbackID += 1; anchor = clock
  }
  private func seek(_ value: Double) {
    let playing = anchor != nil
    offset = value; anchor = playing ? clock : nil; playbackID += 1
  }
  private func timeText(_ time: Double) -> String {
    String(format: "%d:%04.1f", Int(time) / 60, time.truncatingRemainder(dividingBy: 60))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: anchor == nil)) { _ in
          let time = cursor
          ReplayCourt(replay: review.clip, surface: review.surface, angle: angle, seconds: time,
            playing: anchor != nil, playbackID: playbackID, reduceMotion: reduceMotion) {
              ready = true
              if !reduceMotion && phase == .active { play() }
            }
            .overlay { if !ready { ProgressView().accessibilityLabel("Preparing replay") } }
            .accessibilityLabel("\(angle.rawValue) camera")
            .onChange(of: time >= review.clip.duration) { _, ended in if ended { pause() } }
        }
        VStack(spacing: 10) {
          Picker("Camera", selection: $angle) {
            ForEach(ReplayAngle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("replayCamera")
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
                Slider(value: Binding(get: { time }, set: seek), in: 0...max(PointReplay.tick,review.clip.duration)) { editing in
                  if editing { resumeAfterScrub = anchor != nil; pause() }
                  else if resumeAfterScrub { resumeAfterScrub = false; play() }
                }.accessibilityLabel("Point timeline").accessibilityValue(timeText(time))
                Text("0.5×").font(.subheadline.bold().monospacedDigit())
              }
              HStack {
                Text(timeText(time)).accessibilityIdentifier("replayTime")
                Spacer()
                Text(timeText(review.clip.duration))
              }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
          }
        }.disabled(!ready).padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
      }
      .navigationTitle("Point replay").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .onDisappear { pause() }
    .onChange(of: phase) { _, phase in if phase != .active { pause() } }
  }
}
