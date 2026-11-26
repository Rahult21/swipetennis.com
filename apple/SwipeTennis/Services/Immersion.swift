import AVFoundation
import CoreHaptics
import CoreMotion
import GameController
import UIKit

@MainActor final class Immersion {
  static let shared = Immersion()
  private var haptics: CHHapticEngine?
  private let speech = AVSpeechSynthesizer()
  private var crowd: AVAudioPlayer?
  private var audio: [AVAudioPlayer] = []
  private let motion = CMMotionManager()
  private var neutral: (Double, Double)?
  var tilt = Vec.zero
  var motionAvailable: Bool { motion.isDeviceMotionAvailable }
  var soundEnabled: Bool { UserDefaults.standard.object(forKey: "sound") as? Bool ?? true }
  var hapticsEnabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
  var volume: Float { Float(UserDefaults.standard.object(forKey: "courtVolume") as? Double ?? 0.3) }
  private var audioActive = false
  private init() {
    // This update restores audible play once; later user mute/volume choices are retained.
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "courtAudioV2") {
      defaults.set(true, forKey: "sound")
      defaults.set(0.3, forKey: "courtVolume")
      defaults.set(true, forKey: "courtAudioV2")
    }
    defaults.removeObject(forKey: "grunts")
  }

  private func activateAudio() {
    guard !audioActive else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      audioActive = true
    } catch { audioActive = false }
  }

  func prepareAudio() {
    guard audio.isEmpty else { return }
    guard let url = Bundle.main.url(forResource: "hit", withExtension: "wav") else { return }
    audio = (0..<3).compactMap { _ in
      guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
      player.prepareToPlay()
      return player
    }
  }

  func cheer() {
    guard soundEnabled, let url = Bundle.main.url(forResource: "crowd", withExtension: "wav") else { return }
    activateAudio()
    if crowd == nil { crowd = try? AVAudioPlayer(contentsOf: url) }
    crowd?.volume = volume * 0.65
    crowd?.currentTime = 0
    crowd?.play()
  }

  func playHit(x: Double, gain: Double) {
    guard soundEnabled else { return }
    activateAudio()
    prepareAudio()
    guard let player = audio.first(where: { !$0.isPlaying }) ?? audio.first else { return }
    player.pan = Float(clamp(x / 4.115 - 1, -0.85, 0.85))
    player.volume = volume * 0.5 * Float(gain)
    player.currentTime = 0
    player.play()
  }

  func hit(bounce: Bool = false, x: Double = 4.115, gain: Double = 1) {
    if hapticsEnabled {
      if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
        do {
          if haptics == nil {
            haptics = try CHHapticEngine()
            haptics?.isAutoShutdownEnabled = true
            haptics?.resetHandler = { [weak self] in Task { @MainActor in self?.haptics = nil } }
          }
          try haptics?.start()
          let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
              .init(parameterID: .hapticIntensity, value: bounce ? 0.25 : 0.75),
              .init(parameterID: .hapticSharpness, value: bounce ? 0.15 : 0.8),
            ], relativeTime: 0)
          try haptics?.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(
            atTime: 0)
        } catch { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      } else {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      }
    }
    // Only racket contact plays audio; court bounces retain their tactile feedback.
    if !bounce { playHit(x: x, gain: gain) }
  }

  func point(_ text: String) {
    if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    if UserDefaults.standard.bool(forKey: "voice") {
      speech.stopSpeaking(at: .immediate)
      let utterance = AVSpeechUtterance(string: text)
      utterance.rate = 0.48
      speech.speak(utterance)
    }
  }
  func startMotion() {
    guard motion.isDeviceMotionAvailable else { return }
    neutral = nil
    motion.deviceMotionUpdateInterval = 1 / 60
    motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
      guard let data else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        let roll = data.attitude.roll
        let pitch = data.attitude.pitch
        if self.neutral == nil { self.neutral = (roll, pitch) }
        let n = self.neutral!
        self.tilt = Vec(x: clamp((roll - n.0) * 4, -1, 1), y: clamp((pitch - n.1) * 4, -1, 1))
      }
    }
  }
  func finishRally() {
    motion.stopDeviceMotionUpdates()
    tilt = .zero
    neutral = nil
  }
  func stop() {
    finishRally()
    speech.stopSpeaking(at: .immediate)
    audio.forEach { $0.stop() }
    crowd?.stop()
    if audioActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    audioActive = false
    haptics?.stop()
  }
}
