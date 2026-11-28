// Compile on macOS and supply four native Stroke studio exports in chapter order:
// make_quick_start destination.mp4 serve.mp4 run.mp4 forehand.mp4 backhand.mp4
import AppKit
import AVFoundation

let args=CommandLine.arguments
guard args.count==6 else { fatalError("Expected destination, serve, run, forehand and backhand paths") }
let width=720,height=848, panel:CGFloat=170, fps:Int32=30
let output=URL(fileURLWithPath:args[1])
let writer=try AVAssetWriter(outputURL:output,fileType:.mp4)
let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,
  AVVideoWidthKey:width,AVVideoHeightKey:height,
  AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:2_400_000,AVVideoExpectedSourceFrameRateKey:fps]])
let pixels=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
  kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime:.zero)
let hand=NSImage(systemSymbolName:"hand.point.up.left.fill",accessibilityDescription:nil)?
  .withSymbolConfiguration(.init(pointSize:32,weight:.medium))?
  .withSymbolConfiguration(.init(paletteColors:[.white]))?.cgImage(forProposedRect:nil,context:nil,hints:nil)
let white=CGColor(gray:0.97,alpha:1), muted=CGColor(red:0.73,green:0.84,blue:0.80,alpha:1)
let blue=CGColor(red:0.43,green:0.76,blue:1,alpha:1),yellow=CGColor(red:0.96,green:0.91,blue:0.28,alpha:1)
let purple=CGColor(red:0.81,green:0.68,blue:0.99,alpha:1)
func ease(_ value:Double)->Double { let u=max(0,min(1,value));return u*u*(3-2*u) }
func diagram(_ c:CGContext,chapter:Int,t:Double) {
  c.setFillColor(CGColor(red:0.052,green:0.143,blue:0.122,alpha:1))
  c.fill(CGRect(x:0,y:0,width:width,height:Int(panel)))
  func line(_ a:CGPoint,_ b:CGPoint,_ color:CGColor,_ weight:CGFloat){
    c.setStrokeColor(color);c.setLineWidth(weight);c.setLineCap(.round)
    c.move(to:a);c.addLine(to:b);c.strokePath()
  }
  func text(_ string:String,at p:CGPoint,size:CGFloat,bold:Bool,color:CGColor){
    let attr:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular),
                                           .foregroundColor:NSColor(cgColor:color)!]
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
    string.draw(at:p,withAttributes:attr);NSGraphicsContext.restoreGraphicsState()
  }
  func ring(_ p:CGPoint,_ color:CGColor,_ pulse:Double) {
    for i in 0..<3 {
      let f=(pulse+Double(i)/3).truncatingRemainder(dividingBy:1)
      let radius=4+10*f
      c.setLineWidth(CGFloat(2.7*(1-f)+0.7));c.setStrokeColor(color.copy(alpha:0.92*(1-f))!)
      c.strokeEllipse(in:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2))
    }
  }
  let court=CGRect(x:92,y:14,width:74,height:143), lines=white.copy(alpha:0.69)!
  c.setFillColor(CGColor(red:0.12,green:0.27,blue:0.22,alpha:1));c.fill(court)
  c.setStrokeColor(lines);c.setLineWidth(1.6);c.stroke(court)
  for x in [court.minX+9,court.maxX-9] {line(CGPoint(x:x,y:court.minY),CGPoint(x:x,y:court.maxY),lines,1.1)}
  for f in [0.23,0.77] {let y=court.minY+court.height*f;line(CGPoint(x:court.minX+9,y:y),CGPoint(x:court.maxX-9,y:y),lines,1)}
  line(CGPoint(x:court.midX,y:court.minY+court.height*0.23),CGPoint(x:court.midX,y:court.minY+court.height*0.77),lines,1)
  line(CGPoint(x:court.minX-3,y:court.midY),CGPoint(x:court.maxX+3,y:court.midY),white,2.2)
  let start=CGPoint(x:court.midX,y:court.minY+10)
  var finger=CGPoint.zero, target=CGPoint.zero
  let progress=ease((t-0.3)/1.48)
  let title:String,caption:String
  let tint:CGColor
  switch chapter {
  case 0:
    tint=blue;target=CGPoint(x:court.midX+6+17*progress,y:court.midY+21)
    finger=CGPoint(x:start.x+19*progress,y:start.y+8*progress)
    if t >= 2 {
      let swing=ease((t-2.25)/0.85)
      finger=CGPoint(x:start.x+(target.x-start.x)*swing,y:start.y+(target.y-start.y)*swing)
    }
    title=t<2 ? "Drag on your half" : "Swipe toward blue"
    caption=t<2 ? "Set blue, then hold still" : "Swipe farther to land deeper"
  case 1:
    tint=yellow;target=CGPoint(x:court.maxX-9,y:court.minY+16)
    finger=CGPoint(x:start.x+(target.x-start.x)*progress,y:start.y+(target.y-start.y)*progress)
    title="Prepare the return";caption="Your player moves to receive"
  default:
    let deep=chapter==2
    tint=purple;target=CGPoint(x:court.midX+(deep ? -19:18)*progress,y:court.midY+(deep ? 63:24)*progress)
    finger=CGPoint(x:start.x+(deep ? -22:14)*progress,y:start.y+(deep ? 70:27)*progress)
    title=deep ? "Swipe farther" : "Use a shorter swipe"
    caption=deep ? "Aim deep before contact" : "Bring the landing inside the court"
  }
  ring(target,tint,t*1.32)
  if t<2.35 || (chapter==0 && t<3.4) {
    line(start,finger,white.copy(alpha:0.58)!,3)
    if let hand { c.draw(hand,in:CGRect(x:finger.x-2,y:finger.y-22,width:31,height:32)) }
  }
  text(title,at:CGPoint(x:229,y:91),size:37,bold:true,color:white)
  text(caption,at:CGPoint(x:230,y:56),size:23,bold:false,color:muted)
  for i in 0..<4 {
    c.setFillColor(i==chapter ? tint : white.copy(alpha:0.24)!)
    c.fill(CGRect(x:231+i*27,y:29,width:19,height:3))
  }
}
for (chapter,path) in args.dropFirst(2).enumerated() {
  let asset=AVURLAsset(url:URL(fileURLWithPath:path))
  let reader=try AVAssetReader(asset:asset)
  let video=AVAssetReaderTrackOutput(track:asset.tracks(withMediaType:.video).first!,
                 outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
  reader.add(video);guard reader.startReading() else {throw reader.error!}
  var sample=video.copyNextSampleBuffer(), displayed:CMSampleBuffer?
  let duration=asset.duration.seconds
  for i in 0..<5*Int(fps) {
    let seconds=Double(i)/Double(fps)
    let t=max(0,min(duration-0.012,(seconds-0.30)*max(1,duration/4.48)))
    while let next=sample, CMSampleBufferGetPresentationTimeStamp(next).seconds<=t+0.002 {
      displayed=next; sample=video.copyNextSampleBuffer()
    }
    guard let source=displayed ?? sample,let frame=CMSampleBufferGetImageBuffer(source) else {fatalError("Empty native court film")}
    while !input.isReadyForMoreMediaData && writer.status == .writing { Thread.sleep(forTimeInterval:0.004) }
    guard writer.status == .writing else {throw writer.error!}
    try autoreleasepool {
      var result:CVPixelBuffer?
      guard let bufferPool=pixels.pixelBufferPool,CVPixelBufferPoolCreatePixelBuffer(nil,bufferPool,&result)==kCVReturnSuccess,let buf=result else {fatalError("Video buffer")}
      CVPixelBufferLockBaseAddress(buf,[]);CVPixelBufferLockBaseAddress(frame,.readOnly)
      let flags=CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.noneSkipFirst.rawValue
      let space=CGColorSpace(name:CGColorSpace.sRGB)!
      let c=CGContext(data:CVPixelBufferGetBaseAddress(buf),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buf),space:space,bitmapInfo:flags)!
      let source=CGContext(data:CVPixelBufferGetBaseAddress(frame),width:CVPixelBufferGetWidth(frame),height:CVPixelBufferGetHeight(frame),
        bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(frame),space:space,bitmapInfo:flags)!.makeImage()!
      c.draw(source,in:CGRect(x:0,y:panel,width:CGFloat(width),height:CGFloat(height)-panel))
      diagram(c,chapter:chapter,t:seconds)
      CVPixelBufferUnlockBaseAddress(frame,.readOnly);CVPixelBufferUnlockBaseAddress(buf,[])
      guard pixels.append(buf,withPresentationTime:CMTime(value:Int64(chapter*150+i),timescale:fps)) else {throw writer.error!}
    }
  }
}
input.markAsFinished();let completed=DispatchSemaphore(value:0)
writer.finishWriting { completed.signal() };completed.wait()
guard writer.status == .completed else {throw writer.error!}
