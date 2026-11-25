// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SwipeTennisCore", platforms: [.macOS(.v13)], products: [.library(name:"TennisCore",targets:["TennisCore"])], targets: [.target(name:"TennisCore",path:"SwipeTennis/Core"),.testTarget(name:"TennisCoreTests",dependencies:["TennisCore"],path:"Tests")])
