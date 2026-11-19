import Foundation

struct AuthUser: Equatable {
    let uid: String
    let email: String?
    let displayName: String?
    /// How the account signs in — "Apple", "Google", or "email" — for Settings' account row.
    /// `nil` when Firebase reports no provider (e.g. previews).
    var signInMethod: String? = nil
}
