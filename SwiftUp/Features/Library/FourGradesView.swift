import SwiftUI

/// Reachable two ways — from `LibraryView`'s footer link, and from a row on `ProfileHomeView`.
/// Either way it's a plain pushed screen, so the `dismiss()`-based back link works correctly
/// regardless of entry point.
///
/// Rebuilt per source design turn 13 ("Four grades") as a plain ladder of seals rather than a
/// tracks-and-progress list: no track counts, no progress bar, no footer stats — the design's own
/// note calls that out explicitly ("No tracks, no stats"). Grade itself is a separate
/// status/achievement ladder now, decoupled from the Library (which no longer gates anything by
/// grade) — this screen's only job is to show where the four grades sit relative to each other and
/// which one the user is on.
struct FourGradesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryRepository.self) private var libraryRepo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("← Back") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.accent700)
                    .frame(minHeight: 44, alignment: .leading)

                EyebrowLabel("The ladder").padding(.top, 8)
                Text("Four grades").font(Theme.Fonts.heading(34)).padding(.top, 8)
                Text("Every engineer climbs the same four. A grade, once earned, is never lost.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 12)

                ZStack(alignment: .leading) {
                    // The connecting rail sits behind the rows; each icon paints its own opaque
                    // circular backing (below) so the rail reads as passing behind it rather than
                    // through it, matching the source design's layered seals.
                    Rectangle()
                        .fill(Theme.Colors.divider)
                        .frame(width: 2)
                        .padding(.vertical, 28)
                        .padding(.leading, 27)

                    VStack(spacing: 6) {
                        ForEach(Array(SkillLevel.allCases.enumerated()), id: \.element.id) { index, grade in
                            gradeRow(grade, tier: index + 1)
                        }
                    }
                }
                .padding(.top, 26)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }

    @ViewBuilder
    private func gradeRow(_ grade: SkillLevel, tier: Int) -> some View {
        let isCurrent = grade == libraryRepo.grade

        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(isCurrent ? Theme.Colors.accent100 : Theme.Colors.bg)
                GradeSealIcon(tier: tier, isCurrent: isCurrent)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(grade.displayName)
                        .font(Theme.Fonts.heading(21))
                        .foregroundStyle(isCurrent ? Theme.Colors.accent800 : Theme.Colors.text)
                    if isCurrent {
                        EyebrowLabel("You are here", color: Theme.Colors.accent700)
                    }
                }
                Text(grade.blurb)
                    .font(Theme.Fonts.body(13.5))
                    .foregroundStyle(isCurrent ? Theme.Colors.neutral800 : Theme.Colors.neutral700)
            }
        }
        .padding(.vertical, 13)
        .background(isCurrent ? Theme.Colors.accent100 : Color.clear)
        .overlay(isCurrent ? Rectangle().fill(Theme.Colors.accent).frame(width: 3) : nil, alignment: .leading)
    }
}

/// The ladder icon that gains detail as the grades rise — a plain dot, rings, a registration
/// cross, then a star for the top grade (source design turn 13's "seals" language). `isCurrent`
/// switches the mark from neutral ink to the accent color.
private struct GradeSealIcon: View {
    let tier: Int
    let isCurrent: Bool
    var size: CGFloat = 56

    private var strokeColor: Color { isCurrent ? Theme.Colors.accent : Theme.Colors.neutral400 }

    var body: some View {
        ZStack {
            switch tier {
            case 1:
                Circle().stroke(strokeColor, lineWidth: 3).padding(size * 0.065)
                centerDot
            case 2:
                Circle().stroke(strokeColor, lineWidth: 1.5).padding(size * 0.065)
                Circle().stroke(strokeColor, lineWidth: 1.5).padding(size * 0.24)
                centerDot
            case 3:
                Circle().stroke(strokeColor, lineWidth: 1.5).padding(size * 0.065)
                Circle().stroke(strokeColor, lineWidth: 1.5).padding(size * 0.24)
                Path { path in
                    path.move(to: CGPoint(x: size / 2, y: 0))
                    path.addLine(to: CGPoint(x: size / 2, y: size))
                    path.move(to: CGPoint(x: 0, y: size / 2))
                    path.addLine(to: CGPoint(x: size, y: size / 2))
                }
                .stroke(strokeColor, lineWidth: 1.2)
                centerDot
            default:
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundStyle(strokeColor)
                    .padding(size * 0.065)
                StarShape().stroke(strokeColor, lineWidth: 1.5).padding(size * 0.2)
            }
        }
        .frame(width: size, height: size)
    }

    private var centerDot: some View {
        Circle().fill(strokeColor).frame(width: size * 0.17, height: size * 0.17)
    }
}

#Preview {
    NavigationStack { FourGradesView() }
        .environment(LibraryRepository.preview())
}
