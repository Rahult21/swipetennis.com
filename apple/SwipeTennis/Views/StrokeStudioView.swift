import SwiftUI

struct StrokeStudioView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var repeatStroke = false
  @State private var ready = false
  @State private var fittedMesh = false
  @State private var selectedPhase: String?
  @State private var renderedPhase: String?
  @State private var frozenImage: UIImage?
  private var phaseKey: String? { selectedPhase.map { stroke.rawValue + "-" + angle.rawValue + "-" + $0 } }
  @State private var stroke = StudioStroke.serve
  @State private var angle = LockerAngle.back
  @State private var clip: StrokeStudioClip?
  @State private var offset = 0.0
  @State private var anchor: TimeInterval?

  private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
  private func cursor(_ clip: StrokeStudioClip) -> Double {
    let elapsed = offset + (anchor.map { max(0,now-$0)*PointReplay.speed } ?? 0)
    if repeatStroke && anchor != nil { return PointReplay.loopTime(elapsed,in:0...clip.duration) }
    return min(clip.duration,elapsed)
  }
  private func freeze(_ time: Double) { offset = time; anchor = nil }
  private func start(_ clip: StrokeStudioClip) {
    if offset >= clip.duration-0.001 { offset = 0 }
    selectedPhase = nil; renderedPhase = nil; anchor = now
  }

  var body: some View {
    ScrollView {
      VStack(alignment:.leading,spacing:16) {
        Picker("Stroke",selection:$stroke) {
          ForEach(StudioStroke.allCases,id:\.self) { Text($0.rawValue) }
        }.pickerStyle(.segmented)
        if let clip {
          TimelineView(.animation(minimumInterval:1.0/60,paused:anchor == nil)) { _ in
            let t = cursor(clip)
            VStack(spacing:12) {
              StudioCourt(clip:clip,time:t,azimuth:angle.radians,serve:stroke == .serve,
                          phase:ready ? phaseKey : nil,displayed:{ key, image in
                            if phaseKey == key { frozenImage = image; renderedPhase = key }
                          }) { fitted in
                fittedMesh = fitted; ready = true
                if !reduceMotion { start(clip) }
              }
                .aspectRatio(1.06,contentMode:.fit)
                .overlay {
                  if let frozenImage, let phaseKey, phaseKey == renderedPhase {
                    Image(uiImage:frozenImage).resizable().scaledToFit()
                      .clipShape(RoundedRectangle(cornerRadius:18)).allowsHitTesting(false).accessibilityHidden(true)
                  }
                }
                .accessibilityLabel("\(stroke.rawValue) in slow motion, \(angle.rawValue) view")
                .accessibilityIdentifier("motionStudioCourt")
                .accessibilityValue(renderedPhase ?? (ready ? (fittedMesh ? "Ready" : "Simplified player") : "Loading"))
              HStack {
                Button { if anchor == nil { start(clip) } else { freeze(t) } } label: {
                  Image(systemName:anchor == nil ? "play.fill" : "pause.fill").frame(width:38,height:42)
                }.accessibilityLabel(anchor == nil ? "Play stroke" : "Pause stroke")
                Slider(value:Binding(get:{ t },set:{ selectedPhase = nil; renderedPhase = nil; freeze($0) }),in:0...clip.duration)
                  .accessibilityLabel("Stroke timeline")
                Button {
                  let previous = cursor(clip)
                  repeatStroke.toggle()
                  if repeatStroke { start(clip) }
                  else { offset = previous; if anchor != nil { anchor = now } }
                } label: {
                  Image(systemName:"repeat.1").frame(width:36,height:42)
                }.foregroundStyle(repeatStroke ? Color.accentColor : Color.secondary)
                  .accessibilityLabel(repeatStroke ? "Stop repeating stroke" : "Repeat stroke")
                  .accessibilityIdentifier("studioRepeat")
                  .accessibilityAddTraits(repeatStroke ? .isSelected : [])
                Text("0.5×").font(.callout.monospacedDigit())
              }
              HStack {
                phaseButton("Load","figure.tennis") { freeze(max(0,clip.contactTime-0.26)) }
                phaseButton("Contact","scope") { freeze(clip.contactTime) }
                phaseButton("Finish","figure.cooldown") { freeze(min(clip.duration,clip.contactTime+0.21)) }
              }
            }.onChange(of:t >= clip.duration) { _, ended in if ended { freeze(clip.duration) } }
          }
          Picker("Camera",selection:$angle) {
            ForEach(LockerAngle.allCases,id:\.self) { Text($0.rawValue) }
          }.pickerStyle(.segmented)
          Text(stroke.cue).font(.subheadline).foregroundStyle(.secondary)
        }
      }.padding().frame(maxWidth:600).frame(maxWidth:.infinity)
    }
    .navigationTitle("Stroke studio").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let frozenImage, let phaseKey, phaseKey == renderedPhase {
        let image = Image(uiImage:frozenImage)
        ShareLink(item:image,preview:SharePreview(stroke.rawValue,image:image)) {
          Label("Share pose",systemImage:"square.and.arrow.up")
        }
      }
    }
    .onChange(of:stroke,initial:true) { _, choice in
      clip = StrokeStudioClip(choice)
      if let clip {
        selectedPhase = nil; renderedPhase = nil
        freeze(reduceMotion ? clip.contactTime : 0)
        if ready && !reduceMotion { start(clip) }
      }
    }
    .onChange(of:scenePhase) { _,phase in if phase != .active, let clip { freeze(cursor(clip)) } }
  }

  private func phaseButton(_ text: String, _ symbol: String, action:@escaping () -> Void) -> some View {
    Button {
      selectedPhase = text
      action()
    } label: {
      Label(text,systemImage:symbol).font(.caption.weight(.semibold)).frame(maxWidth:.infinity,minHeight:30)
    }.buttonStyle(.bordered).tint(selectedPhase == text ? .indigo : .accentColor)
      .accessibilityAddTraits(selectedPhase == text ? .isSelected : [])
  }
}

private struct StudioCourt: UIViewRepresentable {
  let clip: StrokeStudioClip
  let time: Double, azimuth: Float, serve: Bool
  let phase: String?
  let displayed: (String,UIImage) -> Void
  let ready: (Bool) -> Void
  final class Coordinator { var phase: String? }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> CourtReplayView {
    let view = CourtReplayView(surface:.hard,venue:.harbor)
    view.layer.cornerRadius = 18; view.clipsToBounds = true
    view.whenRendering { [weak view] in ready(view?.hasFittedPlayers == true) }
    return view
  }
  func updateUIView(_ view: CourtReplayView, context: Context) {
    guard let frame = clip.frame(time), let atHit = clip.frame(clip.contactTime) else { return }
    let origin = (atHit.near[.leftHip]+atHit.near[.rightHip])*0.5
    view.drawStudio(frame,origin:origin,azimuth:azimuth,serve:serve)
    if context.coordinator.phase != phase {
      context.coordinator.phase = phase
      if let phase { view.whenFrameIsReady { displayed(phase,$0) } }
    }
  }
  static func dismantleUIView(_ view: CourtReplayView, coordinator: Coordinator) {
    view.finishReview()
    view.scene.anchors.removeAll()
  }

}
