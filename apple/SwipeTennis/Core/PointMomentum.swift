import Foundation

struct TennisAffirmation: Codable, Equatable {
  let text: String
  var author: String? = nil
  /// A short reset still gets a calm pause; longer quotes get up to eight seconds.
  var readingDuration: Double {
    let wordCount = (text + " " + (author ?? "")).split(whereSeparator: \.isWhitespace).count
    return clamp(1.4 + Double(wordCount) / 3, 4, 8)
  }
  // The player's requested collection; supplied attributions are retained.
  static let all: [TennisAffirmation] = [
    .init(text: "Next point, fresh start."),
    .init(text: "I control my effort, my feet, and my attitude."),
    .init(text: "Make them earn every single point."),
    .init(text: "Pressure is a privilege."),
    .init(text: "Stay loose, breathe out."),
    .init(text: "It’s not over until the last ball bounces twice."),
    .init(text: "I will find a way!"),
    .init(text: "Heavy topspin, big targets."),
    .init(text: "Love the battle."),
    .init(text: "Split step, watch the contact."),
    .init(text: "She still has to close it out."),
    .init(text: "Trust the work I’ve put in."),
    .init(text: "Losing is not my enemy; fear of losing is my enemy", author: "Rafa"),
    .init(text: "The next point—that’s all I must think about.", author: "Laver"),
    .init(text: "Regardless of how I feel on the inside, I have to look like a winner on the outside.", author: "Arthur Ashe"),
    .init(text: "What matters isn't how well I play when I'm playing well; it's how well I play when I'm playing badly.", author: "Federer"),
    .init(text: "I must believe in myself when no one else does.", author: "Venus"),
    .init(text: "A champion is defined not by their wins, but by how they can recover when they fall.", author: "Serena Williams"),
    .init(text: "The key is to stay loose, relaxed, and maintain your focus under pressure.", author: "Chris Evert"),
    .init(text: "Champions keep playing until they get it right.", author: "Billie Jean King"),
    .init(text: "It's those who can mentally cope with the most stressful moments who are the champions.", author: "Iga Świątek"),
    .init(text: "The mark of great sportsmen is not how good they are at their best, but how good they are at their worst.", author: "Martina Navratilova"),
    .init(text: "I never look back, I look forward.", author: "Steffi Graf"),
    .init(text: "Any problem you overcome will carry you forward in the future and give you new strength.", author: "Steffi Graf"),
    .init(text: "Lighten up, look up, smile, and enjoy the opportunity—don't be fearful of the occasion.", author: "Ashleigh Barty"),
    .init(text: "There’s no right way, there’s no wrong way, there’s just my way.", author: "Ashleigh Barty")
  ]
}

struct PointReaction: Codable {
  static let smiles = ["🙂", "😊", "😄", "😁", "😌", "😎", "🤗", "☺️"]
  var affirmation: TennisAffirmation?
  var smile = "🙂"
  var frustration = 0
  var duration: Double { affirmation?.readingDuration ?? 2 }

  var displayText: String {
    guard let affirmation else { return "" }
    let message = affirmation.text.count <= 45
      ? affirmation.text.replacingOccurrences(of: ", ", with: ",\n") : affirmation.text
    return message + "\u{00a0}" + smile
  }

  /// Reveal complete characters (including emoji), leaving time to read within the existing cap.
  func visibleCharacterCount(at elapsed: Double, reduceMotion: Bool = false) -> Int {
    let count = displayText.count
    guard !reduceMotion else { return count }
    let streamingDuration = clamp(Double(count) / 38, 0.8, 2.8)
    return Int(Double(count) * clamp((elapsed - 0.15) / streamingDuration, 0, 1))
  }
}

struct PointMomentum: Codable {
  private(set) var winsInRow = 0
  private(set) var lossesInRow = 0
  private var affirmationGame: Int?
  private var lastAffirmationIndex: Int?
  private var lastSmileIndex: Int?
  // Optional for saved matches from before the opponent's cooldown was introduced.
  var gamesUntilReaction: Int?

  mutating func completedOpponentGame() {
    if let remaining = gamesUntilReaction { gamesUntilReaction = max(0, remaining - 1) }
  }

  mutating func finishPoint(winner: Int, game: Int, againstOpponent: Bool,
    random: () -> Double) -> PointReaction? {
    if winner == 0 {
      winsInRow += 1; lossesInRow = 0
      guard againstOpponent, winsInRow >= 2, (gamesUntilReaction ?? 0) == 0,
        random() < 0.5 else { return nil }
      gamesUntilReaction = random() < 0.5 ? 2 : 3
      return PointReaction(frustration: 1)
    }
    lossesInRow += 1; winsInRow = 0
    guard lossesInRow >= 2, affirmationGame != game else { return nil }
    let choices = TennisAffirmation.all.indices.filter { $0 != lastAffirmationIndex }
    let index = choices[Int(clamp(random(), 0, 0.999999) * Double(choices.count))]
    let smiles = PointReaction.smiles.indices.filter { $0 != lastSmileIndex }
    let smileIndex = smiles[Int(clamp(random(), 0, 0.999999) * Double(smiles.count))]
    affirmationGame = game
    lastAffirmationIndex = index
    lastSmileIndex = smileIndex
    return PointReaction(affirmation: TennisAffirmation.all[index], smile: PointReaction.smiles[smileIndex])
  }
}
