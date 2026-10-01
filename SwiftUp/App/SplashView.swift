import SwiftUI

/// Cold-launch splash: three misregistered "process plates" (yellow, then the
/// text-color plate, then a full accent wash) register into place behind the
/// wordmark, which recolors to stay legible against whatever's on top of it.
/// Plays once over 4.2s, matching the design's authored timeline, then calls
/// `onFinished`. No spinner, no version, no logo lockup — just the masthead.
struct SplashView: View {
    var onFinished: () -> Void = {}

    private static let duration: TimeInterval = 4.2
    private static let plateDiameter: CGFloat = 296
    private static let wordmarkSize: CGFloat = 58

    @State private var startDate = Date()
    @State private var didFinish = false

    var body: some View {
        TimelineView(.animation) { context in
            let t = progress(at: context.date)

            ZStack {
                Theme.Colors.bg

                Circle()
                    .fill(Theme.Colors.processYellow)
                    .frame(width: Self.plateDiameter, height: Self.plateDiameter)
                    .scaleEffect(Self.yellowScale(t))

                Circle()
                    .fill(Theme.Colors.text)
                    .frame(width: Self.plateDiameter, height: Self.plateDiameter)
                    .scaleEffect(Self.blackScale(t))

                GeometryReader { geo in
                    let diagonal = (geo.size.width * geo.size.width + geo.size.height * geo.size.height).squareRoot()
                    Circle()
                        .fill(Theme.Colors.accent)
                        .frame(width: diagonal * 2, height: diagonal * 2)
                        .scaleEffect(Self.washScale(t))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                Text("SwiftUp")
                    .font(Theme.Fonts.heading(Self.wordmarkSize))
                    .tracking(Self.wordmarkTracking(t))
                    .foregroundStyle(Self.wordmarkColor(t))
            }
            .ignoresSafeArea()
            .onChange(of: t >= 1) { _, finished in
                guard finished, !didFinish else { return }
                didFinish = true
                onFinished()
            }
        }
    }

    private func progress(at date: Date) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(startDate) / Self.duration, 0), 1))
    }

    // MARK: - Keyframe evaluation
    //
    // Mirrors the design's CSS @keyframes 1:1 by percentage of the 4.2s cycle —
    // each transitioning segment below corresponds to one keyframe-to-keyframe
    // span in the source. `eased` approximates the design's
    // cubic-bezier(.65,0,.35,1); an exact bezier solve isn't worth it for a
    // splash screen, so this trades perfect curve fidelity for a simple,
    // verifiable smoothstep that reads the same by eye.

    private static func eased(_ localT: CGFloat) -> CGFloat {
        let c = min(max(localT, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Progress through the [start, end] window of the 4.2s cycle, eased. 0 before
    /// `start`, 1 after `end`.
    private static func segment(_ t: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return t < start ? 0 : 1 }
        return eased((t - start) / (end - start))
    }

    /// swp-ry: 0%{scale:0} 14%,100%{scale:1}
    private static func yellowScale(_ t: CGFloat) -> CGFloat {
        segment(t, from: 0, to: 0.14)
    }

    /// swp-rk: 0%,32%{scale:0} 46%,100%{scale:1}
    private static func blackScale(_ t: CGFloat) -> CGFloat {
        t < 0.32 ? 0 : segment(t, from: 0.32, to: 0.46)
    }

    /// swp-fc: 0%,62%{circle 0%} 84%,100%{circle 150%} — modeled as a circle sized
    /// to the screen diagonal, scaling 0→1 to fully cover from center.
    private static func washScale(_ t: CGFloat) -> CGFloat {
        t < 0.62 ? 0 : segment(t, from: 0.62, to: 0.84)
    }

    /// swp-ink letter-spacing: 0%{.06em} 14%,32%{-.05em} (holds through the rest)
    private static func wordmarkTracking(_ t: CGFloat) -> CGFloat {
        let loose = 0.06 * wordmarkSize
        let tight = -0.05 * wordmarkSize
        return loose + (tight - loose) * segment(t, from: 0, to: 0.14)
    }

    /// swp-ink color: 0%,32%{text} 46%,62%{bg} 84%,100%{accent-100}
    private static func wordmarkColor(_ t: CGFloat) -> Color {
        if t < 0.32 {
            Theme.Colors.text
        } else if t < 0.46 {
            lerp(Theme.Colors.text, Theme.Colors.bg, segment(t, from: 0.32, to: 0.46))
        } else if t < 0.62 {
            Theme.Colors.bg
        } else if t < 0.84 {
            lerp(Theme.Colors.bg, Theme.Colors.accent100, segment(t, from: 0.62, to: 0.84))
        } else {
            Theme.Colors.accent100
        }
    }

    private static func lerp(_ a: Color, _ b: Color, _ f: CGFloat) -> Color {
        let ca = components(a), cb = components(b)
        return Color(
            red: ca.r + (cb.r - ca.r) * f,
            green: ca.g + (cb.g - ca.g) * f,
            blue: ca.b + (cb.b - ca.b) * f,
            opacity: ca.a + (cb.a - ca.a) * f
        )
    }

    private static func components(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

#Preview {
    SplashView()
}
