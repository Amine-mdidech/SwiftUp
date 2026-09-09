import Testing
import Foundation
@testable import SwiftUp

private func makeQuestion(_ id: String, level: SkillLevel = .junior) -> Question {
    Question(
        id: id, topic: "Test", level: level, format: .multipleChoice,
        prompt: "Prompt \(id)", codeSnippet: nil,
        options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
        correctOptionID: "A", explanation: "Because.", xp: 15
    )
}

struct QuestionSelectorTests {
    @Test func shouldPromoteWhenEveryQuestionAnswered() {
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let answered: [String: Date] = ["q1": .now, "q2": .now, "q3": .now]
        #expect(QuestionSelector.shouldPromote(bank: bank, answered: answered))
    }

    @Test func shouldNotPromoteWhenSomeUnanswered() {
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let answered: [String: Date] = ["q1": .now]
        #expect(!QuestionSelector.shouldPromote(bank: bank, answered: answered))
    }

    @Test func shouldNotPromoteEmptyBank() {
        #expect(!QuestionSelector.shouldPromote(bank: [], answered: [:]))
    }

    @Test func pickFivePicksAllUnseenWhenNoneAnswered() {
        let bank = (1...10).map { makeQuestion("q\($0)") }
        let picks = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "seed-a")
        #expect(picks.count == 5)
        #expect(Set(picks.map(\.id)).count == 5)
    }

    @Test func pickFiveIncludesExactlyOneOldestRepeatWhenEnoughUnseenExist() {
        let bank = (1...10).map { makeQuestion("q\($0)") }
        let now = Date()
        let answered: [String: Date] = [
            "q1": now.addingTimeInterval(-1000),
            "q2": now.addingTimeInterval(-500),
        ]
        let picks = QuestionSelector.pickFive(bank: bank, answered: answered, seed: "seed-b")
        #expect(picks.count == 5)
        let pickedIDs = Set(picks.map(\.id))
        // Exactly one of the two previously-answered questions should appear — the oldest one (q1).
        #expect(pickedIDs.contains("q1"))
        #expect(!pickedIDs.contains("q2"))
        // The other 4 are unseen.
        let unseenPicks = pickedIDs.subtracting(["q1"])
        #expect(unseenPicks.allSatisfy { !answered.keys.contains($0) })
        #expect(unseenPicks.count == 4)
    }

    @Test func pickFiveFillsFromRepeatsWhenFewerThanFourUnseen() {
        // Bank of 3, 1 unseen, 2 answered — can't get 4 new, so it should fill from repeats
        // rather than returning fewer than 5.
        let bank = (1...3).map { makeQuestion("q\($0)") }
        let now = Date()
        let answered: [String: Date] = [
            "q1": now.addingTimeInterval(-1000),
            "q2": now.addingTimeInterval(-500),
        ]
        let picks = QuestionSelector.pickFive(bank: bank, answered: answered, seed: "seed-c")
        #expect(picks.count == 3) // can't exceed bank size
        #expect(Set(picks.map(\.id)) == Set(["q1", "q2", "q3"]))
    }

    @Test func pickFiveIsDeterministicForSameSeed() {
        let bank = (1...10).map { makeQuestion("q\($0)") }
        let picksA = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "same-seed")
        let picksB = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "same-seed")
        #expect(picksA.map(\.id) == picksB.map(\.id))
    }

    @Test func pickFiveDiffersForDifferentSeeds() {
        let bank = (1...20).map { makeQuestion("q\($0)") }
        let picksA = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "seed-x")
        let picksB = QuestionSelector.pickFive(bank: bank, answered: [:], seed: "seed-y")
        #expect(picksA.map(\.id) != picksB.map(\.id))
    }

    @Test func todaySeedIsStableForSameDayAndDiffersByUID() {
        let date = Date()
        let seedA = QuestionSelector.todaySeed(uid: "user-a", level: .junior, date: date)
        let seedB = QuestionSelector.todaySeed(uid: "user-b", level: .junior, date: date)
        #expect(seedA != seedB)
        // Same uid/level/date -> same seed, called twice.
        let seedA2 = QuestionSelector.todaySeed(uid: "user-a", level: .junior, date: date)
        #expect(seedA == seedA2)
    }

    @Test func todaySeedDiffersByLevel() {
        let date = Date()
        let juniorSeed = QuestionSelector.todaySeed(uid: "user-a", level: .junior, date: date)
        let midSeed = QuestionSelector.todaySeed(uid: "user-a", level: .mid, date: date)
        #expect(juniorSeed != midSeed)
    }
}
