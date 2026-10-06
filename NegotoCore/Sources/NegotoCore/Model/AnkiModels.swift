import Foundation

public struct NoteField: Hashable, Sendable {
    public var name: String
    public var ord: Int
}

public struct CardTemplate: Hashable, Sendable {
    public var name: String
    public var ord: Int
    public var questionFormat: String
    public var answerFormat: String
}

public struct Notetype: Identifiable, Sendable {
    public enum Kind: Int, Sendable { case normal = 0, cloze = 1 }

    public var id: Int64
    public var name: String
    public var kind: Kind
    public var css: String
    public var fields: [NoteField]
    public var templates: [CardTemplate]
    public var sortFieldIndex: Int
    public var latexPre: String
    public var latexPost: String
    public var latexSvg: Bool

    public var isCloze: Bool { kind == .cloze }

    public func template(forCardOrd ord: Int) -> CardTemplate? {
        if isCloze { return templates.first }
        return templates.first(where: { $0.ord == ord }) ?? (ord < templates.count ? templates[ord] : nil)
    }

    public var fieldNames: [String] { fields.sorted { $0.ord < $1.ord }.map(\.name) }
}

public struct Deck: Identifiable, Hashable, Sendable {
    public var id: Int64
    /// Full name using "::" as the separator.
    public var name: String
    public var configId: Int64
    public var isFiltered: Bool
    public var description: String
    /// Per-deck overrides of the preset limits (Anki ≥2.1.55).
    public var newLimit: Int?
    public var reviewLimit: Int?
    /// Today's extra cards from custom study: (day number, extra new, extra reviews).
    public var extendDay: Int? = nil
    public var extendNew: Int = 0
    public var extendReview: Int = 0

    public var components: [String] { name.components(separatedBy: "::") }
    public var baseName: String { components.last ?? name }
    public var depth: Int { components.count - 1 }
    public var parentName: String? {
        let c = components
        return c.count > 1 ? c.dropLast().joined(separator: "::") : nil
    }
}

public struct DeckConfig: Identifiable, Sendable {
    public enum LeechAction: Int, Sendable { case suspend = 0, tagOnly = 1 }
    public enum NewMix: Int, Sendable { case mixWithReviews = 0, afterReviews = 1, beforeReviews = 2 }

    public var id: Int64
    public var name: String
    /// Minutes.
    public var learnSteps: [Double] = [1, 10]
    public var relearnSteps: [Double] = [10]
    public var newPerDay: Int = 20
    public var reviewsPerDay: Int = 200
    public var initialEase: Double = 2.5
    public var easyMultiplier: Double = 1.3
    public var hardMultiplier: Double = 1.2
    public var lapseMultiplier: Double = 0.0
    public var intervalMultiplier: Double = 1.0
    public var maximumReviewInterval: Int = 36500
    public var minimumLapseInterval: Int = 1
    public var graduatingIntervalGood: Int = 1
    public var graduatingIntervalEasy: Int = 4
    public var leechAction: LeechAction = .tagOnly
    public var leechThreshold: Int = 8
    public var disableAutoplay: Bool = false
    public var capAnswerTimeToSecs: Int = 60
    public var skipQuestionWhenReplayingAnswer: Bool = false
    public var buryNew: Bool = false
    public var buryReviews: Bool = false
    public var buryInterdayLearning: Bool = false
    public var newMix: NewMix = .mixWithReviews
    public var desiredRetention: Double = 0.9
    public var fsrsParams: [Double] = []

    public init(id: Int64, name: String) {
        self.id = id
        self.name = name
    }

    public static let `default` = DeckConfig(id: 1, name: "Default")
}

public struct Card: Identifiable, Hashable, Sendable {
    public enum CardType: Int, Sendable { case new = 0, learning = 1, review = 2, relearning = 3 }
    public enum Queue: Int, Sendable {
        case userBuried = -3, schedBuried = -2, suspended = -1
        case new = 0, learning = 1, review = 2, dayLearning = 3, preview = 4
    }

    public var id: Int64
    public var noteId: Int64
    public var deckId: Int64
    public var ord: Int
    public var mod: Int64
    public var usn: Int
    public var type: Int
    public var queue: Int
    public var due: Int64
    public var interval: Int
    public var factor: Int
    public var reps: Int
    public var lapses: Int
    public var left: Int
    public var originalDue: Int64
    public var originalDeckId: Int64
    public var flags: Int
    public var data: String

    public var cardType: CardType { CardType(rawValue: type) ?? .new }
    public var cardQueue: Queue { Queue(rawValue: queue) ?? .new }
    public var userFlag: Int { flags & 0b111 }

    /// FSRS memory state stored in `cards.data` by Anki ≥23.10.
    public var memoryState: (stability: Double, difficulty: Double)? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let s = (obj["s"] as? NSNumber)?.doubleValue, let d = (obj["d"] as? NSNumber)?.doubleValue
        else { return nil }
        return (s, d)
    }

    /// Unix seconds of the last review (Anki ≥24.11 stores it as "lrt").
    public var lastReviewTime: Int64? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else { return nil }
        return (obj["lrt"] as? NSNumber)?.int64Value
    }
}

public struct Note: Identifiable, Hashable, Sendable {
    public var id: Int64
    public var guid: String
    public var notetypeId: Int64
    public var mod: Int64
    public var tags: [String]
    public var fields: [String]

    public static func splitFields(_ flds: String) -> [String] {
        flds.components(separatedBy: "\u{1f}")
    }

    public static func splitTags(_ tags: String) -> [String] {
        tags.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
    }
}

public struct RevlogEntry: Sendable {
    public var id: Int64
    public var cardId: Int64
    public var usn: Int
    /// 1–4.
    public var ease: Int
    public var interval: Int
    public var lastInterval: Int
    public var factor: Int
    public var time: Int
    /// 0 learn, 1 review, 2 relearn, 3 filtered/cram, 4 manual, 5 rescheduled.
    public var type: Int
}
