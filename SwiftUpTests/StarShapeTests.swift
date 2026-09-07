import Testing
import SwiftUI
@testable import SwiftUp

struct StarShapeTests {
    @Test func starPathStaysWithinBounds() {
        let shape = StarShape()
        let rect = CGRect(x: 0, y: 0, width: 46, height: 46)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect
        #expect(bounds.width <= rect.width + 0.5)
        #expect(bounds.height <= rect.height + 0.5)
        #expect(!path.isEmpty)
    }
}
