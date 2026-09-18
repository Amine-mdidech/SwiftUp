# Path — Navigation Screens (Sub-project B) — Design

Source design: Claude Design project "SwiftUP" (`SwiftUp Daily Quiz.dc.html`), turns `t13`/`13c` ("Four grades"), `t14`/`14a`/`14b` ("The path — node trail and xp economy"), `t15`/`15a` ("Distinguished engineer — the path, finished"). Builds directly on Sub-project A (`docs/superpowers/specs/2026-09-18-path-foundation-design.md`), already merged: `SkillLevel` (4 grades), `PathTrack`/`PathStage`, `PathRepository` (read-only, wired into `RootView`).

## 0. Scope and what changed from the original A/B/C split

The original phasing put the tab-bar swap and leaderboard removal in Sub-project C, paired with the actual gameplay loop. Confirmed with the user: those move into **this** sub-project instead, because without an entry point B's three screens would be unreachable in the running app. Sub-project C is now purely "what happens when you interact" — spending XP, taking a stage's slides+quiz, the track assessment, the grade-closing regrade quiz, and the actual `SkillLevel` promotion write. **Nothing in this spec spends XP, completes a stage, or promotes a grade** — every screen here is read-only against Sub-project A's data, exactly like A was read-only against Firestore.

Confirmed navigation shape (user's own words): "the wheel leads to the track ladder and four grades, four grades can also be accessed in profile."

## 1. Tab bar swap

`AppTab` (`SwiftUp/DesignSystem/CustomTabBar.swift`): the `.ranks` case (rawValue `"Ranks"`) becomes `.path` (rawValue `"Path"`) — same position in `CaseIterable`'s order (3rd tab, between Prep and Record), so nothing about tab ordering changes.

A new `PathIcon` line-art icon replaces `RanksIcon` in that tab position, traced from the design's own Path tab icon (turns 14a/14b/15a all use the identical icon for this slot) — a Y-shaped branching path: a stem from a small filled circle at the bottom up to a fork, splitting into two upper branches each ending in a lighter circle. Same `Canvas`-drawing technique already used for the other three tab icons (`TodayIcon`/`PrepIcon`/`RecordIcon` in the same file):

```
Stem: (9, 15.5) → (9, 10.5)
Left branch: (9, 10.5) → (3.5, 10.5) → (3.5, 6)
Right branch: (9, 10.5) → (14.5, 10.5) → (14.5, 6)
Bottom node: circle center (9, 16), r 1.8, filled, full opacity
Left branch node: circle center (3.5, 4.4), r 2.2, filled, opacity .45
Right branch node: circle center (14.5, 4.4), r 2.2, filled, opacity .45
```
(Same 18×18 coordinate space as the other three icons — stroke width 1.5 for the branch lines, matching the existing icons' convention.)

`SwiftUp/App/MainTabView.swift`: the tab's `NavigationStack { LeaderboardView() }` becomes `NavigationStack { PathWheelView() }`.

## 2. Leaderboard removal

Deleted entirely (the whole leaderboard concept is replaced by Path, not relocated):
- `SwiftUp/Features/Leaderboard/LeaderboardView.swift`
- `SwiftUp/Data/LeaderboardRepository.swift`
- `SwiftUp/Data/LeaderboardRanking.swift`
- `SwiftUp/Models/LeaderboardEntry.swift`
- `SwiftUp/Models/LeaderboardRecord.swift`
- `SwiftUp/Resources/leaderboard.json`, `SwiftUpTests/Fixtures/leaderboard.json`
- `SwiftUpTests/LeaderboardRankingTests.swift`
- `RepositoryTests.swift`'s `leaderboardRepositoryPreviewLoadsEntriesSortedByRank` test (only that one test, not the whole file)

`SwiftUp/App/RootView.swift` loses its `@State private var leaderboardRepository = LeaderboardRepository()` and the matching `.environment(leaderboardRepository)`.

**Not deleted**: `docs/superpowers/plans/2026-09-10-leaderboard.md` and `docs/superpowers/specs/2026-09-10-leaderboard-design.md` — historical record of already-completed work, not live code. Leave them alone.

## 3. `PathRepository` gains `grade`

Both new screens (and Profile) need the user's current grade. Rather than a second read path, `PathRepository.load(for:)` (already fetching the user doc for `completedPathStageIDs`) reads one more field from the same snapshot:

```swift
private(set) var grade: SkillLevel = .junior
```

set alongside `completedStageIDs` in `load(for:)`, reading `users/{uid}.skillLevel` (the same field `QuestionRepository` already reads — this is a second, independent read of the same Firestore field, not a shared cache; that's fine, it's a cheap single-field read and keeps `PathRepository` self-contained). Defaults to `.junior` if absent (a brand-new user with no `skillLevel` set yet), matching `QuestionRepository`'s own default.

This is still a read-only addition — no new write, `PathRepository` stays exactly as read-only as Sub-project A left it.

## 4. Track reachability rule

Sub-project A's spec explicitly flagged this as undecided. Resolved here: **a grade's tracks unlock strictly in order** — track 1 is always reachable once its grade is the user's current grade; track *N* (N > 1) is reachable once track *N-1* is closed (`PathRepository.isTrackClosed`). This matches the design's own example (turn 14a: track 1 cleared, track 2 reachable/current, tracks 3-5 shown locked/dashed while track 2 isn't closed yet) and is the simplest rule consistent with it.

New pure method on `PathRepository` (same style as `isStageUnlocked`):

```swift
/// A track unlocks once every earlier track (by `order`) in the same grade is closed. The first
/// track in a grade is always reachable.
func isTrackReachable(_ track: PathTrack) -> Bool {
    tracks(for: track.grade).filter { $0.order < track.order }.allSatisfy { isTrackClosed($0) }
}
```

## 5. `PathWheelView` — the tab's root screen

Shows the wheel for `pathRepo.grade` (not a grade picker — always the user's current grade; visiting an earlier or later grade's wheel isn't a feature this design supports).

**Top-grade terminal state**: when `pathRepo.grade == .distinguished` and every Distinguished track is closed (`pathRepo.tracks(for: .distinguished).allSatisfy(pathRepo.isTrackClosed)`), render turn 15a's "Nothing left to unlock" layout instead of the wheel — see §5c.

### 5a. Layout (non-terminal state, turn 14a)

Top to bottom:
- Header: `"\(grade.rawValue) · \(closedCount) of \(total) tracks cleared"` eyebrow + `"The path to \(grade.next?.rawValue ?? "—")"` heading, and an XP balance chip (`profileRepo.profile.xpBalance`, same pill styling as the design: accent-100 fill, accent border, a small circular icon + the number).
- The wheel diagram (§5b) — track nodes arranged radially around a center "regrade" hub.
- A ruled list of every track in the grade, each row: a small leading dot (filled = closed, accent-ringed = current/reachable-not-closed, neutral = locked), order number, title, and a trailing state label (`"Cleared"` / `"\(stagesLeft) left · \(xpLeft) xp"` / `"\(stageCount) · \(totalXP) xp"` for locked). Tapping a reachable-or-closed row's `NavigationLink` pushes `TrackLadderView`; a locked row is plain text, not a link.
- Footer: `"Earn xp →"` (calls the `onEarnXP: () -> Void` closure passed in from `MainTabView`, switching the tab selection to `.today`) and `"All four grades →"` (`NavigationLink` to `FourGradesView`).

### 5b. The wheel diagram — a new reusable component

The design's turn 14a hand-positions 5 nodes around a circle at fixed pixel offsets — that doesn't generalize to grades with 4 or 6 tracks. This needs a real radial-layout algorithm instead of copied coordinates:

New file `SwiftUp/DesignSystem/PathWheelDiagram.swift`. Given `tracks: [PathTrack]` (already sorted by order) and closure state from `PathRepository`:
- A fixed-size canvas (e.g. 280×280pt — smaller than the design's 354×306px mockup frame since this app's screens run 24pt-inset rather than the mockup's wider canvas, but same relative proportions).
- Center hub: an 80pt dashed circle (neutral-400, 2pt dash) showing the grade's own progress ring around it (`closedCount / total` as a stroke-dasharray fraction, accent-colored, 5pt stroke, starting at 12 o'clock like the design's `rotate(-90)`), with the next grade name + `"\(closedCount) of \(total)"` centered inside.
- N track nodes (60pt circles), evenly spaced radially starting at 12 o'clock and going clockwise: `angle_i = -90° + i * (360° / N)` for `i` in `0..<N`, at a fixed radius (110pt) from the canvas center. Node `i`'s fill/border matches the design's three states: closed (solid `Theme.Colors.text` fill, `Theme.Colors.bg` checkmark), current/reachable (accent-100 fill, 3pt accent border, order number + `"\(completedStagesInTrack)/\(totalStages)"`), locked (neutral-200 fill, order number only).
- A connecting line from the hub's edge to each node's edge: solid `Theme.Colors.text` (2pt) for the current/reachable track (only ever at most one track is both "not yet closed" and "reachable" at a time under the §4 rule — the first not-yet-closed track), dashed `Theme.Colors.neutral400` (1.5pt, 4pt dash) to every locked track. A closed track's own line is omitted (matching the design, which shows no spoke to the already-cleared track 1).

This is genuinely new custom drawing (not a copy of an existing atom) — implemented with SwiftUI `Canvas` for the lines/ring (same technique as the tab-bar icons) and `ZStack`-positioned `.offset(x:y:)` circles for the nodes themselves (nodes need to be real tappable/`NavigationLink`-capable views, not `Canvas` drawing, unlike the lines).

### 5c. Top-grade terminal state (turn 15a)

When triggered (see above): a static layout, no wheel — four grade "seals" of increasing size (Junior/Mid/Senior solid dark filled circles with a checkmark, Distinguished the full cyan/magenta/yellow registration-target icon matching the app's own icon style, already established elsewhere in this app's design system if such an icon exists, otherwise three concentric colored rings), a plate-numeral count of total tracks closed across all grades (`"20"` once everything's done) with `"tracks closed"` + `"\(totalXP) xp · \(daysSinceStart) days"` (day count: **out of scope for this pass** — no "Path started" timestamp exists anywhere in the data model; render just the xp figure and track count, drop the day count rather than inventing a fake one), a "What carries on" section linking to the Today tab (same `onEarnXP` callback) and the interview bank (`NavigationLink` to the existing interview prep root), and the closing line "Your xp keeps counting, though there is nothing left to spend it on."

## 6. `TrackLadderView` — pushed from the wheel (turn 14b)

Takes a `PathTrack`. Top to bottom:
- Header: `"← The wheel"` back link (`dismiss()`), XP balance chip (same as the wheel's).
- Track number badge + `"Track \(order) of \(total)"` + title.
- A segmented progress bar (one segment per stage: closed = `Theme.Colors.text`, the first not-yet-closed stage = `Theme.Colors.accent`, the rest = `Theme.Colors.neutral200`) with `"\(closedCount) cleared · \(xpBanked) xp banked"` / `"\(remaining) to go"` underneath.
- The stage ladder: a vertical rail (a thin divider line behind the row of circles, matching the design), one row per stage — closed (filled dark circle, checkmark), the first not-yet-closed stage (accent-ringed circle, order number, highlighted row background, `"\(xpCost) xp · Next"`), the rest (outlined circle, order number, `"\(xpCost) xp"`). The final stage (`kind == .assessment`) renders with the dashed-seal styling from the design (matching the wheel's own center-hub dashed styling) rather than a plain numbered circle, and its trailing label is `"\(xpCost) xp"` (the design's "closes the track" phrasing is decorative flavor text, not required — keep the row's own title, "Track assessment," as the description, matching the placeholder content Sub-project A generated).
- Footer: `"\(remaining) stages left to close the track"` / total remaining xp, a segmented bar (remaining-to-close vs. already-closed, matching the design), then the primary button: `"Spend \(nextStage.xpCost) xp · start stage \(nextStage.order)"`.

**The button is a no-op for this pass** (`action: {}`) — spending XP and starting a stage's slides+quiz is Sub-project C's entire job. It's rendered fully styled and enabled (not disabled/grayed) so the screen reads correctly, exactly like this session's "Make a donation" button stayed a real, enabled, empty-closure button until it was wired up later. If every stage in the track is already closed (nothing left to spend on), hide the button entirely rather than showing it disabled — there's nothing left to start.

## 7. `FourGradesView` (turn 13c)

Reachable two ways — from `PathWheelView`'s footer link, and as a new row in `ProfileHomeView` (§8). Either way it's a plain pushed screen (`NavigationLink`), so the existing `dismiss()`-based `"← Back"` link works correctly regardless of which screen pushed it — no special-casing needed per entry point.

Content: heading, one row per grade (Junior/Mid/Senior/Distinguished) — the current grade highlighted (accent-100 background, left accent border, `"You are here"` tag) with its own tracks-closed segmented bar; every other grade shows only its topic list and track count (`"\(N) tracks"`), matching the design's minimal treatment for not-yet-reached grades. Footer stats: total tracks closed across all grades (`"\(closed) of 20"`), this week's xp (**out of scope — no per-week xp aggregation exists in the data model**; the design's "This week: 385 xp" figure has no backing data yet, so this stat is dropped rather than faked), and the projected regrade date (**out of scope — no pace-projection logic exists**; drop this stat too). Footer copy: "A grade never drops."

(Two of the design's four footer stats — "this week" and "regrade by" — require aggregate history/projection logic this branch doesn't have and Sub-project A never built. Rather than invent placeholder numbers that would look real but aren't, this pass shows only the one stat that's genuinely computable from existing data: tracks closed. This is a legitimate, disclosed scope cut, not an oversight.)

## 8. Profile integration

`SwiftUp/Features/Profile/ProfileHomeView.swift`:
- Drops its `@Environment(LeaderboardRepository.self)` and the `.task` call to `leaderboardRepo.load(for:)` (leaderboard is gone — see §2).
- The masthead's right-hand side, currently `mastheadRank` ("Top X% all-time" from the leaderboard), becomes the user's current grade name: `pathRepo.grade.rawValue`.
- A new row is added, mirroring the existing Level row's exact pattern (`"\(xp) to level N+1"` + `"All 12 levels →"`) — `EyebrowLabel("Grade: \(pathRepo.grade.rawValue)")` + `NavigationLink("All four grades →") { FourGradesView() }`, placed directly after that existing Level row.
- Gains `@Environment(PathRepository.self) private var pathRepo`.

## 9. Testing

- `PathRepository.isTrackReachable`: pure-logic tests against hand-built tracks (mirrors `isStageUnlocked`'s existing test style) — first track always reachable, track 2 reachable only once track 1 is closed, track 3 not reachable while track 2 is open even if track 1 is closed.
- `PathRepository.grade`: a bundled-fixture-based test is not meaningful here (grade comes from the user doc, not `pathTracks`) — this specific field is Firestore-snapshot-dependent and, like every other Firestore-snapshot-reading line in this project, isn't independently unit-tested (same accepted limitation `ProfileRepository`'s own precedent already established).
- `PathWheelDiagram`'s radial layout: a pure-math test asserting the angle/position formula for a few `N` values (e.g. `N=5` node 0 sits at the top, `N=4` nodes are 90° apart) is worth adding since it's genuinely new geometry code, not just view composition.
- No manual-verification-only screens beyond what's already an accepted limitation this session (no iOS Simulator UI-automation tool) — the usual "build + full test suite + ask the user to look at it running" applies to all three new screens.

## 10. Out of scope (explicitly deferred, restated from §5c/§7 and elsewhere)

- Spending XP, taking a stage's slides+quiz, the track assessment, the regrade quiz, and the actual grade-promotion write — all Sub-project C.
- "This week's xp," the regrade-by date projection, and the Path "days since start" figure — none of the backing aggregate/timestamp data exists; dropped rather than faked.
- Real slide/quiz content — still deferred beyond this whole three-part project, unchanged from Sub-project A's framing.
