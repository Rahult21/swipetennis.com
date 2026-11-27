import SwiftUI

extension KitColor {
  var tint: UIColor {
    switch self {
    case .tide: return UIColor(red:0.16, green:0.65, blue:0.70, alpha:1)
    case .ember: return UIColor(red:0.91, green:0.34, blue:0.15, alpha:1)
    case .violet: return UIColor(red:0.52, green:0.36, blue:0.78, alpha:1)
    case .white: return UIColor(white:0.92, alpha:1)
    }
  }
}
enum SkinTone: String, CaseIterable {
  case porcelain = "Porcelain", honey = "Honey", bronze = "Bronze", umber = "Umber", espresso = "Espresso"

  var tint: UIColor {
    let rgb: (CGFloat, CGFloat, CGFloat)
    switch self {
    case .porcelain: rgb = (0.89, 0.71, 0.60)
    case .honey: rgb = (0.79, 0.55, 0.39)
    case .bronze: rgb = (0.68, 0.42, 0.29)
    case .umber: rgb = (0.48, 0.285, 0.19)
    case .espresso: rgb = (0.32, 0.18, 0.14)
    }
    return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
  }
}

enum LockerAngle: String, CaseIterable {
  case front = "Front", side = "Side", back = "Back"
  var radians: Float {
    switch self { case .front: return 0; case .side: return .pi / 2; case .back: return .pi }
  }
}

enum Wristband: String, CaseIterable { case chalk = "White", match = "Match shirt", none = "None" }

struct AthleteKit {
  var wristband = Wristband.chalk
  var skort = false
  var skinTone = SkinTone.bronze
  let model: AthleteModel, shirt: TennisKit, color: KitColor, prop: KitProp
  static func current(side: Int, localSide: Int) -> Self {
    let d = UserDefaults.standard
    let selfModel = AthleteModel(rawValue: d.string(forKey:"athleteModel") ?? "") ?? .woman
    if side != localSide {
      return Self(skort:selfModel == .man,skinTone:.umber,model:selfModel == .man ? .woman : .man, shirt:.polo,
        color:d.string(forKey:"kitColor") == KitColor.ember.rawValue ? .tide : .ember, prop:.band)
    }
    return Self(wristband:Wristband(rawValue:d.string(forKey:"kitWrist") ?? "") ?? .chalk,skort:d.bool(forKey:"kitSkort"),skinTone:SkinTone(rawValue:d.string(forKey:"kitSkin") ?? "") ?? .bronze,model:selfModel, shirt:TennisKit(rawValue:d.string(forKey:"kitShirt") ?? "") ?? .crew,
      color:KitColor(rawValue:d.string(forKey:"kitColor") ?? "") ?? .tide,
      prop:KitProp(rawValue:d.string(forKey:"kitProp") ?? "") ?? .visor)
  }
}
struct LockerRoom: View {
  @AppStorage("athleteModel") private var model = AthleteModel.woman.rawValue
  @AppStorage("kitSkort") private var skort = false
  @AppStorage("kitShirt") private var shirt = TennisKit.crew.rawValue
  @AppStorage("kitColor") private var color = KitColor.tide.rawValue
  @AppStorage("kitProp") private var prop = KitProp.visor.rawValue
  @AppStorage("kitSkin") private var skin = SkinTone.bronze.rawValue
  @AppStorage("kitWrist") private var wristband = Wristband.chalk.rawValue
  @State private var angle = LockerAngle.front
  @State private var orbit: Float = 0
  @GestureState private var drag: CGFloat = 0
  @State private var previewReady = false
  @State private var visible = true
  private var appearance: [String] { [model, shirt, color, prop, skin, wristband, String(skort)] }
  var body: some View {
    Form {
      Section {
        Group {
          if visible {
            KitPreview(azimuth:angle.radians+orbit+Float(drag)*0.012) { previewReady = true }
          } else { Color.clear }
        }
          .id(appearance).frame(height:220)
          .overlay {
            Rectangle().fill(.clear).contentShape(Rectangle())
              .gesture(DragGesture(minimumDistance: 6)
                .updating($drag) { value, state, _ in state = value.translation.width }
                .onEnded { orbit += Float($0.translation.width) * 0.012 })
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(model), \(skin) skin, \(color) \(shirt), \(prop)")
          .accessibilityValue(previewReady ? angle.rawValue + " view" : "Loading")
          .accessibilityIdentifier("kitPreview")
          .onChange(of:appearance) { _,_ in previewReady = false }
        Picker("Preview angle", selection: $angle) {
          ForEach(LockerAngle.allCases, id: \.self) { Text($0.rawValue) }
        }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
          .onChange(of: angle) { _, _ in orbit = 0 }
      }.listRowInsets(EdgeInsets())
      Section {
        NavigationLink { StrokeStudioView() } label: { Label("Stroke studio",systemImage:"figure.tennis") }
          .accessibilityIdentifier("strokeStudio")
      }
      Section {
        Picker("Athlete", selection:$model) { ForEach(AthleteModel.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
        Picker("Skin tone", selection: $skin) {
          ForEach(SkinTone.allCases, id: \.self) { tone in
            Label { Text(tone.rawValue) } icon: { Circle().fill(Color(uiColor:tone.tint)) }.tag(tone.rawValue)
          }
        }
        .accessibilityIdentifier("kitSkinTone")
        Picker("Shirt", selection:$shirt) { ForEach(TennisKit.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
        Picker("Bottoms",selection:$skort) { Text("Shorts").tag(false); Text("Skort").tag(true) }
        Picker("Color", selection:$color) { ForEach(KitColor.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
        Picker("Wristbands", selection:$wristband) { ForEach(Wristband.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
        Picker("Headwear", selection:$prop) { ForEach(KitProp.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
      }
      Section {
        Link("3D athlete asset credits",destination:URL(string:"https://www.makehumancommunity.org/")!)
      }
    }.navigationTitle("Player & kit")
      .onAppear { visible = true }
      .onDisappear { visible = false; previewReady = false }
  }
}
