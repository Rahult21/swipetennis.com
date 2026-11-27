import AVKit
import SwiftUI

struct QuickStartFilm: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var phase
  @State private var player = AVPlayer(playerItem: Bundle.main.url(forResource: "QuickStart", withExtension: "mp4").map(AVPlayerItem.init(url:)))
  @State private var observer: Any?
  @State private var chapter = 0
  private let titles = ["Place your serve", "Move to the return", "Drive a deep forehand", "Play a shorter backhand"]
  private let cues = [
    "Drag on your half to move blue. Lift, then tap your half to serve.",
    "Swipe toward yellow to run. Reach it before the ball and your player returns automatically.",
    "Reach the ball on your racket side. Swipe farther toward the far court for a deeper return.",
    "Reach the ball on the opposite side. Use a shorter diagonal swipe to land closer to the net."
  ]
  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let layout = geometry.size.width > geometry.size.height ? AnyLayout(HStackLayout(spacing:16)) : AnyLayout(VStackLayout(spacing:12))
        layout {
          VideoPlayer(player:player).aspectRatio(720.0/848.0,contentMode:.fit)
            .accessibilityLabel(titles[chapter])
          VStack(alignment:.leading,spacing:12) {
            Text("Step \(chapter+1) of 4").font(.subheadline).foregroundStyle(.secondary)
            Text(titles[chapter]).font(.title2.bold())
            Text(cues[chapter]).fixedSize(horizontal:false,vertical:true)
            HStack {
              ForEach(0..<4) { step in Button {
                chapter = step; player.seek(to:CMTime(seconds:Double(step)*5,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero); player.play()
              } label: { Image(systemName: step == chapter ? "circle.inset.filled" : "circle").frame(width:32,height:44) }
                .accessibilityLabel(titles[step]) }
            }
          }.frame(maxWidth:.infinity,alignment:.leading)
        }.padding().frame(maxWidth:.infinity,maxHeight:.infinity)
      }.navigationTitle("Quick start").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("closeQuickStart") } }
    }
    .onAppear {
      observer = player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.15,preferredTimescale:600),queue:.main) { time in
        if time.seconds.isFinite { chapter = min(3,max(0,Int(time.seconds/5))) }
      }
      player.play()
    }.onDisappear { player.pause(); if let observer { player.removeTimeObserver(observer); self.observer = nil } }
    .onChange(of:phase) { _, state in if state != .active { player.pause() } }
  }
}
