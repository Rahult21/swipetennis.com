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
struct AthleteKit {
  var skort = false
  let model: AthleteModel, shirt: TennisKit, color: KitColor, prop: KitProp
  static func current(side: Int, localSide: Int) -> Self {
    let d = UserDefaults.standard
    let selfModel = AthleteModel(rawValue: d.string(forKey:"athleteModel") ?? "") ?? .woman
    if side != localSide {
      return Self(skort:selfModel == .man,model:selfModel == .man ? .woman : .man, shirt:.polo,
        color:d.string(forKey:"kitColor") == KitColor.ember.rawValue ? .tide : .ember, prop:.band)
    }
    return Self(skort:d.bool(forKey:"kitSkort"),model:selfModel, shirt:TennisKit(rawValue:d.string(forKey:"kitShirt") ?? "") ?? .crew,
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
  var body: some View {
    Form {
      Section {
        KitPreview().id([model, shirt, color, prop, String(skort)]).frame(height:220)
          .accessibilityLabel("\(model), \(color) \(shirt), \(prop)")
      }.listRowInsets(EdgeInsets())
      Section {
        Picker("Athlete", selection:$model) { ForEach(AthleteModel.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }.pickerStyle(.segmented)
        Picker("Shirt", selection:$shirt) { ForEach(TennisKit.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
        Picker("Bottoms",selection:$skort) { Text("Shorts").tag(false); Text("Skort").tag(true) }
        Picker("Color", selection:$color) { ForEach(KitColor.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
        Picker("Headwear", selection:$prop) { ForEach(KitProp.allCases,id:\.rawValue) { Text($0.rawValue).tag($0.rawValue) } }
      }
    }.navigationTitle("Player & kit")
  }
}
