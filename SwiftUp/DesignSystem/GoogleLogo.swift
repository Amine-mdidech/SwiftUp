import SwiftUI

/// The Google "G" mark, traced from Google's official multi-color SVG at native
/// 18x18 units (converted from SVG path data, including its elliptical arcs).
struct GoogleLogo: View {
    var body: some View {
        ZStack {
            bluePath.fill(Color(hex: 0x4285F4))
            greenPath.fill(Color(hex: 0x34A853))
            yellowPath.fill(Color(hex: 0xFBBC05))
            redPath.fill(Color(hex: 0xEA4335))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private var bluePath: Path {
        Path { p in
            p.move(to: CGPoint(x: 17.6, y: 9.2))
            p.addCurve(to: CGPoint(x: 17.4, y: 7.3), control1: CGPoint(x: 17.6, y: 8.6), control2: CGPoint(x: 17.5, y: 7.9))
            p.addLine(to: CGPoint(x: 9.0, y: 7.3))
            p.addLine(to: CGPoint(x: 9.0, y: 10.8))
            p.addLine(to: CGPoint(x: 13.8, y: 10.8))
            p.addArc(center: CGPoint(x: 16.0329, y: 14.2386), radius: 4.1, startAngle: .radians(-2.146726), endAngle: .radians(-2.960454), clockwise: true)
            p.addLine(to: CGPoint(x: 12.0, y: 15.7))
            p.addLine(to: CGPoint(x: 14.9, y: 15.7))
            p.addCurve(to: CGPoint(x: 17.6, y: 9.2), control1: CGPoint(x: 16.6, y: 14.1), control2: CGPoint(x: 17.6, y: 11.8))
            p.closeSubpath()
        }
    }

    private var greenPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 9.0, y: 18.0))
            p.addCurve(to: CGPoint(x: 15.0, y: 15.8), control1: CGPoint(x: 11.4, y: 18.0), control2: CGPoint(x: 13.5, y: 17.2))
            p.addLine(to: CGPoint(x: 12.1, y: 13.6))
            p.addCurve(to: CGPoint(x: 9.0, y: 14.5), control1: CGPoint(x: 11.3, y: 14.1), control2: CGPoint(x: 10.3, y: 14.5))
            p.addCurve(to: CGPoint(x: 3.9, y: 10.7), control1: CGPoint(x: 6.6, y: 14.5), control2: CGPoint(x: 4.6, y: 12.9))
            p.addLine(to: CGPoint(x: 0.9, y: 10.7))
            p.addLine(to: CGPoint(x: 0.9, y: 13.0))
            p.addArc(center: CGPoint(x: 0.9377, y: 21.9999), radius: 9.0, startAngle: .radians(-1.574986), endAngle: .radians(-0.460544), clockwise: false)
            p.closeSubpath()
        }
    }

    private var yellowPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 3.9, y: 10.7))
            p.addArc(center: CGPoint(x: -1.2254, y: 9.0), radius: 5.4, startAngle: .radians(0.320262), endAngle: .radians(-0.320262), clockwise: true)
            p.addLine(to: CGPoint(x: 3.9, y: 5.0))
            p.addLine(to: CGPoint(x: 0.9, y: 5.0))
            p.addArc(center: CGPoint(x: -7.1623, y: 9.0), radius: 9.0, startAngle: .radians(-0.460554), endAngle: .radians(0.460554), clockwise: false)
            p.addLine(to: CGPoint(x: 3.9, y: 10.7))
            p.closeSubpath()
        }
    }

    private var redPath: Path {
        Path { p in
            p.move(to: CGPoint(x: 9.0, y: 3.6))
            p.addCurve(to: CGPoint(x: 12.4, y: 4.9), control1: CGPoint(x: 10.3, y: 3.6), control2: CGPoint(x: 11.5, y: 4.1))
            p.addLine(to: CGPoint(x: 15.0, y: 2.3))
            p.addArc(center: CGPoint(x: 6.9289, y: -1.6822), radius: 9.0, startAngle: .radians(0.458348), endAngle: .radians(2.304846), clockwise: false)
            p.addLine(to: CGPoint(x: 3.9, y: 7.3))
            p.addCurve(to: CGPoint(x: 9.0, y: 3.6), control1: CGPoint(x: 4.6, y: 5.2), control2: CGPoint(x: 6.6, y: 3.6))
            p.closeSubpath()
        }
    }
}

#Preview("Google logo") {
    GoogleLogo()
        .padding()
        .background(Theme.Colors.bg)
}
