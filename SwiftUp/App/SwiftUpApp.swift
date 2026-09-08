import SwiftUI
import FirebaseCore

@main
struct SwiftUpApp: App {
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
