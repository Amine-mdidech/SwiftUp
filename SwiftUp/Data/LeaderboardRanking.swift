import Foundation

enum LeaderboardRanking {
    /// A ranked position, deliberately decoupled from any UI-facing model — `LeaderboardRepository`
    /// (which does touch Firestore) maps this 1:1 into `LeaderboardEntry` for the view layer.
    struct RankedRecord {
        let uid: String
        let displayName: String
        let totalXP: Int
        let rank: Int
    }

    /// Assigns 1-based rank by totalXP descending, over whatever page of records is passed in
    /// (e.g. a top-50 query result) — ties share adjacent rank numbers purely by sort position
    /// here. `rank(aheadCount:totalCount:)` below is what gives a single user (who might not be
    /// on this page at all) a rank that correctly ties with everyone else on exact XP.
    static func rankedRecords(from records: [LeaderboardRecord]) -> [RankedRecord] {
        records.sorted { $0.totalXP > $1.totalXP }.enumerated().map { offset, record in
            RankedRecord(uid: record.uid, displayName: record.displayName, totalXP: record.totalXP, rank: offset + 1)
        }
    }

    /// The current user's rank/percentile from two counts: how many users have strictly more XP
    /// (`aheadCount`), and how many users exist in total (`totalCount`, includes the current
    /// user). Ties on XP share the same rank number since a strict `>` count can't distinguish
    /// them — standard leaderboard behavior. `nil` when there's nobody ranked at all.
    static func rank(aheadCount: Int, totalCount: Int) -> (rank: Int, percentile: Int)? {
        guard totalCount > 0 else { return nil }
        let rank = aheadCount + 1
        let percentile = Int((Double(rank) / Double(totalCount) * 100).rounded(.up))
        return (rank: rank, percentile: percentile)
    }
}
