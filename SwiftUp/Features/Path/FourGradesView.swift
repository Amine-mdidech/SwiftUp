import SwiftUI

/// Reachable two ways — from `PathWheelView`'s footer link, and from a new row on
/// `ProfileHomeView` (Task 6). Either way it's a plain pushed screen, so the `dismiss()`-based
/// back link works correctly regardless of entry point.
///
/// Two of the source design's four footer stats ("this week's xp", the regrade-by-date
/// projection) have no backing data anywhere in this codebase and are intentionally dropped
/// rather than faked — see design doc §7.
struct FourGradesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PathRepository.self) private var pathRepo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("← Back") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.accent700)
                    .frame(minHeight: 44, alignment: .leading)

                Text("Four grades").font(Theme.Fonts.heading(32)).padding(.top, 8)
                Text("Your assessment placed you at \(pathRepo.grade.rawValue). Each grade opens when its tracks are all closed.")
                    .font(Theme.Fonts.body(14))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 10)

                VStack(spacing: 11) {
                    ForEach(SkillLevel.allCases) { grade in
                        gradeRow(grade)
                    }
                }
                .padding(.top, 22)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        EyebrowLabel("Tracks closed")
                        Text("\(totalClosed) of \(totalTracks)").font(Theme.Fonts.heading(21))
                    }
                }
                .padding(.top, 22)
                .padding(.top, 14)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                Text("A grade never drops.")
                    .font(Theme.Fonts.body(12.5))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 16)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
    }

    private var totalTracks: Int { pathRepo.tracks.count }
    private var totalClosed: Int { pathRepo.tracks.filter(pathRepo.isTrackClosed).count }

    private func closedCount(for grade: SkillLevel) -> Int {
        pathRepo.tracks(for: grade).filter(pathRepo.isTrackClosed).count
    }

    private func topicList(for grade: SkillLevel) -> String {
        let titles = pathRepo.tracks(for: grade).map(\.title)
        guard !titles.isEmpty else { return "" }
        return titles.joined(separator: ", ") + "."
    }

    @ViewBuilder
    private func gradeRow(_ grade: SkillLevel) -> some View {
        let isCurrent = grade == pathRepo.grade
        let tracksInGrade = pathRepo.tracks(for: grade).count
        let closed = closedCount(for: grade)

        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(grade.rawValue).font(Theme.Fonts.heading(19))
                Spacer()
                if isCurrent {
                    EyebrowLabel("You are here", color: Theme.Colors.accent700)
                } else {
                    EyebrowLabel("\(tracksInGrade) tracks")
                }
            }
            Text(topicList(for: grade))
                .font(Theme.Fonts.body(13))
                .foregroundStyle(Theme.Colors.neutral800)
            if isCurrent && tracksInGrade > 0 {
                ThinProgressBar(fraction: Double(closed) / Double(tracksInGrade), trackColor: Theme.Colors.neutral300, height: 7)
                    .padding(.top, 6)
            }
        }
        .padding(isCurrent ? 13 : 0)
        .padding(.vertical, isCurrent ? 0 : 13)
        .background(isCurrent ? Theme.Colors.accent100 : Color.clear)
        .overlay(isCurrent ? Rectangle().fill(Theme.Colors.accent).frame(width: 3) : nil, alignment: .leading)
        .overlay(isCurrent ? nil : Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { FourGradesView() }
        .environment(PathRepository.preview())
}
