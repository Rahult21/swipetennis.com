// Bake only the UV islands used by the clothed skin mesh. Dilate their edges
// for mip filtering so the atlas stays clean at a distance.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let input = CommandLine.arguments
let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input[1]) as CFURL, nil)!
let size = Int(input[3])!
let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size
] as CFDictionary)!
let alpha = input[2].hasSuffix(".png")
let w = thumbnail.width, h = thumbnail.height
let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,
  bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
if input.count > 4 {
  ctx.setFillColor(CGColor(gray:0.45,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:w,height:h))
  let faces = try JSONDecoder().decode([[[CGFloat]]].self, from:Data(contentsOf:URL(fileURLWithPath:input[4])))
  let path = CGMutablePath()
  for face in faces {
    let points = face.map { CGPoint(x:$0[0]*CGFloat(w),y:$0[1]*CGFloat(h)) }
    path.addLines(between:points); path.closeSubpath()
  }
  ctx.addPath(path.copy(strokingWithWidth:4,lineCap:.round,lineJoin:.round,miterLimit:1))
  ctx.addPath(path); ctx.clip()
}
ctx.draw(thumbnail,in:CGRect(x:0,y:0,width:w,height:h))
let url = URL(fileURLWithPath:input[2])
let dest = CGImageDestinationCreateWithURL(url as CFURL,(alpha ? UTType.png : UTType.jpeg).identifier as CFString,1,nil)!
CGImageDestinationAddImage(dest,ctx.makeImage()!,[kCGImageDestinationLossyCompressionQuality:0.89] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { fatalError("Could not write player texture") }
