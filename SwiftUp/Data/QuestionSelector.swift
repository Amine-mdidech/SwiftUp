import Foundation

enum QuestionSelector {
    /// True once every question in the bank has been answered — the trigger for skill-level promotion.
    static func shouldPromote(bank: [Question], answered: [String: Date]) -> Bool {
        guard !bank.isEmpty else { return false }
        return bank.allSatisfy { answered[$0.id] != nil }
    }

    /// Picks today's 5: up to 4 never-answered questions (seeded, so stable for a given seed),
    /// plus 1 repeat — the answered question with the oldest timestamp. If fewer than 4 unseen
    /// questions exist, fills the remaining slots from the answered pool (oldest first) instead
    /// of returning fewer than requested — the "4 new" target relaxes gracefully when the bank
    /// is small relative to how much the user has already answered.
    static func pickFive(bank: [Question], answered: [String: Date], seed: String) -> [Question] {
        let unseen = bank.filter { answered[$0.id] == nil }
        let seenOldestFirst = bank
            .filter { answered[$0.id] != nil }
            .sorted { answered[$0.id]! < answered[$1.id]! }

        var generator = StableSeededGenerator(seed: seed)
        let shuffledUnseen = unseen.shuffled(using: &generator)

        var picks = Array(shuffledUnseen.prefix(4))
        let target = min(5, bank.count)
        if picks.count < target {
            picks.append(contentsOf: seenOldestFirst.prefix(target - picks.count))
        }
        if picks.count < target {
            // Still short (fewer than 4 unseen AND fewer repeats than needed to make up the
            // difference) — fall back to remaining unseen questions not already picked.
            let alreadyPicked = Set(picks.map(\.id))
            let leftoverUnseen = shuffledUnseen.filter { !alreadyPicked.contains($0.id) }
            picks.append(contentsOf: leftoverUnseen.prefix(target - picks.count))
        }
        return picks
    }

    /// A seed that's stable across app launches (unlike Swift's randomized String.hashValue)
    /// for a given user/level/day, and changes at the next calendar day.
    static func todaySeed(uid: String, level: SkillLevel, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(uid)-\(level.rawValue)-\(formatter.string(from: date))"
    }
}

/// A deterministic RandomNumberGenerator seeded by a string, using FNV-1a (not Swift's
/// String.hashValue, which is randomized per-process and would silently break "same 5
/// questions all day" every time the app relaunches).
private struct StableSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash == 0 ? 0x9E3779B97F4A7C15 : hash
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
