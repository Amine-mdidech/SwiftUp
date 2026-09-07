import Testing
import Foundation
@testable import SwiftUp

struct ModelDecodingTests {
    @Test func decodesMultipleChoiceQuestion() throws {
        let json = """
        {
          "id": "q1", "topic": "Concurrency", "format": "multipleChoice",
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
}
