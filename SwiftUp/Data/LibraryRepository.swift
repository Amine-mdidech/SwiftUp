import Foundation
import FirebaseFirestore

/// Result of completing a class: `xpAwarded` is what was just credited (0 if this class was
/// already completed before — a replay never re-awards its xp), and `becamePerfect` reports
/// whether this pass just earned a first-time perfect score.
struct ClassCompletionResult: Equatable {
    let xpAwarded: Int
    let becamePerfect: Bool
}

@Observable
@MainActor
final class LibraryRepository {
    private(set) var paths: [LibraryPath] = []
    private(set) var completedClassIDs: Set<String> = []
    private(set) var startedClassIDs: Set<String> = []
    private(set) var perfectClassIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var grade: SkillLevel = .junior
    private var loadedUID: String?

    init() {}

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> LibraryRepository {
        let repo = LibraryRepository()
        repo.paths = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [LibraryPath] {
        decodeJSONResource([LibraryPath].self, filename: "path_tracks", bundle: bundle) ?? []
    }

    /// Fetches every class across all twenty paths — a fixed, small collection, the same "load it
    /// all at once" approach `InterviewRepository` already takes for its bank — plus this user's
    /// progress (started/completed/perfect class IDs).
    ///
    /// Guarded at entry the same way `QuestionRepository`/`ProfileRepository` are: skipping when a
    /// load is already in progress, or has already succeeded for this same `uid`, keeps every
    /// caller safe without needing call-site changes.
    func load(for uid: String) async {
        guard !isLoading, loadedUID != uid else { return }
        isLoading = true
        defer { isLoading = false }

        async let pathsResult = Self.fetchPaths()
        async let userDocResult = Self.fetchUserDocument(uid: uid)
        let (fetchedPaths, userDoc) = await (pathsResult, userDocResult)

        paths = fetchedPaths.isEmpty ? Self.loadBundledFallback() : fetchedPaths
        completedClassIDs = Self.classIDs(from: userDoc, field: "completedPathStageIDs")
        startedClassIDs = Self.classIDs(from: userDoc, field: "startedPathStageIDs")
        perfectClassIDs = Self.classIDs(from: userDoc, field: "perfectPathStageIDs")
        grade = Self.grade(from: userDoc)
        loadedUID = uid
    }

    func paths(for grade: SkillLevel) -> [LibraryPath] {
        paths.filter { $0.grade == grade }.sorted { $0.order < $1.order }
    }

    func isClassCompleted(_ libClass: LibraryClass) -> Bool {
        completedClassIDs.contains(libClass.id)
    }

    func isClassStarted(_ libClass: LibraryClass) -> Bool {
        startedClassIDs.contains(libClass.id)
    }

    func isClassPerfect(_ libClass: LibraryClass) -> Bool {
        perfectClassIDs.contains(libClass.id)
    }

    func isPathSealed(_ path: LibraryPath) -> Bool {
        !path.classes.isEmpty && path.classes.allSatisfy { isClassCompleted($0) }
    }

    /// Every class in a path is freely startable in any order — the Library has no lock or price
    /// on anything — except the path's own assessment, which requires every other class in that
    /// path to already be completed. That's the one place "finish the path" still means something
    /// structurally, matching how a course's final exam works.
    func canStartClass(_ libClass: LibraryClass, in path: LibraryPath) -> Bool {
        guard libClass.kind == .assessment else { return true }
        return path.classes.filter { $0.kind != .assessment }.allSatisfy { isClassCompleted($0) }
    }

    private static func fetchPaths() async -> [LibraryPath] {
        guard let snapshot = try? await Firestore.firestore().collection("pathTracks").getDocuments() else {
            return []
        }
        return snapshot.documents.compactMap { try? $0.data(as: LibraryPath.self) }
    }

    /// Fetches the `users/{uid}` document once so `completedClassIDs`/`startedClassIDs`/
    /// `perfectClassIDs`/`grade` can all be derived from the same snapshot, rather than reading
    /// the document four times.
    private static func fetchUserDocument(uid: String) async -> DocumentSnapshot? {
        try? await Firestore.firestore().collection("users").document(uid).getDocument()
    }

    private static func classIDs(from snapshot: DocumentSnapshot?, field: String) -> Set<String> {
        guard let map = snapshot?.get(field) as? [String: Timestamp] else { return [] }
        return Set(map.keys)
    }

    /// Reads the same `users/{uid}.skillLevel` field `QuestionRepository` already reads — a
    /// second, independent read of the same field, not a shared cache. That's fine: it's one
    /// cheap field read, and it keeps `LibraryRepository` self-contained. Grade is purely a status
    /// here now — it gates nothing in the Library, only the (separate) regrade mechanic below.
    private static func grade(from snapshot: DocumentSnapshot?) -> SkillLevel {
        guard let raw = snapshot?.get("skillLevel") as? String,
              let level = SkillLevel(rawValue: raw)
        else {
            return .junior
        }
        return level
    }

    /// Marks `libClass` as read — always succeeds, nothing to spend or unlock anymore. A no-op if
    /// it's already marked, so re-opening an already-read class doesn't re-write the timestamp.
    func markClassStarted(_ libClass: LibraryClass, for uid: String) async {
        guard !startedClassIDs.contains(libClass.id) else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(
                ["startedPathStageIDs": [libClass.id: FieldValue.serverTimestamp()]], merge: true
            )
            startedClassIDs.insert(libClass.id)
        } catch {
            // Non-blocking — matches this project's accepted best-effort posture for Firestore writes.
        }
    }

    /// Marks `libClass` completed, crediting its `xpReward` the first time only — a replay (e.g.
    /// to go for a perfect score after already passing) never re-awards it, though it can still
    /// newly earn the perfect mark. The caller is responsible for reflecting `xpAwarded` into
    /// `ProfileRepository` (via `applyExternalXPEarn`), the same division of responsibility
    /// `startStage`/`applyExternalXPBalance` used for spending.
    @discardableResult
    func completeClass(_ libClass: LibraryClass, isPerfectScore: Bool, for uid: String) async -> ClassCompletionResult {
        let wasAlreadyCompleted = completedClassIDs.contains(libClass.id)
        let wasAlreadyPerfect = perfectClassIDs.contains(libClass.id)
        let xpToAward = wasAlreadyCompleted ? 0 : libClass.xpReward

        var updates: [String: Any] = ["completedPathStageIDs": [libClass.id: FieldValue.serverTimestamp()]]
        if xpToAward > 0 {
            updates["totalXP"] = FieldValue.increment(Int64(xpToAward))
            updates["xpBalance"] = FieldValue.increment(Int64(xpToAward))
        }
        if isPerfectScore {
            updates["perfectPathStageIDs"] = [libClass.id: FieldValue.serverTimestamp()]
        }

        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(updates, merge: true)
            completedClassIDs.insert(libClass.id)
            if isPerfectScore { perfectClassIDs.insert(libClass.id) }
            return ClassCompletionResult(xpAwarded: xpToAward, becamePerfect: isPerfectScore && !wasAlreadyPerfect)
        } catch {
            // Non-blocking — matches this project's accepted best-effort posture for Firestore writes.
            return ClassCompletionResult(xpAwarded: 0, becamePerfect: false)
        }
    }

    /// Promotes the user to `currentGrade.next` after a passing regrade quiz — the only place
    /// `SkillLevel` is written outside onboarding. A no-op at the top grade
    /// (`.distinguished.next == nil`), returning before touching Firestore. Unrelated to Library
    /// access (grade gates nothing there) — this is purely the separate status/achievement ladder.
    func promoteGrade(from currentGrade: SkillLevel, for uid: String) async {
        guard let next = currentGrade.next else { return }
        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(["skillLevel": next.rawValue], merge: true)
            grade = next
        } catch {
            // Non-blocking — matches this project's accepted best-effort posture for Firestore writes.
        }
    }

    /// Fetches one class's article/quiz content, falling back to the bundled placeholder content
    /// (mirroring `fetchPaths`' own bundled-fallback pattern) if Firestore is unreachable.
    func fetchClassContent(for libClass: LibraryClass) async -> LibraryClassContent? {
        if let snapshot = try? await Firestore.firestore().collection("pathStageContent").document(libClass.id).getDocument(),
           let content = try? snapshot.data(as: LibraryClassContent.self) {
            return content
        }
        return Self.loadBundledClassContent().first { $0.classID == libClass.id }
    }

    /// Fetches one grade's regrade quiz, same bundled-fallback pattern as `fetchClassContent`.
    func fetchRegradeQuiz(for grade: SkillLevel) async -> RegradeQuiz? {
        let docID = grade.rawValue.lowercased()
        if let snapshot = try? await Firestore.firestore().collection("pathRegradeQuizzes").document(docID).getDocument(),
           let quiz = try? snapshot.data(as: RegradeQuiz.self) {
            return quiz
        }
        return Self.loadBundledRegradeQuizzes().first { $0.grade == grade }
    }

    private static func loadBundledClassContent(bundle: Bundle = .main) -> [LibraryClassContent] {
        decodeJSONResource(LibraryContentBundle.self, filename: "path_content", bundle: bundle)?.classContent ?? []
    }

    private static func loadBundledRegradeQuizzes(bundle: Bundle = .main) -> [RegradeQuiz] {
        decodeJSONResource(LibraryContentBundle.self, filename: "path_content", bundle: bundle)?.regradeQuizzes ?? []
    }
}
