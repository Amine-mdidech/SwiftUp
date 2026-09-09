import Foundation
import FirebaseFirestore

@Observable
final class QuestionRepository {
    private(set) var todayQuestions: [Question] = []
    private(set) var isLoading = false
    private(set) var levelOverride: SkillLevel?

    init() {}

    /// Synchronously loads the bundled fallback set — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> QuestionRepository {
        let repo = QuestionRepository()
        repo.todayQuestions = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [Question] {
        decodeJSONResource([Question].self, filename: "questions", bundle: bundle) ?? []
    }

    /// Fetches today's five for `uid`: reads their skill level/override/answer-history from
    /// Firestore, fetches that level's bank, promotes if it's exhausted, and runs
    /// QuestionSelector. Falls back to the bundled set only if Firestore is unreachable with
    /// nothing cached locally yet.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userDoc = Firestore.firestore().collection("users").document(uid)

        var storedLevel = SkillLevel.junior
        var override: SkillLevel?
        var answered: [String: Date] = [:]

        do {
            let snapshot = try await userDoc.getDocument()
            if let raw = snapshot.get("skillLevel") as? String, let level = SkillLevel(rawValue: raw) {
                storedLevel = level
            }
            if let raw = snapshot.get("levelOverride") as? String, let level = SkillLevel(rawValue: raw) {
                override = level
            }
            if let map = snapshot.get("answeredQuestionIDs") as? [String: Timestamp] {
                answered = map.mapValues { $0.dateValue() }
            }
        } catch {
            // No user doc data available (offline, first launch) — proceed with defaults;
            // the Firestore question fetch below will fall back to bundled JSON if it also fails.
        }

        levelOverride = override
        let effectiveLevel = override ?? storedLevel

        guard var bank = try? await fetchBank(level: effectiveLevel), !bank.isEmpty else {
            todayQuestions = Self.loadBundledFallback()
            return
        }

        var selectionLevel = effectiveLevel
        if QuestionSelector.shouldPromote(bank: bank, answered: answered), let next = effectiveLevel.next {
            if let nextBank = try? await fetchBank(level: next), !nextBank.isEmpty {
                bank = nextBank
                selectionLevel = next
                storedLevel = next
                try? await userDoc.updateData(["skillLevel": next.rawValue])
            }
        }

        let seed = QuestionSelector.todaySeed(uid: uid, level: selectionLevel)
        todayQuestions = QuestionSelector.pickFive(bank: bank, answered: answered, seed: seed)
    }

    private func fetchBank(level: SkillLevel) async throws -> [Question] {
        let snapshot = try await Firestore.firestore()
            .collection("questions")
            .whereField("level", isEqualTo: level.rawValue)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Question.self) }
    }

    /// Called once, right after onboarding's skill assessment.
    func saveInitialSkillLevel(_ level: SkillLevel, for uid: String) async {
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["skillLevel": level.rawValue], merge: true)
        } catch {
            // Non-blocking, matches AuthRepository's write-failure pattern — retried lazily
            // next time load(for:) runs, since it just re-reads whatever's there.
        }
    }

    /// Called from Settings when the user picks a specific difficulty, or clears back to "Adaptive".
    func setLevelOverride(_ level: SkillLevel?, for uid: String) async {
        levelOverride = level
        do {
            try await Firestore.firestore().collection("users").document(uid)
                .setData(["levelOverride": level?.rawValue as Any], merge: true)
        } catch {
            // Non-blocking.
        }
    }

    /// Records today's five as answered (seen), so they're excluded from future "unseen" picks.
    func recordAnswered(_ questions: [Question], for uid: String) async {
        guard !questions.isEmpty else { return }
        var updates: [String: Any] = [:]
        let now = Timestamp(date: Date())
        for question in questions {
            updates["answeredQuestionIDs.\(question.id)"] = now
        }
        do {
            try await Firestore.firestore().collection("users").document(uid).updateData(updates)
        } catch {
            // Non-blocking — worst case one of today's questions can be re-selected later.
        }
    }
}

func decodeJSONResource<T: Decodable>(_ type: T.Type, filename: String, bundle: Bundle) -> T? {
    guard let url = bundle.url(forResource: filename, withExtension: "json") else {
        assertionFailure("Missing bundled resource: \(filename).json")
        return nil
    }
    guard let data = try? Data(contentsOf: url) else {
        assertionFailure("Could not read bundled resource: \(filename).json")
        return nil
    }
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        assertionFailure("Failed to decode \(filename).json as \(T.self): \(error)")
        return nil
    }
}
