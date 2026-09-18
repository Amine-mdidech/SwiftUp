# Path — Navigation Screens (Sub-project B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three navigation screens for the Path progression system (the per-grade wheel, the track ladder, the four-grades list), swap the tab bar so Path replaces Ranks, remove the leaderboard entirely, and integrate a "current grade" glance into Profile — all read-only against Sub-project A's already-merged data layer. No spending, no stage-taking, no regrade quiz — that's Sub-project C.

**Architecture:** Six sequenced tasks. Task 1 extends `PathRepository` with the two pieces of state/logic the new screens need (`grade`, `isTrackReachable`) that Sub-project A didn't build because nothing consumed them yet. Tasks 2-4 build increasingly-dependent, independently-previewable pieces bottom-up: the radial wheel diagram component, then the track ladder screen, then the four-grades screen — none of which touch the tab bar, so the app keeps working exactly as today throughout. Task 5 builds `PathWheelView`, which is the first thing that actually composes Tasks 2-4 together. Task 6 is the "flip the switch": tab bar swap, `MainTabView`/`RootView` wiring, Profile integration, and full leaderboard removal — done last so nothing is ever mid-migration.

**Tech Stack:** SwiftUI (iOS 17+), `@Observable`, Firebase Firestore, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-18-path-navigation-design.md`

## Global Constraints

- Nothing in this plan spends XP, completes a stage, or writes a `SkillLevel` promotion — every new screen is read-only against `PathRepository`/`ProfileRepository`. The `TrackLadderView`'s "Spend N xp · start stage M" button is a real, enabled, styled button whose action is an empty closure (`{}`) — not disabled, not hidden (unless nothing remains to spend on, per Task 4) — matching this session's established pattern for a feature whose wiring comes later.
- Three design stats have no backing data in this codebase and are dropped rather than faked: "this week's xp," the regrade-by-date projection, and any "days since Path started" figure. Do not invent placeholder numbers for these.
- Track reachability: a grade's tracks unlock strictly in order — track 1 is always reachable; track *N* (N>1) is reachable once track *N-1* is closed.
- Tests run on `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'` (the bare `name=iPhone 16` destination is ambiguous on this machine without pinning `OS=18.6`). A full-app build (no tests) instead uses `-destination 'generic/platform=iOS Simulator'`.
- Every `xcodebuild`/`xcodegen` command must run in the **foreground** — never background a build or test run.
- After adding or removing any file, run `xcodegen generate` from the repo root before building.
- Two pre-existing **untracked** files, `SwiftUp/App/SplashView.swift` and `SwiftUp/Assets.xcassets/`, belong to the user's own separate in-progress work — never commit them, and copy them into any new worktree so the baseline builds.

---

## Task 1: `PathRepository` — `grade` and `isTrackReachable`

**Files:**
- Modify: `SwiftUp/Data/PathRepository.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Produces (consumed by Tasks 2, 5, 6): `PathRepository.grade: SkillLevel` (defaults `.junior`, populated by `load(for:)`), `PathRepository.isTrackReachable(_ track: PathTrack) -> Bool`.
- Consumes: `PathTrack`/`PathStage`/`SkillLevel` (already exist from Sub-project A).

- [ ] **Step 1: Write the failing tests**

Add to `SwiftUpTests/RepositoryTests.swift` (inside `struct RepositoryTests`, near the existing `pathRepository...` tests):

```swift
    @Test func pathRepositoryFirstTrackInAGradeIsAlwaysReachable() {
        let stages = [PathStage(id: "t1-s01", order: 1, title: "One", xpCost: 50, kind: .lesson)]
        let track1 = PathTrack(id: "t1", grade: .junior, order: 1, title: "One", stages: stages)
        let repo = PathRepository()
        #expect(repo.isTrackReachable(track1) == true)
    }

    @Test func pathRepositorySecondTrackNotReachableBeforeFirstIsClosed() {
        // isTrackReachable looks up sibling tracks via `self.tracks(for:)`, which is `private(set)`
        // and only populated by `load(for:)` — with no test seam (same limitation Sub-project A's
        // isTrackClosed/isStageUnlocked tests already accepted for completedStageIDs). On a fresh,
        // never-loaded repo, `tracks(for:)` returns empty, so `track1` is invisible to `track2`'s
        // reachability check — meaning track2 correctly reads as unreachable, but for the "can't
        // see any predecessor at all" reason rather than "predecessor exists but isn't closed."
        // Both reasons produce the same `false`, which is what this test actually verifies.
        let stage2 = PathStage(id: "t2-s01", order: 1, title: "Two", xpCost: 50, kind: .lesson)
        let track2 = PathTrack(id: "t2", grade: .junior, order: 2, title: "Two", stages: [stage2])
        let repo = PathRepository()
        #expect(repo.isTrackReachable(track2) == false)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: FAIL — `isTrackReachable` doesn't exist yet (compile error).

- [ ] **Step 3: Add `isTrackReachable` and `grade` to `PathRepository`**

In `SwiftUp/Data/PathRepository.swift`, add a new stored property alongside the existing ones:

```swift
    private(set) var grade: SkillLevel = .junior
```

Add the new method, placed after `isStageUnlocked`:

```swift
    /// A track unlocks once every earlier track (by `order`) in the same grade is closed. The
    /// first track in a grade is always reachable.
    func isTrackReachable(_ track: PathTrack) -> Bool {
        tracks(for: track.grade).filter { $0.order < track.order }.allSatisfy { isTrackClosed($0) }
    }
```

Then update `load(for uid:)` to also fetch `grade`. Replace:

```swift
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        async let tracksResult = Self.fetchTracks()
        async let completedResult = Self.fetchCompletedStageIDs(uid: uid)
        let (fetchedTracks, fetchedCompleted) = await (tracksResult, completedResult)

        if fetchedTracks.isEmpty {
            tracks = Self.loadBundledFallback()
            usedBundledFallback = true
        } else {
            tracks = fetchedTracks
            usedBundledFallback = false
        }
        completedStageIDs = fetchedCompleted
    }
```

with:

```swift
    func load(for uid: String) async {
        isLoading = true
        defer { isLoading = false }

        async let tracksResult = Self.fetchTracks()
        async let completedResult = Self.fetchCompletedStageIDs(uid: uid)
        async let gradeResult = Self.fetchGrade(uid: uid)
        let (fetchedTracks, fetchedCompleted, fetchedGrade) = await (tracksResult, completedResult, gradeResult)

        if fetchedTracks.isEmpty {
            tracks = Self.loadBundledFallback()
            usedBundledFallback = true
        } else {
            tracks = fetchedTracks
            usedBundledFallback = false
        }
        completedStageIDs = fetchedCompleted
        grade = fetchedGrade
    }
```

and add the new private fetch helper, after `fetchCompletedStageIDs`:

```swift
    /// Reads the same `users/{uid}.skillLevel` field `QuestionRepository` already reads — a
    /// second, independent read of the same field, not a shared cache. That's fine: it's one
    /// cheap field read, and it keeps `PathRepository` self-contained rather than depending on
    /// `QuestionRepository`'s internal state.
    private static func fetchGrade(uid: String) async -> SkillLevel {
        guard let snapshot = try? await Firestore.firestore().collection("users").document(uid).getDocument(),
              let raw = snapshot.get("skillLevel") as? String,
              let level = SkillLevel(rawValue: raw)
        else {
            return .junior
        }
        return level
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: PASS

- [ ] **Step 5: Build and run the full suite**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator' && xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Data/PathRepository.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add PathRepository.grade and isTrackReachable"
```

---

## Task 2: `PathWheelDiagram` — the radial track-node component

**Files:**
- Create: `SwiftUp/DesignSystem/PathWheelDiagram.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathTrack`, `PathRepository.isTrackClosed`/`.isTrackReachable`/`.isStageCompleted` (Task 1), `Theme.Colors`/`Theme.Fonts`.
- Produces (consumed by Task 5): `PathWheelDiagram(tracks: [PathTrack], grade: SkillLevel, pathRepo: PathRepository, onSelectTrack: (PathTrack) -> Void)`.

- [ ] **Step 1: Write the failing test for the radial position formula**

Add to `SwiftUpTests/RepositoryTests.swift`:

```swift
    @Test func pathWheelDiagramNodePositionsAreEvenlySpacedStartingAtTwelveOClock() {
        // Mirrors PathWheelDiagram's own private nodePosition(at:) formula, verified independently
        // here as a pure-math check since the view itself isn't a natural unit-test target.
        func nodePosition(at index: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
            let angle = Angle.degrees(-90 + Double(index) * (360.0 / Double(count)))
            return CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
        }
        let center = CGPoint(x: 150, y: 150)
        let radius: CGFloat = 110

        // 5 nodes: node 0 sits directly above center (12 o'clock).
        let fiveNode0 = nodePosition(at: 0, count: 5, center: center, radius: radius)
        #expect(abs(fiveNode0.x - center.x) < 0.001)
        #expect(abs(fiveNode0.y - (center.y - radius)) < 0.001)

        // 4 nodes: node 1 sits 90° clockwise from 12 o'clock, i.e. directly right of center.
        let fourNode1 = nodePosition(at: 1, count: 4, center: center, radius: radius)
        #expect(abs(fourNode1.x - (center.x + radius)) < 0.001)
        #expect(abs(fourNode1.y - center.y) < 0.001)

        // Every node is exactly `radius` from center, for any count.
        for count in [4, 5, 6] {
            for index in 0..<count {
                let p = nodePosition(at: index, count: count, center: center, radius: radius)
                let distance = sqrt(pow(p.x - center.x, 2) + pow(p.y - center.y, 2))
                #expect(abs(distance - radius) < 0.001)
            }
        }
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:SwiftUpTests/RepositoryTests`
Expected: this specific test should actually PASS immediately, since it tests a self-contained local function, not `PathWheelDiagram` itself (which doesn't exist yet). That's fine — it's here to lock in the formula `PathWheelDiagram`'s real `nodePosition(at:)` must match exactly. Confirm it passes now, then implement Step 3 so the real component uses the identical formula.

- [ ] **Step 3: Write `PathWheelDiagram`**

Create `SwiftUp/DesignSystem/PathWheelDiagram.swift`:

```swift
import SwiftUI

/// The radial "wheel" of track nodes around a center grade-progress hub. This is a from-scratch
/// layout, not a copy of the source design's hand-positioned 5-node mockup — that doesn't
/// generalize to grades with 4 or 6 tracks. N nodes are spaced evenly on a circle starting at
/// 12 o'clock going clockwise, with spokes to the hub styled per each track's state.
struct PathWheelDiagram: View {
    let tracks: [PathTrack]
    let grade: SkillLevel
    let pathRepo: PathRepository
    let onSelectTrack: (PathTrack) -> Void

    private let canvasSize: CGFloat = 300
    private let hubDiameter: CGFloat = 80
    private let nodeDiameter: CGFloat = 60
    private let nodeRadius: CGFloat = 110

    private var center: CGPoint { CGPoint(x: canvasSize / 2, y: canvasSize / 2) }
    private var closedCount: Int { tracks.filter(pathRepo.isTrackClosed).count }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for (index, track) in tracks.enumerated() {
                    guard !pathRepo.isTrackClosed(track) else { continue } // no spoke to a cleared track
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: nodePosition(at: index))
                    if pathRepo.isTrackReachable(track) {
                        context.stroke(line, with: .color(Theme.Colors.text), lineWidth: 2)
                    } else {
                        context.stroke(line, with: .color(Theme.Colors.neutral400), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }

                let hubRect = CGRect(x: center.x - hubDiameter / 2, y: center.y - hubDiameter / 2, width: hubDiameter, height: hubDiameter)
                context.stroke(Path(ellipseIn: hubRect), with: .color(Theme.Colors.neutral200), lineWidth: 5)
                if !tracks.isEmpty {
                    let fraction = Double(closedCount) / Double(tracks.count)
                    var ring = Path()
                    ring.addArc(center: center, radius: hubDiameter / 2, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
                    context.stroke(ring, with: .color(Theme.Colors.accent), lineWidth: 5)
                }
            }
            .frame(width: canvasSize, height: canvasSize)

            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                nodeView(for: track)
                    .position(nodePosition(at: index))
            }

            VStack(spacing: 1) {
                Text(grade.next?.rawValue ?? "—")
                    .font(Theme.Fonts.heading(12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(closedCount) of \(tracks.count)")
                    .font(.system(size: 9))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            .frame(width: hubDiameter - 8, height: hubDiameter - 8)
            .background(Theme.Colors.bg)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.Colors.neutral400, style: StrokeStyle(lineWidth: 2, dash: [3, 3])))
            .position(center)
        }
        .frame(width: canvasSize, height: canvasSize)
    }

    private func nodePosition(at index: Int) -> CGPoint {
        guard !tracks.isEmpty else { return center }
        let angle = Angle.degrees(-90 + Double(index) * (360.0 / Double(tracks.count)))
        return CGPoint(
            x: center.x + nodeRadius * cos(angle.radians),
            y: center.y + nodeRadius * sin(angle.radians)
        )
    }

    @ViewBuilder
    private func nodeView(for track: PathTrack) -> some View {
        let closed = pathRepo.isTrackClosed(track)
        let reachable = pathRepo.isTrackReachable(track)
        Button {
            onSelectTrack(track)
        } label: {
            VStack(spacing: 1) {
                if closed {
                    Text("✓").font(Theme.Fonts.heading(20))
                } else {
                    Text(String(format: "%02d", track.order)).font(Theme.Fonts.heading(17))
                }
                if reachable && !closed {
                    let doneStages = track.stages.filter(pathRepo.isStageCompleted).count
                    Text("\(doneStages)/\(track.stages.count)").font(.system(size: 9.5))
                }
            }
            .frame(width: nodeDiameter, height: nodeDiameter)
            .background(nodeBackground(closed: closed, reachable: reachable))
            .foregroundStyle(nodeForeground(closed: closed, reachable: reachable))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(reachable && !closed ? Theme.Colors.accent : Color.clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .disabled(!reachable)
    }

    private func nodeBackground(closed: Bool, reachable: Bool) -> Color {
        if closed { return Theme.Colors.text }
        if reachable { return Theme.Colors.accent100 }
        return Theme.Colors.neutral200
    }

    private func nodeForeground(closed: Bool, reachable: Bool) -> Color {
        if closed { return Theme.Colors.bg }
        if reachable { return Theme.Colors.accent700 }
        return Theme.Colors.neutral700
    }
}

#Preview {
    let repo = PathRepository.preview()
    let tracks = repo.tracks(for: .junior)
    return PathWheelDiagram(tracks: tracks, grade: .junior, pathRepo: repo, onSelectTrack: { _ in })
        .padding()
        .background(Theme.Colors.bg)
}
```

- [ ] **Step 4: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/DesignSystem/PathWheelDiagram.swift SwiftUpTests/RepositoryTests.swift
git commit -m "Add PathWheelDiagram, the radial track-node component"
```

---

## Task 3: `TrackLadderView`

**Files:**
- Create: `SwiftUp/Features/Path/TrackLadderView.swift`

**Interfaces:**
- Consumes: `PathTrack`/`PathStage`, `PathRepository` (Task 1), `RuledMasthead`/`EyebrowLabel`/`ThinProgressBar` (existing `DesignSystem` atoms), `PlateNumeral` (existing).
- Produces (consumed by Task 5): `TrackLadderView(track: PathTrack)`.

- [ ] **Step 1: Write `TrackLadderView`**

Create `SwiftUp/Features/Path/TrackLadderView.swift`:

```swift
import SwiftUI

/// Pushed from `PathWheelView` when a reachable or closed track is tapped. Read-only for this
/// pass — the "Spend N xp · start stage M" button is a real, styled, enabled button whose action
/// is an empty closure; spending and taking a stage's slides+quiz is a later sub-project's job.
struct TrackLadderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(PathRepository.self) private var pathRepo
    let track: PathTrack

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button("← The wheel") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    xpBalanceChip
                }
                .frame(minHeight: 44)

                HStack(alignment: .center, spacing: 14) {
                    Text(String(format: "%02d", track.order))
                        .font(Theme.Fonts.heading(19))
                        .frame(width: 56, height: 56)
                        .background(Theme.Colors.accent100)
                        .foregroundStyle(Theme.Colors.accent700)
                        .overlay(Circle().strokeBorder(Theme.Colors.accent, lineWidth: 3))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel("Track \(String(format: "%02d", track.order)) of \(String(format: "%02d", totalTracksInGrade))")
                        Text(track.title).font(Theme.Fonts.heading(22))
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 4) {
                    ForEach(Array(track.stages.enumerated()), id: \.element.id) { index, stage in
                        Rectangle()
                            .fill(segmentColor(for: stage, index: index))
                            .frame(height: 8)
                    }
                }
                .padding(.top, 16)

                HStack {
                    EyebrowLabel("\(closedStageCount) cleared · \(bankedXP) xp banked")
                    Spacer()
                    EyebrowLabel("\(track.stages.count - closedStageCount) to go", color: Theme.Colors.accent700)
                }
                .padding(.top, 7)

                VStack(spacing: 0) {
                    ForEach(track.stages) { stage in
                        stageRow(stage)
                    }
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(remainingSummary)
                            .font(Theme.Fonts.body(13.5))
                            .foregroundStyle(Theme.Colors.neutral800)
                        Spacer()
                        Text("\(remainingXP) xp")
                            .font(Theme.Fonts.heading(15))
                    }
                    HStack(spacing: 3) {
                        Rectangle().fill(Theme.Colors.accent).frame(height: 7)
                            .frame(width: closedFraction * 200)
                        Rectangle().fill(Theme.Colors.neutral200).frame(height: 7)
                    }
                    HStack {
                        EyebrowLabel("\(remainingXP) to close", color: Theme.Colors.accent700)
                        Spacer()
                        EyebrowLabel("\(profileRepo.profile.xpBalance) held")
                    }
                }
                .padding(.top, 16)
                .padding(.top, 14)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                if let nextStage {
                    Button(action: {}) {
                        Text("Spend \(nextStage.xpCost) xp · start stage \(String(format: "%02d", nextStage.order))")
                            .font(Theme.Fonts.heading(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                    .padding(.top, 16)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    private var xpBalanceChip: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.Colors.processYellow).frame(width: 10, height: 10)
            Text("\(profileRepo.profile.xpBalance)").font(Theme.Fonts.heading(15)).foregroundStyle(Theme.Colors.accent700)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Theme.Colors.accent100)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.Colors.accent, lineWidth: 1.5))
    }

    private var totalTracksInGrade: Int { pathRepo.tracks(for: track.grade).count }
    private var closedStageCount: Int { track.stages.filter(pathRepo.isStageCompleted).count }
    private var bankedXP: Int { track.stages.filter(pathRepo.isStageCompleted).reduce(0) { $0 + $1.xpCost } }
    private var remainingXP: Int { track.stages.filter { !pathRepo.isStageCompleted($0) }.reduce(0) { $0 + $1.xpCost } }
    private var closedFraction: CGFloat {
        guard !track.stages.isEmpty else { return 0 }
        return CGFloat(closedStageCount) / CGFloat(track.stages.count)
    }
    private var remainingSummary: String {
        let left = track.stages.count - closedStageCount
        return left == 1 ? "One stage left to close the track" : "\(left) stages left to close the track"
    }
    private var nextStage: PathStage? {
        track.stages.first { !pathRepo.isStageCompleted($0) }
    }

    private func segmentColor(for stage: PathStage, index: Int) -> Color {
        if pathRepo.isStageCompleted(stage) { return Theme.Colors.text }
        if stage.id == nextStage?.id { return Theme.Colors.accent }
        return Theme.Colors.neutral200
    }

    @ViewBuilder
    private func stageRow(_ stage: PathStage) -> some View {
        let closed = pathRepo.isStageCompleted(stage)
        let isNext = stage.id == nextStage?.id

        HStack(spacing: 13) {
            Group {
                if closed {
                    Text("✓").font(Theme.Fonts.heading(14))
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.text)
                        .foregroundStyle(Theme.Colors.bg)
                        .clipShape(Circle())
                } else if stage.kind == .assessment {
                    Circle()
                        .strokeBorder(Theme.Colors.neutral400, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                        .frame(width: 32, height: 32)
                        .overlay(Text(String(format: "%02d", stage.order)).font(.system(size: 11, weight: .semibold)))
                } else {
                    Text(String(format: "%02d", stage.order))
                        .font(Theme.Fonts.heading(isNext ? 13 : 12))
                        .frame(width: 32, height: 32)
                        .background(isNext ? Theme.Colors.accent100 : Theme.Colors.bg)
                        .foregroundStyle(isNext ? Theme.Colors.accent700 : Theme.Colors.neutral700)
                        .overlay(Circle().strokeBorder(isNext ? Theme.Colors.accent : Theme.Colors.divider, lineWidth: isNext ? 3 : 1.5))
                        .clipShape(Circle())
                }
            }

            Text(stage.title)
                .font(isNext ? Theme.Fonts.heading(15.5) : Theme.Fonts.body(14))
                .foregroundStyle(closed ? Theme.Colors.neutral700 : Theme.Colors.text)

            Spacer()

            Text(isNext ? "\(stage.xpCost) xp · Next" : "\(stage.xpCost) xp")
                .font(isNext ? Theme.Fonts.heading(12.5) : .system(size: 11.5))
                .foregroundStyle(isNext ? Theme.Colors.accent700 : Theme.Colors.neutral700)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, isNext ? 9 : 0)
        .background(isNext ? Theme.Colors.accent100 : Color.clear)
        .overlay(isNext ? Rectangle().fill(Theme.Colors.accent).frame(width: 3) : nil, alignment: .leading)
    }
}

#Preview {
    let pathRepo = PathRepository.preview()
    let track = pathRepo.tracks(for: .junior)[1] // junior-02, "Object-oriented Swift"
    return NavigationStack {
        TrackLadderView(track: track)
    }
    .environment(ProfileRepository.preview())
    .environment(pathRepo)
}
```

- [ ] **Step 2: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: all tests pass (no new tests in this task — it's a pure view built entirely on Task 1's already-tested logic).

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/Path/TrackLadderView.swift
git commit -m "Add TrackLadderView"
```

---

## Task 4: `FourGradesView`

**Files:**
- Create: `SwiftUp/Features/Path/FourGradesView.swift`

**Interfaces:**
- Consumes: `SkillLevel`, `PathRepository` (Task 1).
- Produces (consumed by Task 5 and Task 6's Profile integration): `FourGradesView()`.

- [ ] **Step 1: Write `FourGradesView`**

Create `SwiftUp/Features/Path/FourGradesView.swift`:

```swift
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
                Button("← The path") { dismiss() }
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
    }

    private var totalTracks: Int { pathRepo.tracks.count }
    private var totalClosed: Int { pathRepo.tracks.filter(pathRepo.isTrackClosed).count }

    private func closedCount(for grade: SkillLevel) -> Int {
        pathRepo.tracks(for: grade).filter(pathRepo.isTrackClosed).count
    }

    private func topicList(for grade: SkillLevel) -> String {
        pathRepo.tracks(for: grade).map(\.title).joined(separator: ", ") + "."
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
                HStack(spacing: 3) {
                    Rectangle().fill(Theme.Colors.accent).frame(height: 7)
                        .frame(width: CGFloat(closed) / CGFloat(tracksInGrade) * 200)
                    Rectangle().fill(Theme.Colors.neutral300).frame(height: 7)
                }
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
```

- [ ] **Step 2: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/Path/FourGradesView.swift
git commit -m "Add FourGradesView"
```

---

## Task 5: `PathWheelView`

**Files:**
- Create: `SwiftUp/Features/Path/PathWheelView.swift`

**Interfaces:**
- Consumes: `PathWheelDiagram` (Task 2), `TrackLadderView` (Task 3), `FourGradesView` (Task 4), `PathRepository`/`ProfileRepository`/`AuthRepository`.
- Produces (consumed by Task 6): `PathWheelView(onEarnXP: () -> Void)`.

- [ ] **Step 1: Write `PathWheelView`**

Create `SwiftUp/Features/Path/PathWheelView.swift`:

```swift
import SwiftUI

/// Root screen of the Path tab. Shows the wheel for the user's current grade
/// (`pathRepo.grade`) — not a grade picker; there's no way to view an earlier or later grade's
/// wheel. When the user is Distinguished with every track closed, renders the "nothing left to
/// unlock" terminal state instead (source design turn 15a) rather than an empty wheel.
struct PathWheelView: View {
    @Environment(PathRepository.self) private var pathRepo
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(AuthRepository.self) private var authRepo
    let onEarnXP: () -> Void

    var body: some View {
        Group {
            if pathRepo.isLoading && pathRepo.tracks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.bg)
            } else if isAtTopGrade {
                topGradeContent
            } else {
                wheelContent
            }
        }
        .background(Theme.Colors.bg)
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await pathRepo.load(for: uid)
        }
    }

    private var currentGradeTracks: [PathTrack] { pathRepo.tracks(for: pathRepo.grade) }
    private var closedCount: Int { currentGradeTracks.filter(pathRepo.isTrackClosed).count }
    private var isAtTopGrade: Bool {
        pathRepo.grade == .distinguished && !currentGradeTracks.isEmpty && currentGradeTracks.allSatisfy(pathRepo.isTrackClosed)
    }

    private var wheelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowLabel("\(pathRepo.grade.rawValue) · \(closedCount) of \(currentGradeTracks.count) tracks cleared")
                        Text("The path to \(pathRepo.grade.next?.rawValue ?? "—")").font(Theme.Fonts.heading(22))
                    }
                    Spacer()
                    xpBalanceChip
                }
                .frame(minHeight: 44)

                PathWheelDiagram(
                    tracks: currentGradeTracks, grade: pathRepo.grade, pathRepo: pathRepo,
                    onSelectTrack: { selectedTrack = $0 }
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(currentGradeTracks) { track in
                        trackRow(track)
                    }
                }
                .padding(.top, 14)

                HStack(spacing: 18) {
                    Button("Earn xp →", action: onEarnXP)
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                    NavigationLink("All four grades →") { FourGradesView() }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 16)
                .padding(.top, 13)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .navigationDestination(item: $selectedTrack) { track in
            TrackLadderView(track: track)
        }
    }

    @State private var selectedTrack: PathTrack?

    private var xpBalanceChip: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.Colors.processYellow).frame(width: 10, height: 10)
            Text("\(profileRepo.profile.xpBalance)").font(Theme.Fonts.heading(15)).foregroundStyle(Theme.Colors.accent700)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Theme.Colors.accent100)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.Colors.accent, lineWidth: 1.5))
    }

    @ViewBuilder
    private func trackRow(_ track: PathTrack) -> some View {
        let closed = pathRepo.isTrackClosed(track)
        let reachable = pathRepo.isTrackReachable(track)
        let row = HStack(spacing: 11) {
            Circle()
                .fill(closed ? Theme.Colors.text : (reachable ? Theme.Colors.accent100 : Theme.Colors.neutral200))
                .overlay(Circle().strokeBorder(reachable && !closed ? Theme.Colors.accent : Color.clear, lineWidth: 2))
                .frame(width: 13, height: 13)
            Text(String(format: "%02d", track.order))
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.neutral700)
                .frame(width: 18, alignment: .leading)
            Text(track.title)
                .font(reachable && !closed ? Theme.Fonts.heading(14.5) : Theme.Fonts.body(14))
                .foregroundStyle(closed || (!reachable) ? Theme.Colors.neutral700 : Theme.Colors.text)
            Spacer()
            Text(trackTrailingLabel(track, closed: closed, reachable: reachable))
                .font(.system(size: 11.5))
                .foregroundStyle(reachable && !closed ? Theme.Colors.accent700 : Theme.Colors.neutral700)
        }
        .frame(minHeight: 44)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)

        if reachable {
            Button(action: { selectedTrack = track }) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func trackTrailingLabel(_ track: PathTrack, closed: Bool, reachable: Bool) -> String {
        if closed { return "Cleared" }
        let totalXP = track.stages.reduce(0) { $0 + $1.xpCost }
        if reachable {
            let left = track.stages.count - track.stages.filter(pathRepo.isStageCompleted).count
            return "\(left) left · \(totalXP) xp"
        }
        return "\(track.stages.count) · \(totalXP) xp"
    }

    // MARK: - Top-grade terminal state (source design turn 15a)

    private var topGradeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Theme.Colors.text).frame(height: 3)
                HStack {
                    EyebrowLabel("Distinguished Engineer")
                    Spacer()
                }
                .padding(.vertical, 7)
                Rectangle().fill(Theme.Colors.text).frame(height: 1)

                Text("Nothing left\nto unlock.").font(Theme.Fonts.heading(34)).padding(.top, 22)
                Text("All \(totalTracksEverywhere) tracks are closed and there is no grade above this one. The daily five carries on for as long as you want it to.")
                    .font(Theme.Fonts.body(15))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 14)

                HStack(alignment: .bottom, spacing: 14) {
                    gradeSeal(size: 44, filled: true)
                    gradeSeal(size: 52, filled: true)
                    gradeSeal(size: 60, filled: true)
                    distinguishedSeal(size: 76)
                }
                .padding(.top, 26)

                HStack(alignment: .bottom, spacing: 18) {
                    PlateNumeral("\(totalTracksEverywhere)", font: Theme.Fonts.heading(64))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("tracks closed").font(Theme.Fonts.heading(16))
                        Text("\(profileRepo.profile.xp) xp").font(Theme.Fonts.body(12.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.top, 24)
                .padding(.top, 14)
                .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)

                EyebrowLabel("What carries on").padding(.top, 20)
                VStack(spacing: 0) {
                    Button(action: onEarnXP) {
                        HStack {
                            Text("The daily five, still there").font(Theme.Fonts.body(14.5)).foregroundStyle(Theme.Colors.text)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    NavigationLink { InterviewBankView() } label: {
                        HStack {
                            Text("The interview bank, every grade").font(Theme.Fonts.body(14.5)).foregroundStyle(Theme.Colors.text)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                }
                .padding(.top, 10)

                Text("Your xp keeps counting, though there is nothing left to spend it on. There was never anything to buy.")
                    .font(Theme.Fonts.body(12.5))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 14)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }

    private var totalTracksEverywhere: Int { pathRepo.tracks.count }

    private func gradeSeal(size: CGFloat, filled: Bool) -> some View {
        ZStack {
            Circle().fill(Theme.Colors.text)
            Path { path in
                path.move(to: CGPoint(x: size * 0.326, y: size * 0.511))
                path.addLine(to: CGPoint(x: size * 0.446, y: size * 0.631))
                path.addLine(to: CGPoint(x: size * 0.674, y: size * 0.402))
            }
            .stroke(Theme.Colors.bg, lineWidth: 3)
        }
        .frame(width: size, height: size)
    }

    private func distinguishedSeal(size: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(Theme.Colors.accent, lineWidth: 3)
                .frame(width: size, height: size)
            Circle().strokeBorder(Theme.Colors.accent2, lineWidth: 3)
                .frame(width: size * 13 / 23, height: size * 13 / 23)
            Path { path in
                path.move(to: CGPoint(x: size / 2, y: 0))
                path.addLine(to: CGPoint(x: size / 2, y: size))
                path.move(to: CGPoint(x: 0, y: size / 2))
                path.addLine(to: CGPoint(x: size, y: size / 2))
            }
            .stroke(Theme.Colors.text, lineWidth: 1.2)
            Circle().fill(Theme.Colors.processYellow)
                .frame(width: size * 5 / 23, height: size * 5 / 23)
        }
        .frame(width: size, height: size)
    }
}

#Preview("Mid-grade") {
    NavigationStack {
        PathWheelView(onEarnXP: {})
    }
    .environment(PathRepository.preview())
    .environment(ProfileRepository.preview())
    .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

Note: `.navigationDestination(item:)` requires `PathTrack` to be `Hashable` for the binding to work correctly with SwiftUI's identity tracking — `PathTrack` is currently only `Codable, Identifiable`. Add `Hashable` conformance to `PathTrack` in `SwiftUp/Models/PathTrack.swift` (and to `PathStage` too, since `PathTrack.stages: [PathStage]` needs to be `Hashable` for `PathTrack` itself to synthesize `Hashable` automatically):

```swift
struct PathStage: Codable, Identifiable, Hashable {
```
```swift
struct PathTrack: Codable, Identifiable, Hashable {
```
(Both structs' stored properties are all already `Hashable`-conforming types — `String`, `Int`, `SkillLevel` (an enum with a `String` raw value, `Hashable` for free), `PathStage.Kind` (same) — so adding the conformance is a zero-risk, compiler-synthesized addition, not something requiring custom `==`/`hash(into:)`.)

- [ ] **Step 2: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/Path/PathWheelView.swift SwiftUp/Models/PathTrack.swift
git commit -m "Add PathWheelView, including the top-grade terminal state"
```

---

## Task 6: Tab bar swap, `RootView`/`MainTabView`/Profile wiring, leaderboard removal

**Files:**
- Modify: `SwiftUp/DesignSystem/CustomTabBar.swift`
- Modify: `SwiftUp/App/MainTabView.swift`
- Modify: `SwiftUp/App/RootView.swift`
- Modify: `SwiftUp/Features/Profile/ProfileHomeView.swift`
- Delete: `SwiftUp/Features/Leaderboard/LeaderboardView.swift`
- Delete: `SwiftUp/Data/LeaderboardRepository.swift`
- Delete: `SwiftUp/Data/LeaderboardRanking.swift`
- Delete: `SwiftUp/Models/LeaderboardEntry.swift`
- Delete: `SwiftUp/Models/LeaderboardRecord.swift`
- Delete: `SwiftUp/Resources/leaderboard.json`
- Delete: `SwiftUpTests/Fixtures/leaderboard.json`
- Delete: `SwiftUpTests/LeaderboardRankingTests.swift`
- Modify: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: `PathWheelView` (Task 5), `FourGradesView` (Task 4).
- Produces: nothing further downstream — this is the last task in this plan.

- [ ] **Step 1: Delete every leaderboard file**

```bash
git rm SwiftUp/Features/Leaderboard/LeaderboardView.swift \
       SwiftUp/Data/LeaderboardRepository.swift \
       SwiftUp/Data/LeaderboardRanking.swift \
       SwiftUp/Models/LeaderboardEntry.swift \
       SwiftUp/Models/LeaderboardRecord.swift \
       SwiftUp/Resources/leaderboard.json \
       SwiftUpTests/Fixtures/leaderboard.json \
       SwiftUpTests/LeaderboardRankingTests.swift
```

If the `Leaderboard` directory under `SwiftUp/Features/` is now empty, that's fine — it's just an unused folder, no need to explicitly remove it (XcodeGen's directory glob doesn't care about empty folders).

- [ ] **Step 2: Remove the leaderboard test from `RepositoryTests.swift`**

In `SwiftUpTests/RepositoryTests.swift`, find and delete this whole test (it references the now-deleted `LeaderboardRepository`):

```swift
    @Test func leaderboardRepositoryPreviewLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository.preview(bundle: testBundle)
        #expect(repo.topEntries.count == 8)
        #expect(repo.topEntries.first?.rank == 1)
        #expect(repo.topEntries.first?.totalXP == 640)
    }
```

- [ ] **Step 3: Swap `AppTab.ranks` for `.path` and add the `PathIcon`**

In `SwiftUp/DesignSystem/CustomTabBar.swift`, replace:

```swift
enum AppTab: String, CaseIterable {
    case today = "Today"
    case prep = "Prep"
    case ranks = "Ranks"
    case record = "Record"
}
```

with:

```swift
enum AppTab: String, CaseIterable {
    case today = "Today"
    case prep = "Prep"
    case path = "Path"
    case record = "Record"
}
```

Replace:

```swift
        switch tab {
        case .today: TodayIcon()
        case .prep: PrepIcon()
        case .ranks: RanksIcon()
        case .record: RecordIcon()
        }
```

with:

```swift
        switch tab {
        case .today: TodayIcon()
        case .prep: PrepIcon()
        case .path: PathIcon()
        case .record: RecordIcon()
        }
```

Replace the whole `RanksIcon` struct:

```swift
private struct RanksIcon: View {
    var body: some View {
        Canvas { context, _ in
            context.opacity = 0.45
            context.fill(Path(CGRect(x: 2, y: 10, width: 3.6, height: 5.5)), with: .foreground)
            context.opacity = 1
            context.fill(Path(CGRect(x: 7.2, y: 6, width: 3.6, height: 9.5)), with: .foreground)
            context.opacity = 0.45
            context.fill(Path(CGRect(x: 12.4, y: 2.5, width: 3.6, height: 13)), with: .foreground)
        }
    }
}
```

with `PathIcon` — a branching-path glyph traced from the design's own Path tab icon (turns 14a/14b/15a all use this same icon for this tab):

```swift
private struct PathIcon: View {
    var body: some View {
        Canvas { context, _ in
            var stem = Path()
            stem.move(to: CGPoint(x: 9, y: 15.5))
            stem.addLine(to: CGPoint(x: 9, y: 10.5))
            context.stroke(stem, with: .foreground, lineWidth: 1.5)

            var leftBranch = Path()
            leftBranch.move(to: CGPoint(x: 9, y: 10.5))
            leftBranch.addLine(to: CGPoint(x: 3.5, y: 10.5))
            leftBranch.addLine(to: CGPoint(x: 3.5, y: 6))
            context.stroke(leftBranch, with: .foreground, lineWidth: 1.5)

            var rightBranch = Path()
            rightBranch.move(to: CGPoint(x: 9, y: 10.5))
            rightBranch.addLine(to: CGPoint(x: 14.5, y: 10.5))
            rightBranch.addLine(to: CGPoint(x: 14.5, y: 6))
            context.stroke(rightBranch, with: .foreground, lineWidth: 1.5)

            var bottomNode = Path()
            bottomNode.addEllipse(in: CGRect(x: 7.2, y: 14.2, width: 3.6, height: 3.6))
            context.fill(bottomNode, with: .foreground)

            context.opacity = 0.45
            var leftNode = Path()
            leftNode.addEllipse(in: CGRect(x: 1.3, y: 2.2, width: 4.4, height: 4.4))
            context.fill(leftNode, with: .foreground)

            var rightNode = Path()
            rightNode.addEllipse(in: CGRect(x: 12.3, y: 2.2, width: 4.4, height: 4.4))
            context.fill(rightNode, with: .foreground)
        }
    }
}
```

- [ ] **Step 4: Wire `PathWheelView` into `MainTabView`**

`PathWheelView` (Task 5) already owns its own navigation state internally (`@State private var selectedTrack` + `.navigationDestination(item:)`), so `MainTabView` needs no additional state of its own for this — only the tab-content swap below.

In `SwiftUp/App/MainTabView.swift`, replace:

```swift
                NavigationStack { LeaderboardView() }
                    .opacity(selectedTab == .ranks ? 1 : 0)
                    .allowsHitTesting(selectedTab == .ranks)
```

with:

```swift
                NavigationStack { PathWheelView(onEarnXP: { selectedTab = .today }) }
                    .opacity(selectedTab == .path ? 1 : 0)
                    .allowsHitTesting(selectedTab == .path)
```

Replace the `#Preview`'s `.environment(LeaderboardRepository.preview())` with `.environment(PathRepository.preview())`:

```swift
#Preview {
    MainTabView()
        .environment(QuestionRepository.preview())
        .environment(ProfileRepository.preview())
        .environment(InterviewRepository.preview())
        .environment(PathRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 5: Remove `LeaderboardRepository` from `RootView`**

In `SwiftUp/App/RootView.swift`, replace:

```swift
    @State private var questionRepository = QuestionRepository()
    @State private var profileRepository = ProfileRepository()
    @State private var interviewRepository = InterviewRepository()
    @State private var leaderboardRepository = LeaderboardRepository()
    @State private var pathRepository = PathRepository()
    @State private var authRepository = AuthRepository()
```

with:

```swift
    @State private var questionRepository = QuestionRepository()
    @State private var profileRepository = ProfileRepository()
    @State private var interviewRepository = InterviewRepository()
    @State private var pathRepository = PathRepository()
    @State private var authRepository = AuthRepository()
```

and replace:

```swift
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(leaderboardRepository)
        .environment(pathRepository)
        .environment(authRepository)
```

with:

```swift
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(pathRepository)
        .environment(authRepository)
```

- [ ] **Step 6: Update `ProfileHomeView`**

In `SwiftUp/Features/Profile/ProfileHomeView.swift`, replace:

```swift
struct ProfileHomeView: View {
    @Environment(ProfileRepository.self) private var repo
    @Environment(LeaderboardRepository.self) private var leaderboardRepo
    @Environment(AuthRepository.self) private var authRepo
```

with:

```swift
struct ProfileHomeView: View {
    @Environment(ProfileRepository.self) private var repo
    @Environment(PathRepository.self) private var pathRepo
    @Environment(AuthRepository.self) private var authRepo
```

Replace:

```swift
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await leaderboardRepo.load(for: uid)
        }
```

with:

```swift
        .task {
            guard let uid = authRepo.currentUser?.uid else { return }
            await pathRepo.load(for: uid)
        }
```

Replace:

```swift
    private var mastheadRank: String {
        guard let percentile = leaderboardRepo.myPercentile else { return "Not yet ranked" }
        return "Top \(percentile)% all-time"
    }
```

with:

```swift
    private var mastheadRank: String { pathRepo.grade.rawValue }
```

Find the existing Level row:

```swift
                HStack {
                    EyebrowLabel("\(repo.profile.xpToNextLevel) xp to level \(repo.profile.level + 1)", color: Theme.Colors.accent700)
                    Spacer()
                    NavigationLink("All 12 levels →") { AllLevelsView() }
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 10)
```

and add a matching Grade row directly after it:

```swift
                HStack {
                    EyebrowLabel("\(repo.profile.xpToNextLevel) xp to level \(repo.profile.level + 1)", color: Theme.Colors.accent700)
                    Spacer()
                    NavigationLink("All 12 levels →") { AllLevelsView() }
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 10)

                HStack {
                    EyebrowLabel("Grade: \(pathRepo.grade.rawValue)")
                    Spacer()
                    NavigationLink("All four grades →") { FourGradesView() }
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 10)
```

Finally, update the `#Preview`:

```swift
#Preview {
    NavigationStack { ProfileHomeView() }
        .environment(ProfileRepository.preview())
        .environment(PathRepository.preview())
        .environment(AuthRepository(isPreview: true, signedIn: true))
}
```

- [ ] **Step 7: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme SwiftUp -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED. If any file still references `LeaderboardRepository`/`LeaderboardView`/`AppTab.ranks`/`RanksIcon`, the build will fail with a clear "cannot find type/case in scope" error — search the whole `SwiftUp`/`SwiftUpTests` tree for any remaining reference and fix it before proceeding.

- [ ] **Step 8: Run the full test suite**

Run: `xcodebuild test -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 9: Manual verification in the simulator**

Nothing here is unit-testable end-to-end (this is UI navigation) — the same limitation this session has accepted for every other UI feature (no iOS Simulator automation tool). Build and run, then check:
1. The tab bar's 3rd tab reads "Path" with the new branching-path icon, not "Ranks."
2. Tapping it shows the wheel for your current grade (Junior, for a fresh test account), with track 1 shown reachable/current and the rest locked.
3. Tapping the reachable track pushes the track ladder, showing its stages and the (inert) "Spend N xp · start stage 01" button.
4. "← The wheel" returns correctly.
5. "All four grades →" (from both the wheel and Profile's new "Grade" row) shows all 4 grades with Junior highlighted as current.
6. Profile's masthead now shows your grade name instead of a leaderboard percentile.
7. Confirm nothing else references the old Ranks tab or leaderboard anywhere in the app.

Report any mismatch before proceeding.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "Swap Ranks for Path in the tab bar, remove the leaderboard, add Profile grade integration"
```
