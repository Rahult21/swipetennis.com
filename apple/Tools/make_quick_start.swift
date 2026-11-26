// Run on macOS: swift apple/Tools/make_quick_start.swift <destination.mp4>
import AppKit
import AVFoundation

let width = 720, height = 640, fps: Int32 = 24
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let writer = try AVAssetWriter(outputURL:url,fileType:.mp4)
let input = AVAssetWriterInput(mediaType:.video,outputSettings:[
  AVVideoCodecKey:AVVideoCodecType.h264, AVVideoWidthKey:width, AVVideoHeightKey:height,
  AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:850000,AVVideoMaxKeyFrameIntervalKey:24]])
let pool = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
  kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
  kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height])
writer.add(input)
guard writer.startWriting() else { fatalError(String(describing:writer.error)) }
writer.startSession(atSourceTime:.zero)
let white = CGColor(gray:0.96,alpha:1), yellow = NSColor.systemYellow.cgColor
let blue = NSColor.systemCyan.cgColor, purple = NSColor.systemPurple.cgColor
let hand = NSImage(systemSymbolName:"hand.point.up.left.fill",accessibilityDescription:nil)?
  .withSymbolConfiguration(.init(pointSize:40,weight:.medium).applying(.init(paletteColors:[.white])))
var handRect = CGRect(x:0,y:0,width:42,height:52)
let finger = hand?.cgImage(forProposedRect:&handRect,context:nil,hints:nil)
func ease(_ t:Double)->Double { let v=min(1,max(0,t));return v*v*(3-2*v) }
func point(_ x:Double,_ y:Double)->CGPoint { CGPoint(x:360+(x-4.115)*(38+12*y/23.77),y:536-405*y/23.77) }
func mix(_ a:CGPoint,_ b:CGPoint,_ t:Double)->CGPoint { CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t) }
func frame(_ c:CGContext,_ time:Double) {
  let chapter = Int(time/5), t = time.truncatingRemainder(dividingBy:5)/5
  func line(_ a:CGPoint,_ b:CGPoint,_ col:CGColor,_ w:Double) {
    c.beginPath(); c.move(to:a);c.addLine(to:b);c.setStrokeColor(col);c.setLineWidth(w);c.strokePath()
  }
  func oval(_ p:CGPoint,_ x:Double,_ y:Double,_ color:CGColor) { c.setFillColor(color);c.fillEllipse(in:CGRect(x:p.x-x,y:p.y-y,width:2*x,height:2*y)) }
  func rings(_ p:CGPoint,_ color:CGColor) {
    for i in 0..<3 {
      let r = 10+Double(i)*5
      c.setLineWidth(2);c.setStrokeColor(color.copy(alpha:0.85-Double(i)*0.23)!)
      c.strokeEllipse(in:CGRect(x:p.x-r,y:p.y-r*0.46,width:2*r,height:r*0.92))
    }
  }
  c.setFillColor(CGColor(red:0.035,green:0.12,blue:0.13,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height))
  let corners=[point(-1.37,0),point(9.6,0),point(9.6,23.77),point(-1.37,23.77)]
  c.beginPath();c.addLines(between:corners);c.closePath();c.setFillColor(CGColor(red:0.12,green:0.35,blue:0.30,alpha:1));c.fillPath()
  for x in [-1.37,0,8.23,9.6] {line(point(x,0),point(x,23.77),white,2)}
  for z in [0.0,23.77] {line(point(-1.37,z),point(9.6,z),white,2.5)}
  for z in [5.485,18.285] {line(point(0,z),point(8.23,z),white,2)}
  line(point(4.115,5.485),point(4.115,18.285),white,2)
  var netL=point(-1.63,11.885), netR=point(9.86,11.885);netL.y+=13;netR.y+=13
  for i in 0...80 { let p=mix(netL,netR,Double(i)/80);line(p,CGPoint(x:p.x,y:p.y-13),white.copy(alpha:0.3)!,1) }
  line(netL,netR,white,3)
  let center=point(4.15,24.7), receiver=point(chapter==3 ? 1.65:6.65,23.9)
  let runner=chapter==0 ? center : mix(center,receiver,ease((t-0.08)/0.38))
  let target = chapter==0 ? mix(point(3.5,8),point(1.3,7),ease(t/0.35))
    : point(chapter==3 ? 5.4:2.4,chapter==3 ? 7.6:1.7)
  func avatar(_ p:CGPoint,_ facing:Double,_ swing:Double,_ back:Bool) {
    let sign=back ? -1.0:1.0
    oval(p,13,4,CGColor(gray:0,alpha:0.32))
    let jersey=NSColor(calibratedRed:facing>0 ? 0.19:0.86,green:facing>0 ? 0.72:0.42,blue:facing>0 ? 0.74:0.21,alpha:1).cgColor
    let skin=CGColor(red:0.74,green:0.48,blue:0.33,alpha:1)
    for x in [-5.0,5] {line(CGPoint(x:p.x+x,y:p.y+15),CGPoint(x:p.x+x*1.65,y:p.y+2),skin,4);oval(CGPoint(x:p.x+x*1.65,y:p.y+2),4,2,white)}
    oval(CGPoint(x:p.x,y:p.y+20),8,11,jersey);oval(CGPoint(x:p.x,y:p.y+34),5.7,6.8,skin)
    let grip=CGPoint(x:p.x+sign*(12-15*swing),y:p.y+21+7*swing)
    line(CGPoint(x:p.x+5*sign,y:p.y+26),grip,skin,4)
    let tip=CGPoint(x:grip.x+sign*(9-22*swing),y:grip.y+12+6*swing)
    line(grip,tip,white,2);c.setStrokeColor(white);c.strokeEllipse(in:CGRect(x:tip.x-5,y:tip.y-1,width:10,height:14))
  }
  avatar(point(4,0),-1,chapter==1 ? ease(t/0.22):0,false)
  let hit=ease((t-0.5)/0.16)
  avatar(runner,1,hit,chapter==3)
  if chapter==0 {rings(target,blue)} else if t<0.52 {rings(receiver,yellow)} else {rings(target,purple)}
  let incomingStart=point(4,0)
  var b=chapter==0 ? runner : mix(incomingStart,receiver,ease(t/0.51))
  if t>0.52 {let u=ease((t-0.52)/0.39);b=mix(runner,target,u);b.y+=sin(u * .pi)*45}
  else {b.y+=chapter==0 ? 18+sin(t/0.52 * .pi)*35 : sin(t/0.52 * .pi)*25}
  oval(b,4.8,4.8,yellow)
  let a = chapter==0 ? center : chapter==1 ? center : receiver
  let finish = chapter==0 ? CGPoint(x:a.x-46,y:a.y+10) : chapter==1 ? receiver :
    CGPoint(x:a.x+(chapter==3 ? 24:-50),y:a.y+(chapter==3 ? 34:94))
  let progress=ease((t-(chapter<2 ? 0.02:0.28))/0.3)
  let handAt=mix(a,finish,progress)
  if t<0.69 {
    line(a,handAt,white.copy(alpha:0.55)!,4)
    if let finger { c.draw(finger,in:CGRect(x:handAt.x-4,y:handAt.y-33,width:37,height:42)) }
  }
}
for n in 0..<Int(fps)*20 {
  while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.004) }
  autoreleasepool {
    var buf:CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil,pool.pixelBufferPool!,&buf)==kCVReturnSuccess,let buf else { fatalError() }
    CVPixelBufferLockBaseAddress(buf,[]);let ctx=CGContext(data:CVPixelBufferGetBaseAddress(buf),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buf),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.noneSkipFirst.rawValue)!
    frame(ctx,Double(n)/Double(fps));CVPixelBufferUnlockBaseAddress(buf,[])
    guard pool.append(buf,withPresentationTime:CMTime(value:Int64(n),timescale:fps)) else { fatalError(String(describing:writer.error)) }
  }
}
input.markAsFinished();let done=DispatchSemaphore(value:0)
writer.finishWriting { done.signal() };done.wait()
guard writer.status == .completed else { fatalError(String(describing:writer.error)) }
