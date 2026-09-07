import Testing
import SwiftUI
@testable import SwiftUp

struct ThemeTests {
    @Test func hexInitializerMatchesKnownColor() {
        let color = Color(hex: 0x0088B0)
        let resolved = color.resolve(in: EnvironmentValues())
        #expect(abs(resolved.red - 0/255) < 0.01)
        #expect(abs(resolved.green - 136.0/255) < 0.01)
        #expect(abs(resolved.blue - 176.0/255) < 0.01)
    }

    @Test func spacingScaleIsPositive() {
        #expect(Theme.Spacing.s1 < Theme.Spacing.s2)
        #expect(Theme.Spacing.s8 == 40)
    }
}
