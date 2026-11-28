import RealityKit
import UIKit

/// Physical fixtures shared by the live court and its replay. Only the two
/// score faces and radar faces need new materials during a match.
@MainActor final class ArenaCourtside {
  private let scores: [ModelEntity]
  private let radars: [ModelEntity]
  private let umpireHead: Entity?
  private var headYaw: Float = 0
  private var score: Score?
  private var speed: Int?
  private var session: UUID?
  private var contact: Int?

  private struct Score: Equatable {
    let player, opponent: String
    let games, points: [Int]
    let server: Int
    let format: PracticeScoring
    let winner: Int?
  }

  init(court: Entity) {
    umpireHead = court.findEntity(named:"chair-umpire-head")
    scores = (0...1).compactMap { court.findEntity(named:"match-score-\($0)") as? ModelEntity }
    radars = (0...1).compactMap { court.findEntity(named:"ball-radar-\($0)") as? ModelEntity }
  }

  func update(_ game: PracticeEngine, reduceMotion: Bool) {
    // From the right net post the umpire looks along the flight to each baseline.
    let target = reduceMotion ? 0 : Float(atan2(game.ball.y-11.8,11.10-game.ball.x))
    let yaw = min(0.92,max(-0.92,target))
    if abs(yaw-headYaw) > 0.05 {
      headYaw = yaw
      umpireHead?.orientation = simd_quatf(angle:yaw,axis:[0,1,0])
    }
    let s = game.scoring
    let value = Score(player:game.settings.playerName,opponent:game.settings.opponentName,games:s.games,points:s.points,
                      server:s.server,format:s.format,winner:s.winner)
    if value != score {
      score = value
      let mat = Self.ink(width:1000,height:290) { ctx in
        Self.fill(ctx,0,0,1000,290,Self.board)
        Self.fill(ctx,0,0,1000,51,UIColor(red:0.06,green:0.26,blue:0.23,alpha:1))
        let event = s.format == .tiebreak ? "TIEBREAK" : "SINGLES"
        Self.type(event+"  ·  "+game.settings.matchVenue.rawValue.uppercased(),28,18,8,578,38,.white)
        Self.type("GAMES",26,632,8,150,38,.white,.center)
        Self.type("PTS",26,831,8,144,38,Self.lime,.center)
        Self.fill(ctx,16,169,968,2,UIColor(white:0.35,alpha:1))
        for side in 0...1 {
          let y = 52+side*119
          if (s.winner ?? s.server) == side {
            ctx.setFillColor(Self.lime.cgColor)
            ctx.fillEllipse(in:CGRect(x:22,y:y+48,width:20,height:20))
          }
          Self.type(game.name(side),64,60,y,540,116,.white)
          Self.type(String(s.games[side]),70,620,y,170,116,.white,.center)
          Self.type(s.pointLabel(side),78,802,y,170,116,Self.lime,.center)
        }
      }
      for face in scores { face.model?.materials = [mat]; face.isEnabled = true }
    }
    if session != game.coach.sessionID {
      session = game.coach.sessionID
      contact = nil
      speed = nil
      if game.flight == nil { showSpeed(nil) }
    }
    if let flight = game.flight, contact != game.contactSerial {
      contact = game.contactSerial
      let reading = flight.launchSpeedKPH
      guard reading != speed else { return }
      speed = reading
      showSpeed(reading)
    }
  }

  private func showSpeed(_ reading: Int?) {
    let mat = Self.ink(width:440,height:228) { ctx in
      Self.fill(ctx,0,0,440,228,Self.board)
      Self.type("BALL SPEED",31,12,7,416,40,.white,.center)
      Self.type(reading.map(String.init) ?? "—",132,8,35,424,147,Self.amber,.center)
      Self.type("KM/H",32,12,181,416,40,.white,.center)
    }
    for face in radars { face.model?.materials = [mat]; face.isEnabled = true }
  }

  private static let board = UIColor(red:0.025,green:0.070,blue:0.082,alpha:1)
  private static let lime = UIColor(red:0.82,green:0.98,blue:0.53,alpha:1)
  private static let amber = UIColor(red:1,green:0.77,blue:0.24,alpha:1)

  private static func fill(_ ctx: CGContext,_ x: Int,_ y: Int,_ w: Int,_ h: Int,_ color: UIColor) {
    ctx.setFillColor(color.cgColor); ctx.fill(CGRect(x:x,y:y,width:w,height:h))
  }
  private static func type(_ text: String,_ size: CGFloat,_ x: Int,_ y: Int,_ w: Int,_ h: Int,
                           _ color: UIColor,_ align: NSTextAlignment = .left) {
    let line = NSMutableParagraphStyle()
    line.alignment = align
    line.lineBreakMode = .byTruncatingTail
    let rect = CGRect(x:x,y:y,width:w,height:h)
    let string = text as NSString
    var font = UIFont.systemFont(ofSize:size,weight:.bold)
    let width = string.size(withAttributes:[.font:font]).width
    if width > rect.width { font = font.withSize(max(size*0.66,size*rect.width/width)) }
    let area = rect.insetBy(dx:0,dy:max(0,(rect.height-font.lineHeight)*0.5))
    string.draw(with:area,options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine],
                attributes:[.font:font,.foregroundColor:color,.paragraphStyle:line],context:nil)
  }
  private static func ink(width: Int,height: Int,draw: (CGContext)->Void) -> UnlitMaterial {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1; format.opaque = true
    let image = UIGraphicsImageRenderer(size:CGSize(width:width,height:height),format:format).image { draw($0.cgContext) }
    var mat = UnlitMaterial(color:board)
    if let cg = image.cgImage, let map = try? TextureResource.generate(from:cg,options:.init(semantic:.color)) {
      mat.color = .init(tint:.white,texture:.init(map))
    }
    return mat
  }

  @discardableResult private static func panel(_ parent: Entity,at atPoint: CourtPoint3D,yaw: Float,
    width: Float,height: Float,material: UnlitMaterial,name: String = "") -> Entity {
    let mount = Entity()
    mount.position = atPoint; mount.orientation = simd_quatf(angle:yaw,axis:[0,1,0])
    let backing = ModelEntity(mesh:.generateBox(size:[width+0.09,height+0.09,0.14]),
                              materials:[SimpleMaterial(color:board,roughness:0.9,isMetallic:false)])
    mount.addChild(backing)
    let face = ModelEntity(mesh:.generatePlane(width:width,height:height),materials:[material])
    face.name = name; face.position.z = 0.075
    face.isEnabled = name.isEmpty
    mount.addChild(face); parent.addChild(mount)
    return mount
  }

  static func build(scenery: Entity, ends: [Entity]) {
    let ads: [(String,String,UIColor)] = [
      ("RPSXO","most fun apple watch game",UIColor(red:0.17,green:0.12,blue:0.40,alpha:1)),
      ("Play Judgement,","most addictive family card game",UIColor(red:0.35,green:0.085,blue:0.13,alpha:1)),
      ("SwipeTennis","- revolutionizing tennis coaching",UIColor(red:0.045,green:0.23,blue:0.19,alpha:1)),
      ("DriveHabits:","Best productivity app",UIColor(red:0.09,green:0.20,blue:0.34,alpha:1)),
      ("SantaAgents:","Worlds most helpful personalized agents!",UIColor(red:0.39,green:0.12,blue:0.12,alpha:1))
    ]
    let posters = ads.map { brand,copy,tint in
      ink(width:1080,height:300) { ctx in
        fill(ctx,0,0,1080,300,tint)
        type(brand,129,24,7,1032,167,.white,.center)
        type(copy,60,24,171,1032,99,UIColor(white:0.94,alpha:1),.center)
      }
    }
    let chair = crew(.umpire), judge = crew(.line), attendant = crew(.ball)
    func place(_ figure: Entity,_ atPoint: CourtPoint3D,_ yaw: Float,_ parent: Entity) {
      let copy = figure.clone(recursive:true)
      copy.position = atPoint; copy.orientation = simd_quatf(angle:yaw,axis:[0,1,0])
      parent.addChild(copy)
    }
    place(chair,[11.10,2.315,11.80],.pi/2,scenery)
    for end in 0...1 {
      let sign: Float = end == 0 ? 1 : -1
      let yaw: Float = end == 0 ? 0 : .pi
      let stand = ends[end]
      let base: Float = end == 0 ? 0 : 23.77
      func pos(_ dx: Float,_ y: Float,_ dz: Float) -> CourtPoint3D { [4.115+sign*dx,y,base+sign*dz] }
      panel(stand,at:pos(0,1.42,-9.68),yaw:yaw,width:9.65,height:2.64,material:.init(color:board),name:"match-score-\(end)")
      for (ad,offset) in [(0,Float(-9.94)),(1,Float(9.94))] {
        panel(stand,at:pos(offset,1.14,-9.68),yaw:yaw,width:9.42,height:2.09,material:posters[ad])
      }
      for (ad,offset) in [(2,Float(-8.3)),(3,Float(8.3))] {
        panel(stand,at:pos(offset,0.74,-0.70),yaw:yaw-offset*0.045,width:4.7,height:1.39,material:posters[ad])
      }
      panel(stand,at:pos(-10.75*sign,0.73,3.4),yaw:yaw+sign*0.34,width:2.68,height:1.36,material:.init(color:board),name:"ball-radar-\(end)")
      // The radar head sits on a short tripod beside its digital readout.
      let hardware = ReplayMeshLines()
      for i in 0..<3 {
        let a = Float(i)*2 * .pi/3
        hardware.line(pos(-12.52*sign,1.02,3.3),pos(-12.52*sign+0.36*cos(a),0.03,3.3+0.36*sin(a)),radius:0.033)
      }
      hardware.box(center:pos(-12.52*sign,1.09,3.3),size:[0.25,0.21,0.43])
      stand.addChild(hardware.model(color:.darkGray))
      for x: Float in [-5.485,5.485] { place(judge,pos(x,0,-5.6),yaw + .pi,stand) }
      place(attendant,pos(-9.0,0,-5.2),yaw + .pi,stand)
    }
    let sidelineChairs = ReplayMeshLines()
    let seatedJudge = chair.clone(recursive:true)
    seatedJudge.findEntity(named:"chair-umpire-head")?.name = "line-judge-head"
    for z: Float in [5.485,18.285] {
      let seat = CourtPoint3D(-4.25,0.51,z)
      sidelineChairs.box(center:seat,size:[0.48,0.065,0.52])
      sidelineChairs.box(center:seat+[-0.22,0.20,0],size:[0.045,0.40,0.52])
      for dx: Float in [-0.19,0.19] { for dz: Float in [-0.21,0.21] {
        sidelineChairs.line(seat+[dx,-0.02,dz],seat+[dx*1.22,-0.50,dz*1.12],radius:0.023)
      } }
      place(seatedJudge,seat+[0,0.035,0],-.pi/2,scenery)
    }
    scenery.addChild(sidelineChairs.model(color:board))
    for sign: Float in [-1,1] {
      let x = 4.115+sign*12.6
      panel(scenery,at:[x,0.72,11.885-sign*5.1],yaw:-sign * .pi/2,width:5.85,height:1.36,material:posters[4])
      place(attendant,[4.115+sign*8.45,0,11.885+sign*0.55],sign * .pi/2,scenery)
    }
  }

  private enum Role { case umpire, line, ball }

  /// All uniforms and limbs are built once per role. The chair pose uses
  /// the seat as its origin. Standing and kneeling figures use the sole.
  private static func crew(_ role: Role) -> Entity {
    let shirt = ReplayMeshLines(), skin = ReplayMeshLines(), pants = ReplayMeshLines(), trim = ReplayMeshLines()
    let seated = role == .umpire, kneeling = role == .ball
    let hips: Float = seated ? 0.07 : kneeling ? 0.60 : 0.88
    let lean: Float = seated ? -0.04 : kneeling ? -0.25 : -0.15
    let pelvis = CourtPoint3D(0,hips,0)
    shirt.contour(pelvis,rings:[(-0.025,0.16,0.12,0),(0.12,0.145,0.11,lean*0.25),
      (0.34,0.195,0.125,lean*0.75),(0.43,0.214,0.12,lean),(0.51,0.08,0.074,lean)])
    let neck = pelvis+[0,0.50,lean]
    skin.line(neck,neck+[0,0.11,0],radius:0.059)
    let face = ReplayMeshLines(), hair = ReplayMeshLines()
    face.contour(.zero,rings:[(0.058,0.045,0.065,-0.024),(0.10,0.083,0.085,-0.014),
                             (0.19,0.096,0.102,0),(0.248,0.083,0.087,0.006),(0.27,0.047,0.051,0.01)])
    face.oval([0,0.151,-0.10],radii:[0.021,0.028,0.023])
    hair.oval([0,0.228,0.014],radii:[0.104,0.078,0.105])
    if !seated { hair.oval([0,0.222,-0.067],radii:[0.11,0.018,0.127]) }
    trim.line(neck+[-0.079,-0.012,0],neck+[0,-0.068,-0.086],radius:0.014)
    trim.line(neck+[0.079,-0.012,0],neck+[0,-0.068,-0.086],radius:0.014)
    for side: Float in [-1,1] {
      let hip = pelvis+[side*0.098,0,0]
      let knee = seated ? hip+[side*0.04,-0.07,-0.37] :
        kneeling ? CourtPoint3D(side*0.17,side < 0 ? 0.095 : 0.38,side < 0 ? 0.14 : -0.34) :
        hip+[side*0.07,-0.40,-0.09]
      let ankle = seated ? knee+[0,-0.395,0.025] : CourtPoint3D(side*0.175,0.09,kneeling ? (side < 0 ? 0.50 : -0.27) : 0.03)
      pants.line(hip,knee,radius:0.09); pants.oval(knee,radii:[0.084,0.088,0.085])
      let lower = kneeling ? skin : pants
      lower.line(knee,ankle,radius:kneeling ? 0.056 : 0.066)
      trim.oval(ankle+[0,-0.03,-0.052],radii:[0.069,0.057,0.133])
      let shoulder = pelvis+[side*0.172,0.408,lean]
      let elbow = shoulder+[side*0.067,-0.235,-0.07]
      let hand = seated ? knee+[0,0.13,0.06] : kneeling ? elbow+[-side*0.10,-0.22,-0.14] : knee+[0,0.20,-0.03]
      let sleeve = shoulder+(elbow-shoulder)*0.62
      shirt.oval(shoulder,radii:[0.083,0.076,0.081])
      shirt.line(shoulder,sleeve,radius:0.081); skin.line(sleeve,elbow,radius:0.054)
      skin.line(elbow,hand,radius:0.047); skin.oval(hand,radii:[0.042,0.061,0.047])
    }
    let root = Entity()
    root.addChild(shirt.model(color:kneeling ? .init(red:0.09,green:0.18,blue:0.27,alpha:1) : .init(red:0.46,green:0.70,blue:0.77,alpha:1)))
    root.addChild(pants.model(color:UIColor(red:0.105,green:0.14,blue:0.19,alpha:1)))
    let tone: UIColor = seated ? .init(red:0.55,green:0.33,blue:0.22,alpha:1) : .init(red:0.73,green:0.50,blue:0.35,alpha:1)
    root.addChild(skin.model(color:tone))
    let head = Entity()
    head.name = seated ? "chair-umpire-head" : "crew-head"
    head.position = neck
    head.addChild(face.model(color:tone)); head.addChild(hair.model(color:board))
    root.addChild(head)
    root.addChild(trim.model(color:.init(white:0.91,alpha:1)))
    return root
  }
}
