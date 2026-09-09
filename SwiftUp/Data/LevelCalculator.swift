import Foundation

enum LevelCalculator {
    /// Finds the highest level whose threshold the given XP total has reached.
    /// `xpForNextLevel` equals `xpForCurrentLevel` at the ladder's ceiling (level 12), so
    /// `UserProfile.xpToNextLevel`'s `max(0, ...)` clamp reads that as "maxed out," not negative.
    static func level(for totalXP: Int, ladder: [LevelInfo]) -> (number: Int, title: String, xpForCurrentLevel: Int, xpForNextLevel: Int) {
        let sorted = ladder.sorted { $0.number < $1.number }
        guard let first = sorted.first else {
            return (number: 1, title: "", xpForCurrentLevel: 0, xpForNextLevel: 0)
        }
        var current = first
        for level in sorted where level.xpThreshold <= totalXP {
            current = level
        }
        let next = sorted.first { $0.number == current.number + 1 }
        return (
            number: current.number,
            title: current.title,
            xpForCurrentLevel: current.xpThreshold,
            xpForNextLevel: next?.xpThreshold ?? current.xpThreshold
        )
    }
}
