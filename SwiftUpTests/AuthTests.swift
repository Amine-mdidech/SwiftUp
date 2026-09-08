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

extension AuthTests {
    @Test @MainActor func previewModeSignedOutHasNoUser() {
        let repo = AuthRepository(isPreview: true, signedIn: false)
        #expect(repo.isSignedIn == false)
        #expect(repo.currentUser == nil)
    }

    @Test @MainActor func previewModeSignedInHasPreviewUser() {
        let repo = AuthRepository(isPreview: true, signedIn: true)
        #expect(repo.isSignedIn == true)
        #expect(repo.currentUser?.uid == "preview-user")
    }

    @Test func randomNonceStringHasRequestedLength() {
        let nonce = AuthRepository.randomNonceString(length: 32)
        #expect(nonce.count == 32)
    }

    @Test func randomNonceStringsAreNotRepeated() {
        let a = AuthRepository.randomNonceString()
        let b = AuthRepository.randomNonceString()
        #expect(a != b)
    }

    @Test func sha256MatchesKnownVector() {
        // Known SHA-256 test vector for the ASCII string "hello".
        let hash = AuthRepository.sha256("hello")
        #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
}
