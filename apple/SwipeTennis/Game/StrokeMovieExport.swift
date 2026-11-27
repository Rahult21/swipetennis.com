import AVFoundation
import RealityKit
import SwiftUI

/// Exports fixed intervals from the same RealityKit court, pose recording and
/// camera as the studio. Render time never changes the exported playback rate.
@MainActor final class StrokeMovieExport: ObservableObject {
  @Published private(set) var fraction: Double?
  @Published private(set) var movie: URL?
  @Published private(set) var message: String?
  weak var court: CourtReplayView?
  private var writer: AVAssetWriter?
  private var ticket = UUID()
  private var output: URL?
  private var watchdog: Task<Void,Never>?
  private var lastFrame: TimeInterval = 0
  var busy: Bool { fraction != nil }

  func clear() {
    cancel()
    movie = nil; message = nil
  }

  func cancel() {
    ticket = UUID()
    watchdog?.cancel(); watchdog = nil
    if let writer, writer.status == .writing { writer.cancelWriting() }
    if let output { try? FileManager.default.removeItem(at:output) }
    output = nil; writer = nil; fraction = nil
  }

  func export(clip: StrokeStudioClip, stroke: StudioStroke, azimuth: Float) {
    clear()
    guard let court, let contact = clip.frame(clip.contactTime) else { return }
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Stroke Studio",isDirectory:true)
      try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
      let dayAgo = Date.now.addingTimeInterval(-86_400)
      for file in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey])
        where (try? file.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantFuture < dayAgo {
        try? FileManager.default.removeItem(at:file)
      }
      let url = directory.appendingPathComponent(stroke.rawValue+"-"+UUID().uuidString+".mp4")
      let width = 768, height = 724, fps: Int32 = 30
      let movie = try AVAssetWriter(outputURL:url,fileType:.mp4)
      let input = AVAssetWriterInput(mediaType:.video,outputSettings:[
        AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,
        AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:3_800_000,AVVideoExpectedSourceFrameRateKey:fps]
      ])
      let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
        kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:width,
        kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String:true
      ])
      guard movie.canAdd(input) else { throw ExportFailure.encoding }
      movie.add(input); guard movie.startWriting() else { throw movie.error ?? ExportFailure.encoding }
      writer = movie; output = url; fraction = 0
      movie.startSession(atSourceTime:.zero)
      let count = Int(ceil(clip.duration/PointReplay.speed*Double(fps)))+1
      lastFrame = ProcessInfo.processInfo.systemUptime
      watchdog = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for:.seconds(3))
          guard !Task.isCancelled, let self, self.busy else { return }
          if ProcessInfo.processInfo.systemUptime-self.lastFrame > 18 {
            self.fail(ExportFailure.encoding); return
          }
        }
      }
      let id = ticket, origin = (contact.near[.leftHip]+contact.near[.rightHip])*0.5
      func render(_ index: Int) {
        guard ticket == id else { return }
        guard movie.status == .writing else { fail(movie.error ?? ExportFailure.encoding); return }
        if index == count {
          input.markAsFinished()
          movie.finishWriting { [weak self] in
            Task { @MainActor in
              guard let self, self.ticket == id else { return }
              guard self.writer?.status == .completed else { self.fail(self.writer?.error ?? ExportFailure.encoding); return }
              self.watchdog?.cancel(); self.watchdog = nil
              self.output = nil; self.writer = nil; self.fraction = nil; self.movie = url
            }
          }
          return
        }
        if !input.isReadyForMoreMediaData {
          Task { @MainActor in try? await Task.sleep(for:.milliseconds(16)); render(index) }
          return
        }
        let t = min(clip.duration,Double(index)*PointReplay.speed/Double(fps))
        guard let frame = clip.frame(t) else { fail(ExportFailure.encoding); return }
        court.drawStudio(frame,origin:origin,azimuth:azimuth,stroke:stroke)
        court.whenFrameIsReady { [weak self] image in
          guard let self, self.ticket == id else { return }
          guard let cg = image.cgImage, let pool = pixels.pixelBufferPool else { self.fail(ExportFailure.encoding); return }
          var buffer: CVPixelBuffer?
          guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer) == kCVReturnSuccess, let buffer,
            Self.draw(cg,to:buffer,width:width,height:height),
            pixels.append(buffer,withPresentationTime:CMTime(value:Int64(index),timescale:fps))
            else { self.fail(movie.error ?? ExportFailure.encoding); return }
          self.lastFrame = ProcessInfo.processInfo.systemUptime
          let progress = Double(index+1)/Double(count)
          if progress-(self.fraction ?? 0)>=0.025 { self.fraction = progress }
          render(index+1)
        }
      }
      render(0)
    } catch { fail(error) }
  }

  private func fail(_ error: Error) { cancel(); message = error.localizedDescription }
  private enum ExportFailure: LocalizedError {
    case encoding
    var errorDescription: String? { "The video could not be written. Try exporting again." }
  }
  private static func draw(_ image: CGImage, to pixel: CVPixelBuffer, width: Int, height: Int) -> Bool {
    guard CVPixelBufferLockBaseAddress(pixel,[]) == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(pixel,[]) }
    let format = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard let context = CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:width,height:height,bitsPerComponent:8,
      bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:format) else { return false }
    context.interpolationQuality = .high
    context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
    return true
  }
}
