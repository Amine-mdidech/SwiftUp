import Foundation
import FirebaseFirestore

@Observable
final class PathRepository {
    private(set) var tracks: [PathTrack] = []
    private(set) var completedStageIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var usedBundledFallback = false
    private(set) var grade: SkillLevel = .junior

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
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        async let tracksResult = Self.fetchTracks()
        async let completedResult = Self.fetchCompletedStageIDs(uid: uid)
        async let gradeResult = Self.fetchGrade(uid: uid)
        let (fetchedTracks, fetchedCompleted, fetchedGrade) = await (tracksResult, completedResult, gradeResult)

        if fetchedTracks.isEmpty {
            tracks = Self.loadBundledFallback()
            usedBundledFallback = true
        } else {
            tracks = fetchedTracks
            usedBundledFallback = false
        }
        completedStageIDs = fetchedCompleted
        grade = fetchedGrade
    }

    func tracks(for grade: SkillLevel) -> [PathTrack] {
        tracks.filter { $0.grade == grade }.sorted { $0.order < $1.order }
    }

    func isStageCompleted(_ stage: PathStage) -> Bool {
        completedStageIDs.contains(stage.id)
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

    private static func fetchCompletedStageIDs(uid: String) async -> Set<String> {
        guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
              let map = snapshot.get("completedPathStageIDs") as? [String: Timestamp]
        else {
            return []
        }
        return Set(map.keys)
    }

    /// Reads the same `users/{uid}.skillLevel` field `QuestionRepository` already reads — a
    /// second, independent read of the same field, not a shared cache. That's fine: it's one
    /// cheap field read, and it keeps `PathRepository` self-contained rather than depending on
    /// `QuestionRepository`'s internal state.
    private static func fetchGrade(uid: String) async -> SkillLevel {
        guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
              let raw = snapshot.get("skillLevel") as? String,
              let level = SkillLevel(rawValue: raw)
        else {
            return .junior
        }
        return level
    }
}
