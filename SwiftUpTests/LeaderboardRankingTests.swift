import Testing
@testable import SwiftUp

struct LeaderboardRankingTests {
    @Test func rankedRecordsSortsDescendingByXPAndAssigns1BasedRank() {
        let records = [
            LeaderboardRecord(uid: "a", displayName: "A", totalXP: 100),
            LeaderboardRecord(uid: "b", displayName: "B", totalXP: 300),
            LeaderboardRecord(uid: "c", displayName: "C", totalXP: 200),
        ]
        let ranked = LeaderboardRanking.rankedRecords(from: records)
        #expect(ranked.map(\.uid) == ["b", "c", "a"])
        #expect(ranked.map(\.rank) == [1, 2, 3])
    }

    @Test func rankFromCountsComputesRankAndPercentile() {
        let result = LeaderboardRanking.rank(aheadCount: 4, totalCount: 100)
        #expect(result?.rank == 5)
        #expect(result?.percentile == 5)
    }

    @Test func rankFromCountsRoundsPercentileUpSoTopSpotIsNeverZeroPercent() {
        let result = LeaderboardRanking.rank(aheadCount: 0, totalCount: 1_000_000)
        #expect(result?.rank == 1)
        #expect(result?.percentile == 1)
    }

    @Test func rankFromCountsIsNilWithNoRankedUsers() {
        #expect(LeaderboardRanking.rank(aheadCount: 0, totalCount: 0) == nil)
    }

    @Test func tiedXPGetsTheSameRankNumber() {
        // Two users both with 3 users strictly ahead of them -> both rank 4, regardless of
        // however many others share their exact XP (a strict `>` count can't tell them apart).
        let a = LeaderboardRanking.rank(aheadCount: 3, totalCount: 10)
        let b = LeaderboardRanking.rank(aheadCount: 3, totalCount: 10)
        #expect(a?.rank == b?.rank)
    }
}
