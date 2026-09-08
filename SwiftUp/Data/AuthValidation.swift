import Foundation

enum AuthValidation {
    /// A pragmatic (not RFC 5322-exhaustive) email shape check: something@something.something.
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Matches Firebase Auth's own minimum password length.
    static func isValidPassword(_ password: String) -> Bool {
        password.count >= 6
    }
}
