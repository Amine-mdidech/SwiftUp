import Foundation
import FirebaseFirestore

@Observable
final class QuestionRepository {
    private(set) var todayQuestions: [Question] = []
    /// Today's edition number, read straight from `dailyQuizzes/{today}`. `nil` when that
    /// document couldn't be fetched (offline, not yet seeded) and `todayQuestions` fell back to
    /// the bundled set — there's no on-device number to show in that case.
    private(set) var editionNumber: Int?
    private(set) var isLoading = false
    private(set) var levelOverride: SkillLevel?
    private(set) var effectiveLevel: SkillLevel = .junior

    init() {}

    /// Synchronously loads the bundled fallback set — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> QuestionRepository {
        let repo = QuestionRepository()
        repo.todayQuestions = loadBundledFallback(bundle: bundle)
        repo.editionNumber = 1
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [Question] {
        decodeJSONResource([Question].self, filename: "questions", bundle: bundle) ?? []
    }

    /// Fetches today's shared daily quiz for `uid`: reads their skill level/override from Firestore,
    /// then reads today's edition — the same edition number and same questions every user at that
    /// level sees today — from `dailyQuizzes/{today}` (`DailyEdition.todayKey()`), authored
    /// server-side by `scripts/seed_daily_quizzes.py`. Falls back to the bundled set only if that
    /// document is unreachable (offline, not yet seeded) with nothing cached locally yet.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let userDoc = Firestore.firestore().collection("users").document(uid)

        var storedLevel = SkillLevel.junior
        var override: SkillLevel?

        do {
            let snapshot = try await userDoc.getDocument()
            if let raw = snapshot.get("skillLevel") as? String, let level = SkillLevel(rawValue: raw) {
                storedLevel = level
            }
            if let raw = snapshot.get("levelOverride") as? String, let level = SkillLevel(rawValue: raw) {
                override = level
            }
        } catch {
            // No user doc data available (offline, first launch) — proceed with defaults.
        }

        levelOverride = override
        let effectiveLevel = override ?? storedLevel

        guard let daily = try? await fetchDailyQuiz() else {
            todayQuestions = Self.loadBundledFallback()
            editionNumber = nil
            return
        }

        todayQuestions = daily.questions(for: effectiveLevel)
        editionNumber = daily.edition
        self.effectiveLevel = effectiveLevel
    }

    private func fetchDailyQuiz() async throws -> DailyQuizDocument {
        try await Firestore.firestore()
            .collection("dailyQuizzes").document(DailyEdition.todayKey())
            .getDocument(as: DailyQuizDocument.self)
    }

    /// A past date's shared daily quiz, for replay/practice — same document shape as today's, just a
    /// different `dailyQuizzes/{date}` key. `nil` if that date was never seeded (predates the app, or
    /// fell outside the seed script's rolling window) — the caller treats this as "nothing to redo."
    func fetchPastQuiz(for dateKey: String) async -> DailyQuizDocument? {
        try? await Firestore.firestore()
            .collection("dailyQuizzes").document(dateKey)
            .getDocument(as: DailyQuizDocument.self)
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

    /// Records today's five as answered. Written on every completion, but currently has no reader —
    /// the auto-promotion check that used to read this map was removed; nothing else consumes it yet.
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
