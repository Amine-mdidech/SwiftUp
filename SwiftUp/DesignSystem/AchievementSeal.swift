import SwiftUI

enum AchievementSealKind: String, Codable {
    case perfectWeek, streakMilestone, topicMastery, firstSession
}

struct StarShape: Shape {
    var points: Int = 5

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.42
        var path = Path()
        let angleStep = .pi * 2 / CGFloat(points)
        for i in 0..<points {
            let outerAngle = CGFloat(i) * angleStep - .pi / 2
            let innerAngle = outerAngle + angleStep / 2
            let outerPoint = CGPoint(
                x: center.x + cos(outerAngle) * outerRadius,
                y: center.y + sin(outerAngle) * outerRadius
            )
            let innerPoint = CGPoint(
                x: center.x + cos(innerAngle) * innerRadius,
                y: center.y + sin(innerAngle) * innerRadius
            )
            if i == 0 {
                path.move(to: outerPoint)
            } else {
                path.addLine(to: outerPoint)
            }
            path.addLine(to: innerPoint)
        }
        path.closeSubpath()
        return path
    }
}

/// A gamification badge/milestone mark, styled after the canvas's press
/// seals rather than an illustration. `filled` distinguishes an earned
/// seal (solid ink) from an in-reach one (outline only).
struct AchievementSeal: View {
    let kind: AchievementSealKind
    var filled: Bool
    var size: CGFloat = 46

    var body: some View {
        Group {
            switch kind {
            case .perfectWeek:
                ZStack {
                    Circle().stroke(Theme.Colors.accent, lineWidth: 2)
                    Circle().stroke(Theme.Colors.accent2, lineWidth: 2)
                        .padding(size * 0.17)
                    Path { p in
                        p.move(to: CGPoint(x: size / 2, y: 0))
                        p.addLine(to: CGPoint(x: size / 2, y: size))
                        p.move(to: CGPoint(x: 0, y: size / 2))
                        p.addLine(to: CGPoint(x: size, y: size / 2))
                    }.stroke(Theme.Colors.text, lineWidth: 1)
                    if filled {
                        Circle().fill(Theme.Colors.processYellow)
                            .frame(width: size * 0.17, height: size * 0.17)
                    }
                }
            case .streakMilestone:
                ZStack {
                    Circle().stroke(filled ? Theme.Colors.text : Theme.Colors.accent, lineWidth: filled ? 1 : 2)
                    if filled {
                        StarShape().fill(Theme.Colors.accent).padding(size * 0.11)
                    } else {
                        StarShape().stroke(Theme.Colors.accent, lineWidth: 1.5).padding(size * 0.11)
                    }
                }
            case .topicMastery:
                ZStack {
                    if filled {
                        Circle().fill(Theme.Colors.accent2)
                    } else {
                        Circle().stroke(Theme.Colors.accent2, lineWidth: 2)
                    }
                    Path { p in
                        p.move(to: CGPoint(x: size * 0.26, y: size / 2))
                        p.addLine(to: CGPoint(x: size * 0.74, y: size / 2))
                        p.move(to: CGPoint(x: size / 2, y: size * 0.26))
                        p.addLine(to: CGPoint(x: size / 2, y: size * 0.74))
                    }.stroke(filled ? Theme.Colors.bg : Theme.Colors.accent2, lineWidth: filled ? 3 : 2)
                }
            case .firstSession:
                ZStack {
                    Rectangle().stroke(Theme.Colors.text, lineWidth: 1)
                    if filled {
                        Rectangle().fill(Theme.Colors.processYellow)
                            .frame(width: size * 0.46, height: size * 0.46)
                            .position(x: size * 0.27, y: size * 0.27)
                        Rectangle().fill(Theme.Colors.accent)
                            .frame(width: size * 0.46, height: size * 0.46)
                            .position(x: size * 0.73, y: size * 0.73)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(kind.accessibilityName) seal, \(filled ? "earned" : "not yet earned")")
    }
}

private extension AchievementSealKind {
    var accessibilityName: String {
        switch self {
        case .perfectWeek: return "Perfect week"
        case .streakMilestone: return "Streak milestone"
        case .topicMastery: return "Topic mastery"
        case .firstSession: return "First session"
        }
    }
}

struct LockedSeal: View {
    let remainingCount: Int
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Theme.Colors.neutral400)
            Text("+\(remainingCount)")
                .font(Theme.Fonts.heading(15))
                .foregroundStyle(Theme.Colors.neutral600)
        }
        .frame(width: size, height: size)
        .opacity(0.4)
    }
}

#Preview("Seals") {
    HStack(spacing: 14) {
        AchievementSeal(kind: .perfectWeek, filled: true)
        AchievementSeal(kind: .streakMilestone, filled: true)
        AchievementSeal(kind: .streakMilestone, filled: false)
        AchievementSeal(kind: .topicMastery, filled: true)
        AchievementSeal(kind: .firstSession, filled: true)
        LockedSeal(remainingCount: 5)
    }
    .padding()
    .background(Theme.Colors.bg)
}
