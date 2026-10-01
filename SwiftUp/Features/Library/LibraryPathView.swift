import SwiftUI

/// Pushed from `LibraryView` when a path is tapped. Every class is freely startable except the
/// path's own assessment, which requires every other class in the path completed first
/// (`LibraryRepository.canStartClass`) — everything else here is just presentation.
struct LibraryPathView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(LibraryRepository.self) private var libraryRepo
    @Environment(AuthRepository.self) private var authRepo
    let path: LibraryPath

    @State private var activeAttempt: ClassAttempt?
    @State private var selectedClassID: String?
    @State private var loadErrorAlert: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("← Volume \(path.grade.volumeNumeral)") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    EyebrowLabel("\(path.grade.volumeNumeral).\(path.order) · \(path.classes.count) classes")
                }
                .frame(minHeight: 44)

                Text(path.title).font(Theme.Fonts.heading(30)).padding(.top, 6)
                Text(path.summary)
                    .font(Theme.Fonts.body(14))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 6)

                sealProgressBlock
                    .padding(.top, 16)

                HStack {
                    EyebrowLabel("Contents")
                    Spacer()
                    Text("\(completedCount)/\(path.classes.count)")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 18)

                VStack(spacing: 0) {
                    ForEach(path.classes) { libClass in
                        classRow(libClass)
                    }
                }
                .padding(.top, 6)

                if let focusedClass {
                    Button(action: { open(focusedClass) }) {
                        Text(startButtonTitle(for: focusedClass))
                            .font(Theme.Fonts.heading(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.top, 20)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationBarBackButtonHidden()
        .navigationDestination(item: $activeAttempt) { attempt in
            if attempt.libClass.kind == .assessment {
                LibraryQuizView(
                    title: attempt.libClass.title,
                    questions: attempt.content.quiz,
                    onPassed: { isPerfect in await complete(attempt.libClass, isPerfect: isPerfect) },
                    onFinished: { activeAttempt = nil },
                    onAbandon: { activeAttempt = nil }
                )
            } else {
                ClassArticleView(
                    path: path, libClass: attempt.libClass, content: attempt.content,
                    onPassed: { isPerfect in await complete(attempt.libClass, isPerfect: isPerfect) },
                    onFinished: { activeAttempt = nil },
                    onAbandon: { activeAttempt = nil }
                )
            }
        }
        .alert("Couldn't load this class", isPresented: $loadErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This class's content isn't available right now. Try again in a moment.")
        }
    }

    private var sealed: Bool { libraryRepo.isPathSealed(path) }
    private var completedCount: Int { path.classes.filter(libraryRepo.isClassCompleted).count }
    private var perfectCount: Int { path.classes.filter(libraryRepo.isClassPerfect).count }
    private var totalXP: Int { path.classes.reduce(0) { $0 + $1.xpReward } }
    private var remainingXP: Int { path.classes.filter { !libraryRepo.isClassCompleted($0) }.reduce(0) { $0 + $1.xpReward } }
    private var nextClass: LibraryClass? { path.classes.first { !libraryRepo.isClassCompleted($0) } }
    /// The class the bottom button starts: whichever row the user tapped, else the next class.
    private var focusedClass: LibraryClass? {
        path.classes.first { $0.id == selectedClassID } ?? nextClass
    }

    private func startButtonTitle(for libClass: LibraryClass) -> String {
        let number = String(format: "%02d", libClass.order)
        if libraryRepo.isClassCompleted(libClass) { return "Review class \(number)" }
        if libraryRepo.isClassStarted(libClass) { return "Continue class \(number)" }
        return "Start class \(number)"
    }

    private var sealProgressBlock: some View {
        HStack(alignment: .center, spacing: 14) {
            PathSealIcon(isSealed: sealed, fraction: sealFraction, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                EyebrowLabel("The \(path.title) seal", color: Theme.Colors.accent700)
                Text(sealed ? "Sealed" : remainingSummary)
                    .font(Theme.Fonts.heading(17))
                Text("+\(sealed ? totalXP : remainingXP) xp · \(perfectCount) of \(path.classes.count) perfect so far")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
    }

    private var remainingSummary: String {
        let left = path.classes.count - completedCount
        return left == 1 ? "One class to strike it" : "\(left) classes to strike it"
    }

    private var sealFraction: Double {
        path.classes.isEmpty ? 0 : Double(completedCount) / Double(path.classes.count)
    }

    @ViewBuilder
    private func classRow(_ libClass: LibraryClass) -> some View {
        let completed = libraryRepo.isClassCompleted(libClass)
        let started = libraryRepo.isClassStarted(libClass)
        let perfect = libraryRepo.isClassPerfect(libClass)
        let isNext = libClass.id == nextClass?.id
        let isFocused = libClass.id == focusedClass?.id
        let canStart = libraryRepo.canStartClass(libClass, in: path)

        let row = HStack(spacing: 11) {
            Text(String(format: "%02d", libClass.order))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.neutral700)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(libClass.title)
                    .font(isFocused ? Theme.Fonts.heading(15) : Theme.Fonts.body(14))
                    .foregroundStyle(canStart ? Theme.Colors.text : Theme.Colors.neutral400)
                if isNext {
                    EyebrowLabel("Up next", color: Theme.Colors.accent700)
                } else if !canStart {
                    Text("Finish the other classes first")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
            }
            Spacer()
            if libClass.kind == .assessment {
                Text("Strikes the seal")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.neutral700)
            } else {
                HStack(spacing: 8) {
                    stampDot(filled: started, color: Theme.Colors.text)
                    stampDot(filled: completed, color: Theme.Colors.accent)
                    ZStack {
                        if perfect {
                            StarShape().fill(Theme.Colors.processYellow)
                        } else {
                            StarShape().stroke(Theme.Colors.neutral300, lineWidth: 1.6)
                        }
                    }
                    .frame(width: 13, height: 13)
                }
            }
        }
        .padding(.vertical, isFocused ? 10 : 9)
        .padding(.horizontal, isFocused ? 9 : 0)
        .background(isFocused ? Theme.Colors.accent100 : Color.clear)
        .overlay(isFocused ? Rectangle().fill(Theme.Colors.accent).frame(width: 3) : nil, alignment: .leading)
        .opacity(canStart ? 1 : 0.55)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)

        if canStart {
            Button(action: { selectedClassID = libClass.id }) { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func stampDot(filled: Bool, color: Color) -> some View {
        Circle()
            .strokeBorder(filled ? color : Theme.Colors.neutral300, lineWidth: filled ? 0 : 1.5)
            .background(Circle().fill(filled ? color : Color.clear))
            .frame(width: 12, height: 12)
    }

    private func open(_ libClass: LibraryClass) {
        guard let uid = authRepo.currentUser?.uid else { return }
        Task {
            await libraryRepo.markClassStarted(libClass, for: uid)
            guard let content = await libraryRepo.fetchClassContent(for: libClass) else {
                loadErrorAlert = true
                return
            }
            activeAttempt = ClassAttempt(libClass: libClass, content: content)
        }
    }

    private func complete(_ libClass: LibraryClass, isPerfect: Bool) async {
        guard let uid = authRepo.currentUser?.uid else { return }
        let result = await libraryRepo.completeClass(libClass, isPerfectScore: isPerfect, for: uid)
        if result.xpAwarded > 0 {
            profileRepo.applyExternalXPEarn(result.xpAwarded)
        }
    }
}

/// Bundles a class with the content already fetched for it, so the single
/// `.navigationDestination(item:)` above has everything it needs to route to the article (lesson)
/// or straight to a quiz (assessment) without a second async fetch mid-navigation.
private struct ClassAttempt: Identifiable, Hashable {
    let libClass: LibraryClass
    let content: LibraryClassContent
    var id: String { libClass.id }
}

#Preview {
    let libraryRepo = LibraryRepository.preview()
    let path = libraryRepo.paths(for: .junior)[1] // junior-02, "Object-oriented Swift"
    return NavigationStack {
        LibraryPathView(path: path)
    }
    .environment(ProfileRepository.preview())
    .environment(libraryRepo)
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
