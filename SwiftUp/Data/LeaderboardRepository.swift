import Foundation
import FirebaseFirestore

@Observable
final class LeaderboardRepository {
    let levels: [LevelInfo]
    private(set) var topEntries: [LeaderboardEntry] = []
    /// The signed-in user's own ranked entry — `nil` until they've completed at least one daily
    /// quiz (no `leaderboardEntries` doc yet), or if that lookup itself failed.
    private(set) var myEntry: LeaderboardEntry?
    private(set) var myPercentile: Int?
    private(set) var totalRanked = 0
    private(set) var isLoading = false

    init(bundle: Bundle = .main) {
        levels = decodeJSONResource([LevelInfo].self, filename: "levels", bundle: bundle) ?? []
    }

    /// Synchronously loads bundled fallback content — safe for #Preview, never touches Firestore.
    static func preview(bundle: Bundle = .main) -> LeaderboardRepository {
        let repo = LeaderboardRepository(bundle: bundle)
        repo.applyBundledFallback(bundle: bundle)
        return repo
    }

    private func applyBundledFallback(bundle: Bundle) {
        let records = decodeJSONResource([LeaderboardRecord].self, filename: "leaderboard", bundle: bundle) ?? []
        topEntries = Self.entries(from: LeaderboardRanking.rankedRecords(from: records))
        myEntry = nil
        myPercentile = nil
        totalRanked = topEntries.count
    }

    /// Fetches the real global, all-time board: the top 50 by totalXP, plus the signed-in user's
    /// own rank/percentile via COUNT aggregation (whether or not they're in the top 50). Falls
    /// back to the bundled set only if the top-50 fetch itself is unreachable; a failure fetching
    /// just the user's own rank leaves the real top-50 in place with `myEntry` simply unset.
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        let entriesRef = Firestore.firestore().collection("leaderboardEntries")

        do {
            let snapshot = try await entriesRef
                .order(by: "totalXP", descending: true)
                .limit(to: 50)
                .getDocuments()
            let records: [LeaderboardRecord] = snapshot.documents.compactMap { doc in
                guard let displayName = doc.get("displayName") as? String, let totalXP = doc.get("totalXP") as? Int else {
                    return nil
                }
                return LeaderboardRecord(uid: doc.documentID, displayName: displayName, totalXP: totalXP)
            }
            topEntries = Self.entries(from: LeaderboardRanking.rankedRecords(from: records))
        } catch {
            applyBundledFallback(bundle: .main)
            return
        }

        myEntry = nil
        myPercentile = nil
        guard
            let mySnapshot = try? await entriesRef.document(uid).getDocument(),
            var myDisplayName = mySnapshot.get("displayName") as? String,
            let myXP = mySnapshot.get("totalXP") as? Int
        else { return }

        // `leaderboardEntries/{uid}.displayName` is a denormalized copy that only gets rewritten
        // when a daily quiz completes (or at sign-in, best-effort) — it can lag behind the name on
        // `users/{uid}` by a session or more, especially right after a name is first captured or
        // corrected, since that write and this read both fire concurrently at app launch with no
        // guaranteed order. Prefer the live value here so the signed-in user always sees their
        // current name in the one row that's actually theirs, independent of that race.
        if let usersSnapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
           let freshDisplayName = usersSnapshot.get("displayName") as? String, !freshDisplayName.isEmpty {
            myDisplayName = freshDisplayName
        }

        guard
            let ahead = try? await entriesRef.whereField("totalXP", isGreaterThan: myXP).count.getAggregation(source: .server),
            let total = try? await entriesRef.count.getAggregation(source: .server)
        else { return }

        totalRanked = Int(truncating: total.count)
        guard let result = LeaderboardRanking.rank(aheadCount: Int(truncating: ahead.count), totalCount: totalRanked) else { return }
        myEntry = LeaderboardEntry(uid: uid, displayName: myDisplayName, totalXP: myXP, rank: result.rank)
        myPercentile = result.percentile
    }

    private static func entries(from ranked: [LeaderboardRanking.RankedRecord]) -> [LeaderboardEntry] {
        ranked.map { LeaderboardEntry(uid: $0.uid, displayName: $0.displayName, totalXP: $0.totalXP, rank: $0.rank) }
    }
}
