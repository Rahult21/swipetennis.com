import SwiftUI

/// A frozen, player-relative court. All pins use the simulation's metre coordinates.
struct DecisionCourt: View {
  var side = 0
  let feet: Vec
  let opponent: Vec
  var recovery: Vec?
  var selection: Vec?
  var onPlace: ((Vec) -> Void)?

  private func court(in size: CGSize) -> CGRect {
    let scale = min((size.width-26)/10.97, (size.height-30)/PracticeEngine.length)
    let w = 8.23*scale, h = PracticeEngine.length*scale
    return CGRect(x:(size.width-w)/2, y:(size.height-h)/2,width:w,height:h)
  }
  var body: some View {
    GeometryReader { geometry in
      let rect = court(in: geometry.size)
      Canvas { context, _ in
        func screen(_ p: Vec) -> CGPoint {
          let q = CupPerspective.court(p, side: side)
          return CGPoint(x:rect.minX+q.x/8.23*rect.width, y:rect.minY+q.y/23.77*rect.height)
        }
        func line(_ a: Vec,_ b: Vec, dashed: Bool = false) {
          var path = Path(); path.move(to:screen(a)); path.addLine(to:screen(b))
          context.stroke(path,with:.color(dashed ? .mint : .white.opacity(0.8)),style:StrokeStyle(lineWidth:1.4,dash:dashed ? [4,3] : []))
        }
        context.fill(Path(rect),with:.color(Color(red:0.12,green:0.37,blue:0.29)))
        if recovery != nil && abs(feet.x - PracticeEngine.width / 2) > 0.25 {
          let near = CupPerspective.court(feet,side:side)
          let start = near.x < 4.115 ? 5.48 : 0.0
          context.fill(Path(CGRect(x:rect.minX+start/8.23*rect.width,y:rect.midY,width:rect.width/3,height:rect.height/2)),with:.color(.orange.opacity(0.36)))
        }
        context.stroke(Path(rect),with:.color(.white),lineWidth:1.5)
        for depth in [5.485,18.285] { line(Vec(x:0,y:depth), Vec(x:8.23,y:depth)) }
        line(Vec(x:4.115,y:5.485),Vec(x:4.115,y:18.285))
        line(Vec(x:-1.37,y:11.885),Vec(x:9.60,y:11.885))
        func dot(_ point: Vec,_ color: Color,_ hollow: Bool = false) {
          let p = screen(point); let circle = Path(ellipseIn:CGRect(x:p.x-6,y:p.y-6,width:12,height:12))
          if !hollow { context.fill(circle,with:.color(color)) }
          context.stroke(circle,with:.color(hollow ? color : .white),lineWidth:2)
        }
        if let recovery { line(feet,recovery,dashed:true); dot(recovery,.mint,true) }
        dot(opponent,.orange); dot(feet,.cyan)
        if let selection { dot(selection,.yellow,true) }
      }
      .contentShape(Rectangle())
      .gesture(SpatialTapGesture().onEnded { tap in
        let point = Vec(x:8.23*(tap.location.x-rect.minX)/rect.width,y:23.77*(tap.location.y-rect.minY)/rect.height)
        onPlace?(CupPerspective.court(point,side:side))
      })
    }
    .background(Color(red:0.06,green:0.19,blue:0.16),in: RoundedRectangle(cornerRadius:14))
    .accessibilityLabel("Court at contact, you in blue, opponent in orange.")
  }
}

private struct FrozenContact: UIViewRepresentable {
  let moment: DecisionSnapshot
  func makeUIView(context: Context) -> CourtReplayView {
    CourtReplayView(surface:moment.game.settings.surface,venue:moment.game.settings.matchVenue,localSide:moment.receiver)
  }
  func updateUIView(_ view: CourtReplayView, context: Context) {
    view.draw(moment.frame, angle: moment.receiver == 0 ? .you : .opponent, reduceMotion:false,powerBeat:nil)
  }
}

struct DecisionReviewView: View {
  let moment: DecisionSnapshot
  @State private var camera = false
  @State private var rehearse = false
  var body: some View {
    VStack(alignment:.leading,spacing:12) {
      Text("At your opponent’s contact").font(.title2.bold())
      Picker("View",selection:$camera) {
        Text("Coverage").tag(false); Text("Frozen 3D view").tag(true)
      }.pickerStyle(.segmented)
      Group {
        if camera { FrozenContact(moment:moment).accessibilityLabel("Frozen camera at the opponent’s strike") }
        else { DecisionCourt(side:moment.receiver,feet:moment.feet,opponent:moment.opponent,recovery:moment.recovery) }
      }.frame(maxWidth:.infinity,minHeight:100,maxHeight:.infinity)
      if !camera { HStack {
        Label("You",systemImage:"circle.fill").foregroundStyle(.teal)
        Label("Recovery spot",systemImage:"circle.dashed").foregroundStyle(.green)
      }.font(.caption) }
      let relative = CupPerspective.court(moment.feet,side:moment.receiver)
      let coverage = abs(relative.x - 4.115) <= 0.25 ? "You covered both sidelines evenly." :
        "You left more space on the " + (relative.x < 4.115 ? "right." : "left.")
      Text(String(format:"Your recovery spot was %.1f m away. ",moment.feet.distance(to:moment.recovery)) + coverage)
        .font(.subheadline)
      if moment.receiver == 0 && moment.game.attacking[0] && !moment.game.settings.local {
        Button("Rehearse this split",systemImage:"figure.tennis") { rehearse = true }
      }
    }.fullScreenCover(isPresented:$rehearse) {
      TrainingCourtView(.net,surface:moment.game.settings.surface,original:moment.game)
    }.padding().navigationTitle("Decision replay").navigationBarTitleDisplayMode(.inline)
  }
}

struct TrainingCourtView: View {
  @Environment(\.dismiss) private var dismiss
  let exercise: TrainingExercise
  let original: PracticeEngine?
  let comparison: String?
  let surface: CourtSurface
  @State private var serve: ServePlacement = .wide
  @State private var lane: TrainingLane = .right
  @State private var split = Vec(x:4.115,y:15)
  @State private var feed: PracticeEngine
  @State private var run: PracticeEngine?
  @State private var runID = UUID()
  @State private var startingComparison: String?
  @State private var previous: String?
  @State private var practiceRecord: TacticalPracticeRecord
  private var storageKey: String { "tactical.practice." + exercise.rawValue }

  init(_ exercise: TrainingExercise, surface: CourtSurface, original: PracticeEngine? = nil, comparison: String? = nil) {
    self.exercise = exercise; self.surface = surface; self.original = original; self.comparison = comparison
    let saved = UserDefaults.standard.data(forKey:"tactical.practice." + exercise.rawValue)
    _practiceRecord = State(initialValue:saved.flatMap { try? JSONDecoder().decode(TacticalPracticeRecord.self,from:$0) } ?? TacticalPracticeRecord())
    _feed = State(initialValue:original ?? TrainingFeed.net(surface:surface,lob:Bool.random(),right:Bool.random()))
    if let original, exercise == .net { _split = State(initialValue:original.players[0].pos) }
  }
  var body: some View {
    NavigationStack {
      Group {
        if let run {
          TrainingRally(seed:run,exercise:exercise,lane:lane,plannedServe:serve,previous:startingComparison) { summary, success in
            previous = summary
            practiceRecord.finish(success:success)
            if let data = try? JSONEncoder().encode(practiceRecord) { UserDefaults.standard.set(data,forKey:storageKey) }
          } tryAgain: { self.run = nil }.id(runID)
        } else {
          Form {
            if let previous { Section("Last attempt") { Text(previous) } }
            else if let comparison { Section("Original point") { Text(comparison) } }
            switch exercise {
            case .servePlusOne:
              Section("Plan the first two shots") {
                Picker("Serve",selection:$serve) { ForEach(ServePlacement.allCases,id:\.self) { Text($0.rawValue) } }
                Picker("Next landing lane",selection:$lane) { ForEach(TrainingLane.allCases,id:\.self) { Text($0.rawValue) } }
                Text("Tap to serve, read the return, then swipe your next ball into the lane you chose.")
              }
            case .net:
              Section("Choose where to split") {
                DecisionCourt(feet:feed.players[0].pos,opponent:feed.players[1].pos,selection:split) { point in
                  split = Vec(x:clamp(point.x,0.2,8.03),y:clamp(point.y,12.885,18.285))
                }.frame(height:220)
                Text("Tap your service box to place the yellow ring. Start from that split and play the pass or lob.")
                Picker("Split lane",selection:Binding(get:{ TrainingLane.allCases.min(by:{ abs($0.x-split.x)<abs($1.x-split.x) }) ?? .middle },set:{ split.x = $0.x })) {
                  ForEach(TrainingLane.allCases,id:\.self) { Text($0.rawValue) }
                }.pickerStyle(.segmented)
                if original == nil { Button("New opponent feed") { feed = TrainingFeed.net(surface:surface,lob:Bool.random(),right:Bool.random()) } }
              }
            case .retry:
              Section("Same starting position") {
                Text(original?.phase == .serving ? "Aim the same serve again from your saved position and compare the outcome." :
                  "The incoming ball, player positions and fatigue are restored. Play a different return and compare the outcome.")
              }
            }
            Button("Play this attempt",systemImage:"play.fill") {
              var start = exercise == .servePlusOne ? TrainingFeed.serve(serve,surface:surface) : feed
              if exercise == .net { TrainingFeed.split(split, into:&start) }
              startingComparison = previous ?? comparison
              runID = UUID(); run = start
            }.accessibilityIdentifier("startTacticalAttempt")
            if practiceRecord.attempts > 0 {
              Section("Practice record on this device") {
                LabeledContent("Completed attempts", value:String(practiceRecord.attempts))
                  .accessibilityIdentifier("practiceCompletedAttempts")
                LabeledContent(exercise == .servePlusOne ? "Planned lanes hit" : "Points won",
                               value:String(practiceRecord.successes))
                LabeledContent("Best streak", value:String(practiceRecord.bestStreak))
              }
            }
            DisclosureGroup("Motion credits") {
              Link("Tennis-MoCap · Pulgarin-Giraldo and colleagues",destination:URL(string:"https://github.com/jdpulgarin/Tennis-MoCap")!)
              Link("Adapted movement data · CC BY-SA 3.0",destination:URL(string:"https://creativecommons.org/licenses/by-sa/3.0/")!)
            }
          }
        }
      }.navigationTitle(exercise.rawValue).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
    }
  }
}

private struct TrainingRally: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var session: PracticeSession
  let exercise: TrainingExercise
  let lane: TrainingLane
  let plannedServe: ServePlacement
  let previous: String?
  let finish: (String, Bool) -> Void
  let tryAgain: () -> Void
  @State private var result: String?
  @State private var serveX: Double?
  @State private var returnX: Double?
  @State private var firstDriveSerial: Int?
  init(seed: PracticeEngine, exercise: TrainingExercise, lane: TrainingLane, plannedServe: ServePlacement, previous: String?,finish: @escaping (String,Bool)->Void,tryAgain: @escaping ()->Void) {
    _session = StateObject(wrappedValue:PracticeSession(engine:seed))
    self.exercise = exercise; self.lane = lane; self.plannedServe = plannedServe; self.previous = previous; self.finish = finish; self.tryAgain = tryAgain
  }
  var body: some View {
    VStack(spacing:0) {
      Text(exercise == .servePlusOne ? "\(plannedServe.rawValue) serve · Next ball \(lane.rawValue.lowercased())" : "Swipe toward yellow, then choose your shot")
        .font(.subheadline.weight(.semibold)).padding(8)
      LiveCourt(scene:session.scene, paused:session.paused)
      if let result {
        VStack(alignment:.leading,spacing:8) {
          Text(result).font(.headline)
          if let previous { Text("Previous · \(previous)").font(.footnote).foregroundStyle(.secondary) }
          Button("Try again", action: tryAgain).buttonStyle(.borderedProminent)
        }.frame(maxWidth:.infinity,alignment:.leading).padding().background(.bar)
      } else if session.paused {
        Button("Resume attempt") { session.resume() }.padding()
      }
    }
    .onAppear { session.scene.reduceMotion = reduceMotion }
    .onDisappear { session.pause() }
    .onChange(of:scenePhase) { _, phase in if phase != .active { session.pause() } }
    .onChange(of:session.snapshot.contactSerial) { _,_ in
      let game = session.snapshot
      guard result == nil, exercise == .servePlusOne, let shot = game.flight else { return }
      if shot.serve && shot.hitter == 0 && shot.fault == nil { serveX = game.players[1].pos.x }
      if shot.hitter == 1 && game.rally == 2 { returnX = shot.from.x }
      if shot.hitter == 0 && !shot.serve, let serveX, let returnX {
        firstDriveSerial = game.contactSerial
        let pulled = abs(returnX-serveX)
        let gap = abs(lane.x-game.players[1].pos.x)
        let landed = shot.fault == nil && abs(shot.landing.x-lane.x) <= 1.37
        let summary = String(format:"Returner moved %.1f m from the serve. Your planned lane was %.1f m from them. %@",pulled,gap,
          shot.fault != nil ? "Your next shot missed." : landed ? "You hit the planned lane." : "Your next shot went to another lane.")
        result = summary
        finish(summary, landed)
      }
    }
    .onChange(of:session.snapshot.flight?.progress) { _, progress in
      if let serial = firstDriveSerial, result != nil, !session.paused,
         session.snapshot.contactSerial != serial || (progress ?? 0) >= 0.85 {
        session.pause()
      }
    }
    .onChange(of:session.snapshot.showsPointResult) { _, visible in
      guard visible else { return }
      if result == nil {
        let game = session.snapshot
        let summary = game.feedback.title + " " + game.feedback.reason
        result = summary
        finish(summary, exercise != .servePlusOne && game.coach.records.last?.winner == 0)
      }
      session.pause()
    }
  }
}
