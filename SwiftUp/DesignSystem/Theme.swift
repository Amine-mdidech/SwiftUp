import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum Theme {
    enum Colors {
        static let bg = Color(hex: 0xF3F2F2)
        static let surface = Color(hex: 0xEAE9E9)
        static let text = Color(hex: 0x201E1D)
        static let divider = Color(hex: 0x201E1D, opacity: 0.16)

        static let accent = Color(hex: 0x0088B0)
        static let accent100 = Color(hex: 0xE9F8FF)
        static let accent700 = Color(hex: 0x006786)
        static let accent800 = Color(hex: 0x004961)

        static let accent2 = Color(hex: 0xD6006C)
        static let accent2100 = Color(hex: 0xFFF1F4)
        static let accent2800 = Color(hex: 0x790E3D)

        static let neutral200 = Color(hex: 0xEAE7E7)
        static let neutral300 = Color(hex: 0xD7D3D3)
        static let neutral400 = Color(hex: 0xBAB6B6)
        static let neutral600 = Color(hex: 0x7D7979)
        static let neutral700 = Color(hex: 0x605D5D)
        static let neutral800 = Color(hex: 0x444141)

        static let processYellow = Color(hex: 0xEDBB00)
    }

    enum Spacing {
        static let s1: CGFloat = 5
        static let s2: CGFloat = 10
        static let s3: CGFloat = 15
        static let s4: CGFloat = 20
        static let s6: CGFloat = 30
        static let s8: CGFloat = 40
    }

    enum Fonts {
        static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}
