import Foundation

/// One interview-prep category's full content: its Junior/Mid/Senior question lists, decoded
/// either from an `interviewBank/{slug}` Firestore document or from the bundled fallback.
struct InterviewCategoryContent: Codable, Identifiable {
    var id: String { name }
    let name: String
    let junior: [InterviewQuestion]
    let mid: [InterviewQuestion]
    let senior: [InterviewQuestion]

    /// `level` is one of `InterviewBankView`'s picker values: "Junior", "Mid", "Senior", or "All".
    /// "All" (or any other value) concatenates Junior-first, so `.first` naturally ties toward the
    /// lowest level that has content, and `.count` naturally sums across all three.
    func questions(for level: String) -> [InterviewQuestion] {
        switch level {
        case "Junior": return junior
        case "Mid": return mid
        case "Senior": return senior
        default: return junior + mid + senior
        }
    }
}
