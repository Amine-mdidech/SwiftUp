import Testing
@testable import SwiftUp

struct AuthTests {
    @Test func authUserStoresFields() {
        let user = AuthUser(uid: "abc123", email: "dev@example.com", displayName: "Amine")
        #expect(user.uid == "abc123")
        #expect(user.email == "dev@example.com")
        #expect(user.displayName == "Amine")
    }

    @Test func validEmailsPass() {
        #expect(AuthValidation.isValidEmail("dev@example.com"))
        #expect(AuthValidation.isValidEmail("a.b+c@sub.example.co"))
    }

    @Test func invalidEmailsFail() {
        #expect(!AuthValidation.isValidEmail("not-an-email"))
        #expect(!AuthValidation.isValidEmail("missing@domain"))
        #expect(!AuthValidation.isValidEmail("@example.com"))
        #expect(!AuthValidation.isValidEmail(""))
    }

    @Test func passwordsAtLeastSixCharsPass() {
        #expect(AuthValidation.isValidPassword("abcdef"))
        #expect(AuthValidation.isValidPassword("longenoughpassword"))
    }

    @Test func shortPasswordsFail() {
        #expect(!AuthValidation.isValidPassword("abc"))
        #expect(!AuthValidation.isValidPassword(""))
    }
}
