import Testing
@testable import SwiftUp

private let testLadder = [
    LevelInfo(number: 1, title: "Swift Novice", xpThreshold: 0),
    LevelInfo(number: 2, title: "Optional Handler", xpThreshold: 150),
    LevelInfo(number: 3, title: "Protocol Wrangler", xpThreshold: 400),
]

struct LevelCalculatorTests {
    @Test func zeroXPIsLevelOne() {
        let result = LevelCalculator.level(for: 0, ladder: testLadder)
        #expect(result.number == 1)
        #expect(result.title == "Swift Novice")
        #expect(result.xpForCurrentLevel == 0)
        #expect(result.xpForNextLevel == 150)
    }

    @Test func midLevelBand() {
        let result = LevelCalculator.level(for: 200, ladder: testLadder)
        #expect(result.number == 2)
        #expect(result.title == "Optional Handler")
        #expect(result.xpForCurrentLevel == 150)
        #expect(result.xpForNextLevel == 400)
    }

    @Test func exactlyAtThreshold() {
        let result = LevelCalculator.level(for: 400, ladder: testLadder)
        #expect(result.number == 3)
    }

    @Test func aboveCeilingStaysAtTopLevel() {
        let result = LevelCalculator.level(for: 999_999, ladder: testLadder)
        #expect(result.number == 3)
        #expect(result.title == "Protocol Wrangler")
        #expect(result.xpForCurrentLevel == 400)
        #expect(result.xpForNextLevel == 400) // no level above 3 — matches "xp to next level" clamping at 0
    }

    @Test func emptyLadderFallsBackToLevelOne() {
        let result = LevelCalculator.level(for: 500, ladder: [])
        #expect(result.number == 1)
        #expect(result.xpForCurrentLevel == 0)
        #expect(result.xpForNextLevel == 0)
    }
}
