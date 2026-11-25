import SpriteKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Lettering on the player's court, with a feathered shade rather than a result card.
@MainActor final class CourtReaction: SKNode {
  private let lettering = SKNode()
  private let shade = SKSpriteNode(texture: CourtReaction.shadeTexture())
  private let words = SKLabelNode(fontNamed: "Georgia-Italic")
  private let shadow = SKLabelNode(fontNamed: "Georgia-Italic")
  private let attribution = SKLabelNode(fontNamed: "AvenirNext-Medium")
  private let tapHint = SKLabelNode(fontNamed: "AvenirNext-Medium")
  private let flourish = SKShapeNode()
  private let opponent = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
  private var lastAffirmation: TennisAffirmation?
  private var lastSmile: String?
  private var lastSize = CGSize.zero
  private var fullText = ""
  private var fullWords = NSAttributedString(string: "")
  private var fullShadow = NSAttributedString(string: "")
  private var lastVisibleCount = -1

  override init() {
    super.init()
    zPosition = 150
    addChild(lettering)
    shade.zPosition = -2
    lettering.addChild(shade)
    shadow.fontColor = .black.withAlphaComponent(0.4)
    shadow.zPosition = -1
    words.fontColor = .init(red: 1, green: 0.98, blue: 0.88, alpha: 1)
    for label in [words, shadow] {
      label.horizontalAlignmentMode = .center
      label.verticalAlignmentMode = .center
      label.numberOfLines = 0
      lettering.addChild(label)
    }
    attribution.horizontalAlignmentMode = .center
    attribution.verticalAlignmentMode = .center
    attribution.fontColor = .init(red: 1, green: 0.91, blue: 0.65, alpha: 1)
    lettering.addChild(attribution)
    tapHint.horizontalAlignmentMode = .center
    tapHint.verticalAlignmentMode = .center
    tapHint.fontSize = 10
    tapHint.fontColor = .white.withAlphaComponent(0.8)
    tapHint.text = "Tap anywhere for result"
    lettering.addChild(tapHint)
    flourish.strokeColor = attribution.fontColor!
    flourish.lineWidth = 1.3
    lettering.addChild(flourish)
    opponent.horizontalAlignmentMode = .center
    opponent.verticalAlignmentMode = .center
    opponent.fontSize = 10
    opponent.fontColor = .init(red: 1, green: 0.76, blue: 0.57, alpha: 1)
    opponent.text = "FRUSTRATED"
    addChild(opponent)
  }
  required init?(coder: NSCoder) { fatalError("Use init()") }

  func draw(_ reaction: PointReaction?, courtCenter: CGPoint, opponentPosition: CGPoint,
    width: CGFloat, courtHeight: CGFloat, elapsed: Double, reduceMotion: Bool) {
    lettering.isHidden = reaction?.affirmation == nil
    opponent.isHidden = (reaction?.frustration ?? 0) == 0
    opponent.position = CGPoint(x: opponentPosition.x, y: opponentPosition.y + 55)
    guard let reaction, let affirmation = reaction.affirmation else { return }
    let layout = CGSize(width: min(460, max(220, width - 44)), height: max(120, courtHeight))
    if lastAffirmation != affirmation || lastSmile != reaction.smile || lastSize != layout {
      arrange(affirmation, text: reaction.displayText, size: layout)
      lastAffirmation = affirmation
      lastSmile = reaction.smile
      lastSize = layout
    }
    let visible = reaction.visibleCharacterCount(at: elapsed, reduceMotion: reduceMotion)
    reveal(visible)
    attribution.isHidden = affirmation.author == nil || visible < fullText.count
    lettering.position = courtCenter
    lettering.alpha = reduceMotion ? 1 : CGFloat(min(clamp(elapsed / 0.25, 0, 1),
      clamp((reaction.duration - elapsed) / 0.3, 0, 1)))
  }

  private func arrange(_ affirmation: TennisAffirmation, text: String, size: CGSize) {
    let scale = CGFloat(clamp(Double(size.width) / 346, 0.9, 1.3))
    let base: CGFloat = affirmation.text.count > 90 ? 24 : affirmation.text.count > 45 ? 28 : 32
    words.preferredMaxLayoutWidth = size.width
    shadow.preferredMaxLayoutWidth = size.width
    setWords(text, size: base * scale)
    attribution.fontSize = 11 * scale
    attribution.text = affirmation.author.map { "— " + $0.uppercased() }
    attribution.isHidden = affirmation.author == nil
    let creditHeight: CGFloat = affirmation.author == nil ? 0 : 26 * scale
    while words.frame.height + creditHeight + 26 > size.height && words.fontSize > 15 {
      setWords(text, size: words.fontSize - 0.5)
    }
    words.position = CGPoint(x: 0, y: creditHeight / 2)
    shadow.position = CGPoint(x: 0.7, y: words.position.y - 1.5)
    attribution.position = CGPoint(x: 0, y: words.position.y - words.frame.height / 2 - 18 * scale)
    let lineY = words.position.y + words.frame.height / 2 + 16
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -22, y: lineY))
    path.addLine(to: CGPoint(x: 22, y: lineY))
    flourish.path = path
    shade.size = CGSize(width: size.width + 60,
      height: max(140, words.frame.height + creditHeight + 100))
    tapHint.position = CGPoint(x: 0, y: size.height / 2 + 40)
    fullText = text
    fullWords = words.attributedText!
    fullShadow = shadow.attributedText!
    lastVisibleCount = -1
  }

  private func reveal(_ count: Int) {
    guard count != lastVisibleCount else { return }
    lastVisibleCount = count
    // Lay out the entire quote once and hide only the unrevealed characters.
    // Lines keep their final position instead of jumping as new text arrives.
    let end = fullText.index(fullText.startIndex, offsetBy: min(count, fullText.count))
    let hidden = NSRange(end..<fullText.endIndex, in: fullText)
    for (label, source) in [(words, fullWords), (shadow, fullShadow)] {
      let text = NSMutableAttributedString(attributedString: source)
      if hidden.length > 0 { text.addAttribute(.foregroundColor, value: SKColor.clear, range: hidden) }
      label.attributedText = text
    }
  }

  private func setWords(_ text: String, size: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = 2
    #if canImport(UIKit)
    let font = UIFont(name: "Georgia-Italic", size: size) ?? UIFont.italicSystemFont(ofSize: size)
    #else
    let font = NSFont(name: "Georgia-Italic", size: size) ?? NSFont.systemFont(ofSize: size)
    #endif
    for label in [words, shadow] {
      label.fontSize = size
      label.attributedText = NSAttributedString(string: text,
        attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: label.fontColor!])
    }
  }

  private static func shadeTexture() -> SKTexture {
    let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
      bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors = [CGColor(gray: 0, alpha: 0.52), CGColor(gray: 0, alpha: 0.28),
      CGColor(gray: 0, alpha: 0)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
      locations: [0, 0.5, 1])!
    context.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
      endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
    let texture = SKTexture(cgImage: context.makeImage()!)
    texture.filteringMode = .linear
    return texture
  }
}
