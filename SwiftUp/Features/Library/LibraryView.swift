import SwiftUI

/// Root screen of the Library tab. Unlike the old Path wheel, this isn't scoped to the user's own
/// grade — any volume is browsable regardless of which grade the user is actually assigned (grade
/// gates nothing here; see `LibraryRepository.canStartClass`'s doc comment). `selectedVolume`
/// starts on the user's own grade purely as a sensible default, not a restriction.
struct LibraryView: View {
    @Environment(LibraryRepository.self) private var libraryRepo
    @Environment(AuthRepository.self) private var authRepo
    @State private var selectedVolume: SkillLevel?
    @State private var selectedPath: LibraryPath?

    var body: some View {
        Group {
            if libraryRepo.isLoading && libraryRepo.paths.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else {
                content
            }
        }
        .background(Theme.Colors.bg)
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await libraryRepo.load(for: uid)
        }
    }

    private var displayedVolume: SkillLevel { selectedVolume ?? libraryRepo.grade }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    EyebrowLabel("The library")
                    Spacer()
                    sealsCounterChip
                }
                .frame(minHeight: 44)

                Text("The SwiftUp\nencyclopedia").font(Theme.Fonts.heading(30)).padding(.top, 6)
                Text("Twenty paths, open to everyone. Finish every class in a path to strike its seal.")
                    .font(Theme.Fonts.body(14.5))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 10)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(SkillLevel.allCases) { grade in
                        volumeCell(grade)
                    }
                }
                .padding(.top, 20)

                HStack(alignment: .firstTextBaseline) {
                    EyebrowLabel("Volume \(displayedVolume.volumeNumeral) · \(displayedVolume.volumeSubtitle)")
                    Spacer()
                    EyebrowLabel("\(sealedCount(in: displayedVolume)) of \(volumePaths.count) sealed")
                }
                .padding(.top, 22)

                VStack(spacing: 0) {
                    ForEach(volumePaths) { path in
                        pathRow(path)
                    }
                }
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .navigationDestination(item: $selectedPath) { path in
            LibraryPathView(path: path)
        }
    }

    private var sealsCounterChip: some View {
        HStack(spacing: 7) {
            StarShape().fill(Theme.Colors.processYellow).frame(width: 14, height: 14)
            Text("\(totalSealedCount) / \(libraryRepo.paths.count) seals").font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.text, lineWidth: 1.5))
    }

    private var totalSealedCount: Int { libraryRepo.paths.filter(libraryRepo.isPathSealed).count }
    private var volumePaths: [LibraryPath] { libraryRepo.paths(for: displayedVolume) }

    private func sealedCount(in grade: SkillLevel) -> Int {
        libraryRepo.paths(for: grade).filter(libraryRepo.isPathSealed).count
    }

    @ViewBuilder
    private func volumeCell(_ grade: SkillLevel) -> some View {
        let isSelected = grade == displayedVolume
        let gradePaths = libraryRepo.paths(for: grade)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(grade.volumeNumeral).font(Theme.Fonts.heading(20))
                Spacer()
                Text("\(sealedCount(in: grade))/\(gradePaths.count)").font(.system(size: 10.5, weight: .semibold))
            }
            Spacer(minLength: 8)
            Text(grade.displayName).font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
            HStack(spacing: 2) {
                ForEach(gradePaths) { path in
                    Rectangle().fill(pipColor(for: path, isSelectedCell: isSelected)).frame(height: 4)
                }
            }
            .padding(.top, 6)
        }
        .padding(9)
        .frame(height: 86)
        .background(isSelected ? Theme.Colors.text : Color.clear)
        .foregroundStyle(isSelected ? Theme.Colors.bg : Theme.Colors.text)
        .overlay(Rectangle().stroke(isSelected ? Theme.Colors.text : Theme.Colors.divider, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedVolume = grade }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func pipColor(for path: LibraryPath, isSelectedCell: Bool) -> Color {
        if libraryRepo.isPathSealed(path) {
            return isSelectedCell ? Theme.Colors.processYellow : Theme.Colors.text
        }
        return isSelectedCell ? Theme.Colors.neutral700 : Theme.Colors.neutral200
    }

    private func pathRow(_ path: LibraryPath) -> some View {
        let completed = path.classes.filter(libraryRepo.isClassCompleted).count
        let sealed = libraryRepo.isPathSealed(path)
        let totalXP = path.classes.reduce(0) { $0 + $1.xpReward }
        let remainingXP = path.classes.filter { !libraryRepo.isClassCompleted($0) }.reduce(0) { $0 + $1.xpReward }

        return Button(action: { selectedPath = path }) {
            HStack(alignment: .center, spacing: 12) {
                Text("\(path.grade.volumeNumeral).\(path.order)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .frame(width: 30, alignment: .leading)
                VStack(alignment: .leading, spacing: 7) {
                    Text(path.title).font(Theme.Fonts.heading(16))
                    HStack(spacing: 8) {
                        ThinProgressBar(fraction: path.classes.isEmpty ? 0 : Double(completed) / Double(path.classes.count), height: 5)
                            .frame(width: 112)
                        Text(sealed ? "Sealed · +\(totalXP) xp" : (completed > 0 ? "\(completed) of \(path.classes.count) · +\(remainingXP) xp to seal" : "\(path.classes.count) classes · +\(totalXP) xp"))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.neutral700)
                            .lineLimit(1)
                    }
                }
                Spacer()
                PathSealIcon(isSealed: sealed, fraction: path.classes.isEmpty ? 0 : Double(completed) / Double(path.classes.count), size: 34)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.text)
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environment(LibraryRepository.preview())
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
