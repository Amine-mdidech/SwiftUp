import Foundation

struct InterviewCategory: Codable, Identifiable {
    var id: String { name }
    let name: String
    let reviewedCount: Int
    let totalCount: Int
}
