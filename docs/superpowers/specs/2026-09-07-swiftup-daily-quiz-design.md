# SwiftUp Daily Quiz — SwiftUI Implementation Design

Source: Claude Design canvas `SwiftUp Daily Quiz.dc.html` (project `1aebc53c-4314-48ed-8f47-82d0a6372951`), 21 screens across 7 turns, "Broadsheet" design system (`_ds/broadsheet-b75e86b6-53a9-4cd1-a970-cf3642cdcee4`). Cross-reference: `requirements.md` in this repo.

## 1. Goal

Turn the static HTML mockups into a real, runnable SwiftUI app: a full Xcode project targeting iOS 17+, matching the Broadsheet editorial visual language (serif display type, ruled dividers, "eyebrow" labels, CMYK-plate numerals, no card chrome, hairline-separated lists instead of grouped boxes), driven by bundled JSON mock data.

Out of scope for this pass (per `requirements.md` §5 and general v1 scope): real backend/auth, push notifications actually firing, live Swift code execution sandbox, adaptive-difficulty engine, real leaderboard networking. All of these are represented as static/mock UI only.

## 2. Project setup

- New Xcode project, SwiftUI App lifecycle, product name **SwiftUp**, bundle id `com.swiftup.dailyquiz` (placeholder, user can rename)
- iOS deployment target: **17.0** (enables `@Observable`, `NavigationStack`)
- Swift Testing for unit tests (not XCTest)
- Git repo initialized at the project root; project scaffold + spec committed
- No third-party dependencies — everything hand-rolled to match the bespoke design system

Folder structure:

```
SwiftUp/
  App/                     SwiftUpApp.swift, RootView.swift (onboarding vs. main gate)
  DesignSystem/            Theme (colors/fonts/spacing), reusable components
  Models/                  Codable domain models
  Data/                    Bundled JSON + repository types
  Features/
    Onboarding/
    DailyQuiz/
    InterviewPrep/
    Leaderboard/
    Profile/
    Settings/
    Support/
  Resources/                JSON files, Info.plist assets
SwiftUpTests/               Swift Testing unit tests
```

## 3. Navigation architecture

- `RootView`: shows `OnboardingFlowView` (full screen) until onboarding is marked complete (persisted via `@AppStorage`), then shows `MainTabView`.
- `MainTabView`: custom-styled `TabView` with 4 tabs, each tab root in its own `NavigationStack`. The design's own footer ("Today / Prep / Ranks / Record", ruled hairline above it, active tab in accent color, non-bold serif labels) is recreated as a **custom tab bar** overlay rather than the stock iOS `TabView` chrome — matching every screen's shared footer exactly.
  1. **Today** → `DailyQuizEntryView` (1a) → quiz question flow (1b–1e pattern, one `QuizQuestionView` driven by a `QuizSession` state machine, 5 questions) → `QuizSummaryView` (1f)
  2. **Prep** → `InterviewBankView` (7a, categories) → `InterviewQuestionDetailView` (7b)
  3. **Ranks** → `LeaderboardView` (7c)
  4. **Record** → `ProfileHomeView` (3a) → `MilestonesView` (3b), `AllLevelsView` (3c), `AccuracyByTopicView` (2b, linked from 3a), `BadgesView` (2c, linked from 3a) → `SettingsView` (4a) → `NotificationSettingsView` (4b), `SupportView` (6a)
- Onboarding flow (not tabbed): `WelcomeView` (5a) → `SkillAssessmentView` (5b) → `TopicInterestsView` (5c) → sets onboarding-complete flag → `MainTabView`.

Screens 2a is **not** built standalone — its front-page content is superseded by 3a; 2b and 2c are built and linked from 3a (added "All topics →" / "All badges →" affordances consistent with the design's own pattern elsewhere, since the mockup itself doesn't show that exact link but the content has no other entry point).

## 4. Screen → View mapping

| ID | Screen | SwiftUI View |
|----|--------|--------------|
| 5a | Welcome | `WelcomeView` |
| 5b | Skill self-assessment | `SkillAssessmentView` |
| 5c | Topic interests | `TopicInterestsView` |
| 1a | Today — quiz entry | `DailyQuizEntryView` |
| 1b/1c | Q1 multiple choice (unanswered/answered) | `QuizQuestionView` (MCQ variant, answered state) |
| 1d | Q2 spot-the-bug, answered wrong | `QuizQuestionView` (code-snippet variant) |
| 1e | Q4 fill-in-the-blank | `QuizQuestionView` (fill-in variant) |
| 1f | End-of-quiz summary | `QuizSummaryView` |
| 3a | Profile — rank front page | `ProfileHomeView` |
| 3b | Milestones — the ladder | `MilestonesView` |
| 3c | All levels — the run | `AllLevelsView` |
| 2b | Accuracy by topic | `AccuracyByTopicView` |
| 2c | Badges | `BadgesView` |
| 4a | Settings | `SettingsView` |
| 4b | Notifications | `NotificationSettingsView` |
| 6a | Support / donate | `SupportView` |
| 7a | FAQ bank categories | `InterviewBankView` |
| 7b | FAQ question detail | `InterviewQuestionDetailView` |
| 7c | Leaderboard | `LeaderboardView` |

`QuizQuestionView` handles all 4 question formats (multiple choice, true/false, spot-the-bug code snippet, fill-in-the-blank) via an enum on the `Question` model, since 1b–1e are the same shell with different bodies.

## 5. Design system tokens

Translate `styles.css` `:root` tokens 1:1 into a `Theme` enum/namespace:

- **Colors**: `bg` (#f3f2f2 canvas / **#e6e4e1 note**: the canvas page bg is the design-tool chrome, the actual app screens use `--color-bg` #f3f2f2), `surface`, `text` (#201e1d), `accent` (#0088b0, cyan) + 100–900 ramp, `accent2` (#d6006c, magenta) + ramp, `neutral` 100–900 ramp, `processYellow` (#edbb00, used only in plate numerals/seals, never chrome)
- **Typography**: heading + body both "Source Serif 4" (bundle the variable font or fall back to `.serif` system design if licensing/bundling is a blocker — flag this as an implementation decision, default to system serif fallback via `Font.system(.largeTitle, design: .serif)` etc. to avoid font-licensing/bundling work in v1)
- **Spacing scale**: 5/10/15/20/30/40pt matching `--space-*`
- **Components**:
  - `EyebrowLabel` — 10px uppercase tracked caption
  - `RuledMasthead` — 3px rule / label row / 1px rule, used as the top furniture on cover-style screens (1a, 1f, 2a-analog 3a, 5a, 6a, 7c)
  - `PlateNumeral` — the `.cmyk-num` effect: a number rendered 3× in accent/accent2/processYellow with small offsets and `.blendMode(.multiply)`, plus the true value on top for accessibility
  - `RuledList` / `RuledRow` — hairline-separated rows replacing iOS grouped lists (used everywhere: settings, topic lists, level ladder, badges)
  - `SegmentedPicker` — square-cornered custom segmented control matching `.seg`/`.seg-opt` (not stock `Picker(.segmented)`)
  - `SquareToggle` — 46×26 square (not pill) switch matching the settings toggles
  - `ThinProgressBar` — flat rectangular bar (accent or accent2 fill) replacing `ProgressView`
  - `BadgeSealShape` — the SVG seal marks (circle+cross, star, diamond, quadrant) as SwiftUI `Shape`s, parameterized by kind + earned/locked state
  - `CustomTabBar` — the ruled footer nav (Today/Prep/Ranks/Record)

## 6. Data models & mock data

All `Codable`, loaded from bundled JSON via small repository types (`QuestionRepository`, `ProfileRepository`, `InterviewRepository`, `LeaderboardRepository`), exposed through `@Observable` view models per feature. No networking.

Core models: `Question` (id, topic, format enum, prompt, options/code/blank-tokens, correctAnswer, explanation, xp), `Topic` (name, accuracyPercent), `UserProfile` (name, initials, level, levelTitle, xp, xpToNextLevel, streak, freezesAvailable, answeredCount, accuracyPercent, joinDate), `Level` (number, title, xpThreshold), `Milestone` (title, kind, progress, target, xpReward, unlockedDate?), `Badge` (same as milestone essentially — unify `Milestone`/`Badge` into one `Achievement` model since 2c/3b render the same underlying data two ways), `LeaderboardEntry` (rank, name, level, xp, isCurrentUser), `InterviewCategory` (name, reviewedCount, totalCount), `InterviewQuestion` (id, category, difficulty, prompt, modelAnswer, talkingPoints, followUps, bookmarked).

`QuizSession` (`@Observable`): holds the 5 questions for "today," current index, answers given, score, elapsed time — drives 1a→1b/c/d/e→1f.

## 7. Testing

- SwiftUI `#Preview` for every view listed in §4, using the same mock repositories (previews are the primary visual-verification tool given no design-review pipeline here)
- Swift Testing unit tests for: JSON decoding of every model, `QuizSession` scoring/progression logic, level/XP threshold math (`Level` lookup, xp-to-next-level), streak/freeze accounting, leaderboard sort/rank display
- Manual verification: build + run in Simulator, click through the full flow (onboarding → today → quiz → summary → each tab → settings → support), confirm it matches the mockups closely

## 8. Open implementation decisions (flagged, not blocking)

- **Font bundling**: default to system serif (`.serif` design) rather than bundling "Source Serif 4" TTFs, to avoid license/asset overhead. Can swap in the real font later by dropping files into Resources and registering in Info.plist.
- **2a**: content fully superseded by 3a; not built as a separate view.
- **Onboarding persistence**: `@AppStorage("hasCompletedOnboarding")`, no backend.
