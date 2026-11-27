import SwiftUI

struct StrokeStudioView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var orbit: Float = 0
  @State private var orbitBase: Float?
  @State private var repeatStroke = false
  @StateObject private var exporter = StrokeMovieExport()
  @State private var ready = false
  @State private var fittedMesh = false
  @State private var selectedPhase: String?
  @State private var renderedPhase: String?
  @State private var frozenImage: UIImage?
  private var phaseKey: String? { selectedPhase.map { stroke.rawValue + "-" + direction + "-" + $0 } }
  private var direction: String { abs(orbit) < 0.01 ? angle.rawValue : "Orbit " + String(Int(orbit*180 / .pi)) }
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
    GeometryReader { geometry in
      let landscape = geometry.size.width > geometry.size.height
      let width = min(geometry.size.width*0.48,max(130,geometry.size.height-66)*1.06)
      let layout = landscape ? AnyLayout(HStackLayout(alignment:.top,spacing:20))
                             : AnyLayout(VStackLayout(alignment:.leading,spacing:16))
      ScrollView {
        VStack(alignment:.leading,spacing:12) {
          Picker("Stroke",selection:$stroke) {
            ForEach(StudioStroke.allCases,id:\.self) { Text($0.rawValue) }
          }.pickerStyle(.segmented).disabled(exporter.busy)
          if let clip {
            layout {
              viewport(clip).frame(width:landscape ? width : nil)
              controls(clip).frame(maxWidth:.infinity,alignment:.leading)
            }
          }
        }.padding(.horizontal).padding(.vertical,8)
          .frame(maxWidth:landscape ? 1050 : 600).frame(maxWidth:.infinity)
      }
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
      exporter.clear()
      clip = StrokeStudioClip(choice)
      if let clip {
        selectedPhase = nil; renderedPhase = nil
        freeze(reduceMotion ? clip.contactTime : 0)
        if ready && !reduceMotion { start(clip) }
      }
    }
    .onDisappear { exporter.cancel() }
    .onChange(of:scenePhase) { _,phase in if phase != .active, let clip { exporter.cancel(); freeze(cursor(clip)) } }
  }

  private func viewport(_ clip: StrokeStudioClip) -> some View {
    StudioCourt(clip:clip,stroke:stroke,offset:offset,anchor:anchor,looping:repeatStroke,
                azimuth:angle.radians+orbit,exporter:exporter,phase:ready && orbitBase == nil ? phaseKey : nil,displayed:{ key, image in
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
      } else if !ready {
        RoundedRectangle(cornerRadius:18).fill(.background).overlay { ProgressView("Preparing court") }
      }
    }
    .contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance:8)
      .onChanged { drag in
        if orbitBase == nil { orbitBase = orbit; exporter.clear() }
        orbit = (orbitBase ?? 0) + Float(drag.translation.width)*0.012
      }.onEnded { _ in orbitBase = nil })
    .allowsHitTesting(!exporter.busy)
    .accessibilityLabel("\(stroke.rawValue) in slow motion, \(direction) view")
    .accessibilityHint("Drag left or right to rotate the camera")
    .accessibilityIdentifier("motionStudioCourt")
    .accessibilityValue(renderedPhase ?? (ready ? (fittedMesh ? "Ready" : "Simplified player") : "Loading"))
  }

  private func controls(_ clip: StrokeStudioClip) -> some View {
    VStack(alignment:.leading,spacing:12) {
      TimelineView(.animation(minimumInterval:0.10,paused:anchor == nil)) { _ in
        let t = cursor(clip)
        VStack(spacing:12) {
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
      .disabled(exporter.busy)
      Picker("Camera",selection:$angle) {
        ForEach(LockerAngle.allCases,id:\.self) { Text($0.rawValue) }
      }.pickerStyle(.segmented).disabled(exporter.busy).onChange(of:angle) { _,_ in orbit = 0; exporter.clear() }
      Text(stroke.cue).font(.subheadline).foregroundStyle(.secondary)
      if let fraction = exporter.fraction {
        HStack {
          ProgressView(value:fraction).accessibilityLabel("Exporting stroke")
          Button("Cancel",role:.cancel) { exporter.cancel() }
        }
      } else if let movie = exporter.movie {
        ShareLink(item:movie) { Label("Share slow-motion video",systemImage:"square.and.arrow.up") }
          .accessibilityIdentifier("shareStudioMovie")
      } else {
        Button {
          freeze(cursor(clip)); selectedPhase = nil; renderedPhase = nil
          exporter.export(clip:clip,stroke:stroke,azimuth:angle.radians+orbit)
        } label: { Label("Export 0.5× video",systemImage:"film") }
          .disabled(!ready).accessibilityIdentifier("exportStudioMovie")
      }
      if let message = exporter.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
    }
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
  let stroke: StudioStroke
  let offset: Double
  let anchor: TimeInterval?
  let looping: Bool
  let azimuth: Float
  let exporter: StrokeMovieExport
  let phase: String?
  let displayed: (String,UIImage) -> Void
  let ready: (Bool) -> Void

  @MainActor final class Coordinator {
    weak var view: CourtReplayView?
    private var link: CADisplayLink?
    private var clip: StrokeStudioClip?
    private var stroke: StudioStroke?
    private var origin = CourtPoint3D.zero
    private var start: TimeInterval?
    private var offset = 0.0, angle: Float = 0
    private var looping = false
    private var lastTime = -1.0, lastAngle: Float = .infinity
    var phase: String?
    var wasExporting = false
    #if targetEnvironment(simulator)
    // CoreSimulator can leave RealityKit's onscreen drawable stale while a
    // CADisplayLink keeps advancing the rig. Present completed Metal frames
    // in a UIKit layer and keep at most one readback outstanding.
    private let preview = UIImageView()
    private var readingFrame = false
    private var lastRead = -1.0
    private func presentSimulatorFrame(_ view: CourtReplayView) {
      let time = ProcessInfo.processInfo.systemUptime
      guard !readingFrame, time-lastRead >= 1.0/30 else { return }
      if preview.superview !== view {
        preview.frame = view.bounds
        preview.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        preview.isUserInteractionEnabled = false
        preview.isAccessibilityElement = false
        view.addSubview(preview)
      }
      readingFrame = true; lastRead = time
      view.snapshot(saveToHDR:false) { [weak self, weak view] image in
        Task { @MainActor in
          guard let self else { return }
          self.readingFrame = false
          guard let view, self.view === view, self.link != nil, let image else { return }
          self.preview.image = image
          self.preview.isHidden = false
        }
      }
    }
    #endif

    func configure(_ control: StudioCourt, view: CourtReplayView) {
      self.view = view
      if wasExporting { lastTime = -1; wasExporting = false }
      if stroke != control.stroke {
        clip = control.clip; stroke = control.stroke; lastTime = -1
        if let impact = control.clip.frame(control.clip.contactTime) {
          origin = (impact.near[.leftHip]+impact.near[.rightHip])*0.5
        }
      }
      start = control.anchor; offset = control.offset; angle = control.azimuth; looping = control.looping
      if start != nil && link == nil {
        let driver = CADisplayLink(target:self,selector:#selector(frame))
        driver.preferredFrameRateRange = .init(minimum:24,maximum:60,preferred:60)
        driver.add(to:.main,forMode:.common); link = driver
      } else if start == nil { stop() }
      frame()
    }

    @objc private func frame() {
      guard let view, let clip else { return }
      let elapsed = offset+(start.map { max(0,ProcessInfo.processInfo.systemUptime-$0)*PointReplay.speed } ?? 0)
      let t = looping && start != nil ? PointReplay.loopTime(elapsed,in:0...clip.duration) : min(clip.duration,elapsed)
      if abs(t-lastTime)<0.00001 && angle == lastAngle { return }
      if let sample = clip.frame(t), let stroke { view.drawStudio(sample,origin:origin,azimuth:angle,stroke:stroke) }
      #if targetEnvironment(simulator)
      if link != nil { presentSimulatorFrame(view) }
      #endif
      lastTime=t; lastAngle=angle
    }
    func stop() {
      link?.invalidate(); link = nil
      #if targetEnvironment(simulator)
      preview.isHidden = true
      #endif
    }
  }
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeUIView(context: Context) -> CourtReplayView {
    let view = CourtReplayView(surface:.hard,venue:.harbor)
    view.layer.cornerRadius = 18; view.clipsToBounds = true
    view.whenRendering { [weak view] in ready(view?.hasFittedPlayers == true) }
    return view
  }
  func updateUIView(_ view: CourtReplayView, context: Context) {
    exporter.court = view
    if exporter.busy { context.coordinator.stop(); context.coordinator.wasExporting = true; return }
    context.coordinator.configure(self,view:view)
    if context.coordinator.phase != phase {
      context.coordinator.phase = phase
      if let phase { view.whenFrameIsReady { displayed(phase,$0) } }
    }
  }
  static func dismantleUIView(_ view: CourtReplayView, coordinator: Coordinator) {
    coordinator.stop()
    view.finishReview()
    view.scene.anchors.removeAll()
  }

}
