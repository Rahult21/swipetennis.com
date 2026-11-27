// Run with paths to the two source Radiance panoramas and the asset catalog.
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let output = URL(fileURLWithPath:args[3],isDirectory:true)
let context = CIContext()
let space = CGColorSpace(name:CGColorSpace.sRGB)!
func save(_ image: CIImage, name: String) throws {
  let directory = output.appendingPathComponent(name+".imageset",isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  let path = directory.appendingPathComponent("texture.jpg")
  try context.writeJPEGRepresentation(of:image,to:path,colorSpace:space,options:[kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption:0.88])
  let manifest = #"{"images":[{"filename":"texture.jpg","idiom":"universal"}],"info":{"author":"xcode","version":1}}"#
  try manifest.write(to:directory.appendingPathComponent("Contents.json"),atomically:true,encoding:.utf8)
}
let day = CIImage(contentsOf:URL(fileURLWithPath:args[1]))!
let late = CIImage(contentsOf:URL(fileURLWithPath:args[2]))!
func daylight(_ image: CIImage) -> CIImage {
  image.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:0.65])
    .applyingFilter("CIHighlightShadowAdjust",parameters:["inputShadowAmount":0.52,"inputHighlightAmount":0.62])
    .applyingFilter("CIGammaAdjust",parameters:["inputPower":0.74])
}
try save(daylight(day),name:"venue-sky-day")
try save(daylight(late),name:"venue-sky-late")
let dusk = daylight(late).applyingFilter("CIColorMatrix",parameters:[
  "inputRVector":CIVector(x:0.035,y:0,z:0,w:0),"inputGVector":CIVector(x:0,y:0.065,z:0,w:0),
  "inputBVector":CIVector(x:0,y:0,z:0.15,w:0)])
try save(dusk,name:"venue-sky-night")
