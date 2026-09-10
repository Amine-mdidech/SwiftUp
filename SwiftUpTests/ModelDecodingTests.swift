import Testing
import Foundation
@testable import SwiftUp

struct ModelDecodingTests {
    @Test func decodesMultipleChoiceQuestion() throws {
        let json = """
        {
          "id": "q1", "topic": "Concurrency", "level": "Mid", "format": "multipleChoice",
          "prompt": "What does it not inherit?", "codeSnippet": null,
          "options": [{"id": "A", "text": "Actor context"}, {"id": "B", "text": "Cancellation"}],
          "correctOptionID": "A", "explanation": "Because.", "xp": 15
        }
        """.data(using: .utf8)!
        let q = try JSONDecoder().decode(Question.self, from: json)
        #expect(q.format == .multipleChoice)
        #expect(q.options.count == 2)
        #expect(q.correctOptionID == "A")
    }

    @Test func decodesAchievementWithSealKind() throws {
        let json = """
        {
          "id": "a1", "title": "Perfect week", "detail": "Six of seven days",
          "sealKind": "perfectWeek", "status": "earned", "xpReward": 200,
          "earnedDateDisplay": "7 Sep", "progressCurrent": null, "progressTarget": null
        }
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(Achievement.self, from: json)
        #expect(a.sealKind == .perfectWeek)
        #expect(a.status == .earned)
    }

    @Test func decodesUserProfile() throws {
        let json = """
        {
          "name": "Maya Reyes", "initials": "MR", "level": 7,
          "levelTitle": "Concurrency Compositor", "xp": 3240,
          "xpForCurrentLevel": 2200, "xpForNextLevel": 3700,
          "streakDays": 42, "freezesAvailable": 1, "freezesTotal": 3,
          "answeredCount": 585, "accuracyPercent": 81,
          "memberSinceDisplay": "Since 14 May"
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(p.xpToNextLevel == 460)
    }

    @Test func decodesDailyQuizDocumentAndLooksUpByLevel() throws {
        func question(_ id: String, level: String) -> String {
            """
            {"id": "\(id)", "topic": "Test", "level": "\(level)", "format": "multipleChoice",
             "prompt": "P", "codeSnippet": null,
             "options": [{"id": "A", "text": "A"}], "correctOptionID": "A", "explanation": "E", "xp": 10}
            """
        }
        let json = """
        {
          "edition": 4,
          "junior": [\(question("jr1", level: "Junior"))],
          "mid": [\(question("mid1", level: "Mid"))],
          "senior": [\(question("sr1", level: "Senior"))]
        }
        """.data(using: .utf8)!
        let doc = try JSONDecoder().decode(DailyQuizDocument.self, from: json)
        #expect(doc.edition == 4)
        #expect(doc.questions(for: .junior).map(\.id) == ["jr1"])
        #expect(doc.questions(for: .mid).map(\.id) == ["mid1"])
        #expect(doc.questions(for: .senior).map(\.id) == ["sr1"])
    }

    @Test func decodesAchievementDefinitionWithCriterion() throws {
        let json = """
        {
          "id": "a03", "title": "Concurrency, mastered", "detail": "90% across 40 questions in one topic",
          "sealKind": "topicMastery", "xpReward": 250,
          "criterion": {"kind": "topicMastery", "topic": "Concurrency", "minAccuracy": 90, "minAnswered": 40, "count": null, "days": null}
        }
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(AchievementDefinition.self, from: json)
        #expect(d.criterion.kind == "topicMastery")
        #expect(d.criterion.topic == "Concurrency")
        #expect(d.criterion.minAccuracy == 90)
    }
}
