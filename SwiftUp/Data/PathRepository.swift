import Foundation
import FirebaseFirestore

@Observable
@MainActor
final class PathRepository {
    private(set) var tracks: [PathTrack] = []
    private(set) var completedStageIDs: Set<String> = []
    private(set) var startedStageIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var usedBundledFallback = false
    private(set) var grade: SkillLevel = .junior
    private(set) var lastAdUnlockDate: String?
    private var loadedUID: String?
    private var pendingSpendStageIDs: Set<String> = []

    init() {}

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> PathRepository {
        let repo = PathRepository()
        repo.tracks = loadBundledFallback(bundle: bundle)
        return repo
    }

    static func loadBundledFallback(bundle: Bundle = .main) -> [PathTrack] {
        decodeJSONResource([PathTrack].self, filename: "path_tracks", bundle: bundle) ?? []
    }

    /// Fetches every track across all four grades — a fixed, small collection (20 tracks), the
    /// same "load it all at once" approach `InterviewRepository` already takes for its bank — plus
    /// this user's completed stage IDs.
    ///
    /// Guarded at entry: `PathWheelView` and `ProfileHomeView` both call this from their own
    /// `.task`, and `MainTabView` constructs all four tabs at once (hidden via `.opacity`, not
    /// conditional construction), so both `.task`s fire on the same cold launch. Skipping when a
    /// load is already in progress, or has already succeeded for this same `uid`, keeps every
    /// caller safe without needing call-site changes — the same "only load once" idea
    /// `InterviewBankView` applies at its own call site
    /// (`repo.categories.isEmpty ? repo.load() : ()`), just enforced here instead so it covers
    /// every caller. Keying on `uid` (rather than `tracks.isEmpty`) means a sign-out/sign-in into a
    /// *different* account still triggers a fresh load — `PathRepository` is a long-lived `@State`
    /// on `RootView` that outlives sign-out, so a load latch keyed only on "have we ever loaded"
    /// would silently serve one account's grade/tracks to the next.
    func load(for uid: String) async {
        guard !isLoading, loadedUID != uid else { return }
        isLoading = true
        defer { isLoading = false }

        async let tracksResult = Self.fetchTracks()
        async let userDocResult = Self.fetchUserDocument(uid: uid)
        let (fetchedTracks, userDoc) = await (tracksResult, userDocResult)

        if fetchedTracks.isEmpty {
            tracks = Self.loadBundledFallback()
            usedBundledFallback = true
        } else {
            tracks = fetchedTracks
            usedBundledFallback = false
        }
        completedStageIDs = Self.completedStageIDs(from: userDoc)
        startedStageIDs = Self.startedStageIDs(from: userDoc)
        grade = Self.grade(from: userDoc)
        lastAdUnlockDate = userDoc?.get("lastPathAdUnlockDate") as? String
        loadedUID = uid
    }

    func tracks(for grade: SkillLevel) -> [PathTrack] {
        tracks.filter { $0.grade == grade }.sorted { $0.order < $1.order }
    }

    func isStageCompleted(_ stage: PathStage) -> Bool {
        completedStageIDs.contains(stage.id)
    }

    func isStageStarted(_ stage: PathStage) -> Bool {
        startedStageIDs.contains(stage.id)
    }

    func isTrackClosed(_ track: PathTrack) -> Bool {
        !track.stages.isEmpty && track.stages.allSatisfy { isStageCompleted($0) }
    }

    /// A stage unlocks once every earlier stage (by `order`) in its own track is completed. The
    /// first stage in a track is always unlocked by this method's own logic — whether the *track*
    /// itself is reachable (e.g. "you need 3 of 5 Junior tracks closed before this one shows") is
    /// a later sub-project's concern, not this repository's.
    func isStageUnlocked(_ stage: PathStage, in track: PathTrack) -> Bool {
        guard track.stages.contains(where: { $0.id == stage.id }) else { return false }
        return track.stages.filter { $0.order < stage.order }.allSatisfy { isStageCompleted($0) }
    }

    /// A track unlocks once every earlier track (by `order`) in the same grade is closed. The
    /// first track in a grade is always reachable.
    func isTrackReachable(_ track: PathTrack) -> Bool {
        let earlierTracks = tracks(for: track.grade).filter { $0.order < track.order }
        // If we're looking for earlier tracks but found none, and we're not the first track,
        // we're not reachable (prerequisites can't be verified)
        if earlierTracks.isEmpty && track.order > 1 {
            return false
        }
        return earlierTracks.allSatisfy { isTrackClosed($0) }
    }

    private static func fetchTracks() async -> [PathTrack] {
        guard let snapshot = try? await Firestore.firestore().collection("pathTracks").getDocuments() else {
            return []
        }
        return snapshot.documents.compactMap { try? $0.data(as: PathTrack.self) }
    }

    /// Fetches the `users/{uid}` document once so both `completedPathStageIDs` and `skillLevel`
    /// can be derived from the same snapshot, rather than reading the document twice (design doc
    /// §3).
    private static func fetchUserDocument(uid: String) async -> DocumentSnapshot? {
        try? await Firestore.firestore().collection("users").document(uid).getDocument()
    }

    private static func completedStageIDs(from snapshot: DocumentSnapshot?) -> Set<String> {
        guard let map = snapshot?.get("completedPathStageIDs") as? [String: Timestamp] else {
            return []
        }
        return Set(map.keys)
    }

    private static func startedStageIDs(from snapshot: DocumentSnapshot?) -> Set<String> {
        guard let map = snapshot?.get("startedPathStageIDs") as? [String: Timestamp] else {
            return []
        }
        return Set(map.keys)
    }

    /// Reads the same `users/{uid}.skillLevel` field `QuestionRepository` already reads — a
    /// second, independent read of the same field, not a shared cache. That's fine: it's one
    /// cheap field read, and it keeps `PathRepository` self-contained rather than depending on
    /// `QuestionRepository`'s internal state.
    private static func grade(from snapshot: DocumentSnapshot?) -> SkillLevel {
        guard let raw = snapshot?.get("skillLevel") as? String,
              let level = SkillLevel(rawValue: raw)
        else {
            return .junior
        }
        return level
    }

    enum SpendResult: Equatable {
        case started(newBalance: Int)
        case alreadyStarted
        case insufficientXP(balance: Int)
        case failed
    }

    /// Spends `cost` xp to unlock `stage`, or returns `.alreadyStarted` for free if it's already
    /// unlocked (or already completed) — spending is a one-time cost, never repeated for the same
    /// stage (design doc §3). The already-started/already-completed check happens before any
    /// Firestore access, so a retry never even attempts a re-charge.
    ///
    /// Not independently unit-tested beyond `isStageStarted`'s own coverage: every other branch
    /// here requires live Firestore state, matching the accepted limitation already in place for
    /// every other Firestore write in this project (see design doc §7).
    func startStage(_ stage: PathStage, cost: Int, for uid: String) async -> SpendResult {
        if completedStageIDs.contains(stage.id) || startedStageIDs.contains(stage.id) {
            return .alreadyStarted
        }
        // Guards against a rapid double-tap: startedStageIDs is only updated after the Firestore
        // round-trip below, so without this a second call for the same stage could pass the guard
        // above too and double-charge. This in-memory set closes that window immediately, before
        // any network access.
        guard !pendingSpendStageIDs.contains(stage.id) else { return .alreadyStarted }
        pendingSpendStageIDs.insert(stage.id)
        defer { pendingSpendStageIDs.remove(stage.id) }

        let userRef = Firestore.firestore().collection("users").document(uid)
        guard let snapshot = try? await userRef.getDocument() else { return .failed }

        let totalXP = (snapshot.get("totalXP") as? Int) ?? 0
        let currentBalance = (snapshot.get("xpBalance") as? Int) ?? totalXP
        guard currentBalance >= cost else { return .insufficientXP(balance: currentBalance) }

        let newBalance = currentBalance - cost
        do {
            try await userRef.setData(
                ["xpBalance": FieldValue.increment(Int64(-cost)), "startedPathStageIDs": [stage.id: FieldValue.serverTimestamp()]],
                merge: true
            )
            startedStageIDs.insert(stage.id)
            return .started(newBalance: newBalance)
        } catch {
            return .failed
        }
    }

    /// Whether the once-a-day ad unlock is still available today — `true` on a user who has
    /// never used it, or whose last use was on an earlier calendar day than today.
    var hasAdUnlockAvailableToday: Bool {
        lastAdUnlockDate != DailyEdition.todayKey()
    }

    /// Unlocks `stage` for free after a watched rewarded ad — no xp is spent or credited, this is
    /// a pure unlock, matching how this app's existing ad gate elsewhere (Daily Quiz's practice
    /// redo, the Support page) is a pass/fail gate rather than an xp grant. Limited to once per
    /// calendar day: returns `false` without writing anything if today's unlock was already used,
    /// or if `stage` is already started/completed (checked before any Firestore access, same
    /// guard order as `startStage`).
    func unlockStageViaAd(_ stage: PathStage, for uid: String) async -> Bool {
        guard hasAdUnlockAvailableToday else { return false }
        guard !completedStageIDs.contains(stage.id), !startedStageIDs.contains(stage.id) else { return false }

        let today = DailyEdition.todayKey()
        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(
                ["startedPathStageIDs": [stage.id: FieldValue.serverTimestamp()], "lastPathAdUnlockDate": today],
                merge: true
            )
            startedStageIDs.insert(stage.id)
            lastAdUnlockDate = today
            return true
        } catch {
            return false
        }
    }


    /// Marks `stage` as completed after a passing quiz attempt. No XP is written here — passing
    /// grants no XP (design doc §3); this call only records progress.
    func completeStage(_ stage: PathStage, for uid: String) async {
        let userRef = Firestore.firestore().collection("users").document(uid)
        do {
            try await userRef.setData(
                ["completedPathStageIDs": [stage.id: FieldValue.serverTimestamp()]],
                merge: true
            )
            completedStageIDs.insert(stage.id)
        } catch {
            // Non-blocking — matches this project's accepted best-effort posture for Firestore writes.
        }
    }

    /// Promotes the user to `currentGrade.next` after a passing regrade quiz — the only place
    /// `SkillLevel` is written outside onboarding (design doc §6). A no-op at the top grade
    /// (`.distinguished.next == nil`), returning before touching Firestore.
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

    /// Fetches one stage's slide/quiz content, falling back to the bundled placeholder content
    /// (mirroring `fetchTracks`' own bundled-fallback pattern) if Firestore is unreachable.
    func fetchStageContent(for stage: PathStage) async -> PathStageContent? {
        if let snapshot = try? await Firestore.firestore().collection("pathStageContent").document(stage.id).getDocument(),
           let content = try? snapshot.data(as: PathStageContent.self) {
            return content
        }
        return Self.loadBundledStageContent().first { $0.stageID == stage.id }
    }

    /// Fetches one grade's regrade quiz, same bundled-fallback pattern as `fetchStageContent`.
    func fetchRegradeQuiz(for grade: SkillLevel) async -> PathRegradeQuiz? {
        let docID = grade.rawValue.lowercased()
        if let snapshot = try? await Firestore.firestore().collection("pathRegradeQuizzes").document(docID).getDocument(),
           let quiz = try? snapshot.data(as: PathRegradeQuiz.self) {
            return quiz
        }
        return Self.loadBundledRegradeQuizzes().first { $0.grade == grade }
    }

    private static func loadBundledStageContent(bundle: Bundle = .main) -> [PathStageContent] {
        decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: bundle)?.stageContent ?? []
    }

    private static func loadBundledRegradeQuizzes(bundle: Bundle = .main) -> [PathRegradeQuiz] {
        decodeJSONResource(PathContentBundle.self, filename: "path_content", bundle: bundle)?.regradeQuizzes ?? []
    }
}
