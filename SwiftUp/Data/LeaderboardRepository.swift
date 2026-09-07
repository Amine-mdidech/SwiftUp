import Foundation

@Observable
final class LeaderboardRepository {
    let entries: [LeaderboardEntry]

    init(bundle: Bundle = .main) {
        entries = (decodeJSONResource([LeaderboardEntry].self, filename: "leaderboard", bundle: bundle) ?? [])
            .sorted { $0.rank < $1.rank }
    }
}
