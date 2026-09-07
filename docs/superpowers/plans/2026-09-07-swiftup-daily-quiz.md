# SwiftUp Daily Quiz Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a runnable SwiftUI iOS app ("SwiftUp") implementing all 21 screens from the `SwiftUp Daily Quiz.dc.html` design canvas, in the canvas's "Broadsheet" editorial visual system, driven by bundled JSON mock data.

**Architecture:** XcodeGen-generated Xcode project (`SwiftUp.xcodeproj`), SwiftUI App lifecycle, iOS 17+ `@Observable` view models, four-tab `TabView` (Today/Prep/Ranks/Record) with a custom ruled tab bar, one `NavigationStack` per tab, onboarding as a one-time full-screen flow gated by `@AppStorage`. No networking — all content loads from bundled JSON via small repository types.

**Tech Stack:** Swift 5, SwiftUI, iOS 17.0 deployment target, Swift Testing (not XCTest), XcodeGen for project generation, no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-07-swiftup-daily-quiz-design.md`

## Global Constraints

- iOS deployment target: 17.0 minimum (project-wide)
- Product name `SwiftUp`, bundle id `com.swiftup.dailyquiz`
- SwiftUI only — no UIKit view controllers, no third-party packages
- Tests use the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`), not XCTest
- All app content (questions, profile, achievements, levels, topics, leaderboard, interview bank) comes from bundled JSON in `SwiftUp/Resources/*.json` — no network calls anywhere
- Colors/fonts/spacing always go through `Theme` (never hardcode a hex color or raw font size inside a feature view when a Theme token exists for it)
- Every screen-level `View` ships with a `#Preview`
- Git commit after every task

---

## Task 1: Project scaffold

**Files:**
- Create: `project.yml`
- Create: `SwiftUp/App/SwiftUpApp.swift`
- Create: `SwiftUp/App/ContentView.swift`
- Create: `SwiftUpTests/SwiftUpTests.swift`

**Interfaces:**
- Produces: `SwiftUp.xcodeproj` (generated, not hand-edited after this task — later tasks add files to `project.yml`'s `sources` paths, which XcodeGen picks up automatically on regeneration since paths are directory-based)

- [ ] **Step 1: Install XcodeGen if missing**

Run: `which xcodegen || brew install xcodegen`

- [ ] **Step 2: Write the XcodeGen project spec**

`project.yml`:
```yaml
name: SwiftUp
options:
  bundleIdPrefix: com.swiftup
  deploymentTarget:
    iOS: "17.0"
targets:
  SwiftUp:
    type: application
    platform: iOS
    sources:
      - path: SwiftUp
    info:
      path: Generated/SwiftUp-Info.plist
      properties:
        UILaunchScreen: {}
        CFBundleDisplayName: SwiftUp
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.swiftup.dailyquiz
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1"
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: ""
  SwiftUpTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: SwiftUpTests
    dependencies:
      - target: SwiftUp
    settings:
      base:
        SWIFT_VERSION: "5.0"
schemes:
  SwiftUp:
    build:
      targets:
        SwiftUp: all
        SwiftUpTests: [test]
    test:
      targets:
        - SwiftUpTests
    run:
      config: Debug
```

- [ ] **Step 3: Create the app entry point**

`SwiftUp/App/SwiftUpApp.swift`:
```swift
import SwiftUI

@main
struct SwiftUpApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 4: Create a placeholder root view**

`SwiftUp/App/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("SwiftUp")
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 5: Create a placeholder test**

`SwiftUpTests/SwiftUpTests.swift`:
```swift
import Testing

struct SwiftUpTests {
    @Test func scaffoldBuilds() {
        #expect(1 + 1 == 2)
    }
}
```

- [ ] **Step 6: Generate the Xcode project**

Run: `xcodegen generate`
Expected: `SwiftUp.xcodeproj` created, no errors.

- [ ] **Step 7: Build for Simulator**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Run the placeholder test**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **` (adjust simulator name to one available via `xcrun simctl list devices available` if `iPhone 16` isn't present)

- [ ] **Step 9: Add .gitignore entries for generated project artifacts and commit**

Append to `.gitignore`:
```
*.xcodeproj/
Generated/
```

```bash
git add project.yml .gitignore SwiftUp/App SwiftUpTests
git commit -m "Scaffold SwiftUp Xcode project via XcodeGen

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 2: Theme tokens

**Files:**
- Create: `SwiftUp/DesignSystem/Theme.swift`
- Test: `SwiftUpTests/ThemeTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `Theme.Colors.*` (Color constants), `Theme.Spacing.*` (CGFloat constants), `Theme.Font.heading(size:weight:)`, `Theme.Font.body(size:weight:)`, `Color(hex:)` initializer — every later View task uses these.

- [ ] **Step 1: Write the failing test**

`SwiftUpTests/ThemeTests.swift`:
```swift
import Testing
import SwiftUI
@testable import SwiftUp

struct ThemeTests {
    @Test func hexInitializerMatchesKnownColor() {
        let color = Color(hex: 0x0088B0)
        let resolved = color.resolve(in: EnvironmentValues())
        #expect(abs(resolved.red - 0/255) < 0.01)
        #expect(abs(resolved.green - 136.0/255) < 0.01)
        #expect(abs(resolved.blue - 176.0/255) < 0.01)
    }

    @Test func spacingScaleIsPositive() {
        #expect(Theme.Spacing.s1 < Theme.Spacing.s2)
        #expect(Theme.Spacing.s8 == 40)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: FAIL — `Theme` / `Color(hex:)` not defined.

- [ ] **Step 3: Implement Theme**

`SwiftUp/DesignSystem/Theme.swift`:
```swift
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum Theme {
    enum Colors {
        static let bg = Color(hex: 0xF3F2F2)
        static let surface = Color(hex: 0xEAE9E9)
        static let text = Color(hex: 0x201E1D)
        static let divider = Color(hex: 0x201E1D, opacity: 0.16)

        static let accent = Color(hex: 0x0088B0)
        static let accent100 = Color(hex: 0xE9F8FF)
        static let accent700 = Color(hex: 0x006786)
        static let accent800 = Color(hex: 0x004961)

        static let accent2 = Color(hex: 0xD6006C)
        static let accent2100 = Color(hex: 0xFFF1F4)
        static let accent2800 = Color(hex: 0x790E3D)

        static let neutral200 = Color(hex: 0xEAE7E7)
        static let neutral300 = Color(hex: 0xD7D3D3)
        static let neutral400 = Color(hex: 0xBAB6B6)
        static let neutral600 = Color(hex: 0x7D7979)
        static let neutral700 = Color(hex: 0x605D5D)
        static let neutral800 = Color(hex: 0x444141)

        static let processYellow = Color(hex: 0xEDBB00)
    }

    enum Spacing {
        static let s1: CGFloat = 5
        static let s2: CGFloat = 10
        static let s3: CGFloat = 15
        static let s4: CGFloat = 20
        static let s6: CGFloat = 30
        static let s8: CGFloat = 40
    }

    enum Fonts {
        static func heading(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/DesignSystem/Theme.swift SwiftUpTests/ThemeTests.swift
git commit -m "Add Theme design tokens (colors, spacing, fonts)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 3: Core layout atoms — EyebrowLabel, RuledMasthead, RuledRow, ThinProgressBar

**Files:**
- Create: `SwiftUp/DesignSystem/Atoms.swift`

**Interfaces:**
- Consumes: `Theme.Colors.*`, `Theme.Fonts.*`
- Produces:
  - `EyebrowLabel(_ text: String, color: Color = Theme.Colors.neutral700)`
  - `RuledMasthead(left: String, right: String)`
  - `RuledRow<Content: View>(showTopRule: Bool = true, showBottomRule: Bool = false, minHeight: CGFloat = 46, @ViewBuilder content: () -> Content)`
  - `ThinProgressBar(fraction: Double, trackColor: Color = Theme.Colors.neutral200, fillColor: Color = Theme.Colors.accent, height: CGFloat = 7)`

- [ ] **Step 1: Implement the atoms**

`SwiftUp/DesignSystem/Atoms.swift`:
```swift
import SwiftUI

struct EyebrowLabel: View {
    let text: String
    var color: Color = Theme.Colors.neutral700

    init(_ text: String, color: Color = Theme.Colors.neutral700) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .regular))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

struct RuledMasthead: View {
    let left: String
    let right: String

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Colors.text).frame(height: 3)
            HStack {
                EyebrowLabel(left)
                Spacer()
                EyebrowLabel(right)
            }
            .padding(.vertical, 7)
            Rectangle().fill(Theme.Colors.text).frame(height: 1)
        }
    }
}

struct RuledRow<Content: View>: View {
    var showTopRule: Bool = true
    var showBottomRule: Bool = false
    var minHeight: CGFloat = 46
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if showTopRule {
                Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            }
            HStack(spacing: 12) { content() }
                .frame(minHeight: minHeight)
            if showBottomRule {
                Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            }
        }
    }
}

struct ThinProgressBar: View {
    let fraction: Double
    var trackColor: Color = Theme.Colors.neutral200
    var fillColor: Color = Theme.Colors.accent
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(trackColor)
                Rectangle()
                    .fill(fillColor)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: height)
    }
}

#Preview("Atoms") {
    VStack(alignment: .leading, spacing: 20) {
        RuledMasthead(left: "SwiftUp", right: "No. 1")
        RuledRow { Text("Reminder"); Spacer(); Text("07:30") }
        ThinProgressBar(fraction: 0.7)
    }
    .padding()
    .background(Theme.Colors.bg)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/DesignSystem/Atoms.swift
git commit -m "Add core layout atoms (EyebrowLabel, RuledMasthead, RuledRow, ThinProgressBar)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 4: Interactive atoms — SegmentedPicker, SquareToggle, PlateNumeral

**Files:**
- Create: `SwiftUp/DesignSystem/InteractiveAtoms.swift`

**Interfaces:**
- Consumes: `Theme.*`
- Produces:
  - `SegmentedPicker(options: [String], selection: Binding<String>)`
  - `SquareToggle(isOn: Binding<Bool>)`
  - `PlateNumeral(_ value: String, font: Font)`

- [ ] **Step 1: Implement**

`SwiftUp/DesignSystem/InteractiveAtoms.swift`:
```swift
import SwiftUI

struct SegmentedPicker: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(.system(size: 13))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(selection == option ? Theme.Colors.accent : Color.clear)
                    .foregroundStyle(selection == option ? Theme.Colors.bg : Theme.Colors.text)
                    .overlay(alignment: .leading) {
                        if option != options.first {
                            Rectangle().fill(Theme.Colors.divider).frame(width: 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SquareToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(isOn ? Theme.Colors.accent : Theme.Colors.neutral300)
            .frame(width: 46, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.Colors.bg)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
            .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

/// Recreates the canvas's `.cmyk-num` misregistered-plate numeral: three
/// color copies offset a few points apart, multiply-blended so their
/// overlap reads as dark ink with colored fringes at the edges.
struct PlateNumeral: View {
    let value: String
    var font: Font

    init(_ value: String, font: Font) {
        self.value = value
        self.font = font
    }

    var body: some View {
        ZStack {
            Text(value).font(font).foregroundStyle(Theme.Colors.accent)
                .blendMode(.multiply).offset(x: -1.2, y: 0.4)
            Text(value).font(font).foregroundStyle(Theme.Colors.accent2)
                .blendMode(.multiply).offset(x: 1.2, y: 0.8)
            Text(value).font(font).foregroundStyle(Theme.Colors.processYellow)
                .blendMode(.multiply).offset(x: -0.8, y: -0.7)
        }
        .accessibilityLabel(Text(value))
    }
}

#Preview("Interactive atoms") {
    VStack(spacing: 24) {
        SegmentedPicker(options: ["All", "Junior", "Mid", "Senior"], selection: .constant("Mid"))
        SquareToggle(isOn: .constant(true))
        PlateNumeral("42", font: Theme.Fonts.heading(76, weight: .semibold))
    }
    .padding()
    .background(Theme.Colors.bg)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/DesignSystem/InteractiveAtoms.swift
git commit -m "Add interactive atoms (SegmentedPicker, SquareToggle, PlateNumeral)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 5: Achievement seals

**Files:**
- Create: `SwiftUp/DesignSystem/AchievementSeal.swift`
- Test: `SwiftUpTests/StarShapeTests.swift`

**Interfaces:**
- Consumes: `Theme.*`
- Produces: `enum AchievementSealKind: String, Codable { case perfectWeek, streakMilestone, topicMastery, firstSession }`, `AchievementSeal(kind: AchievementSealKind, filled: Bool, size: CGFloat = 46)`, `LockedSeal(remainingCount: Int, size: CGFloat = 46)` — consumed by Task 7's `Achievement` model and Task 15's Profile/Milestones views.

- [ ] **Step 1: Write the failing test for the star geometry**

`SwiftUpTests/StarShapeTests.swift`:
```swift
import Testing
import SwiftUI
@testable import SwiftUp

struct StarShapeTests {
    @Test func starPathStaysWithinBounds() {
        let shape = StarShape()
        let rect = CGRect(x: 0, y: 0, width: 46, height: 46)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect
        #expect(bounds.width <= rect.width + 0.5)
        #expect(bounds.height <= rect.height + 0.5)
        #expect(!path.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: FAIL — `StarShape` not defined.

- [ ] **Step 3: Implement seals**

`SwiftUp/DesignSystem/AchievementSeal.swift`:
```swift
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
        .accessibilityHidden(false)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/DesignSystem/AchievementSeal.swift SwiftUpTests/StarShapeTests.swift
git commit -m "Add achievement seal shapes (perfect week, streak, mastery, first session)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 6: AppTab enum and CustomTabBar

**Files:**
- Create: `SwiftUp/DesignSystem/CustomTabBar.swift`

**Interfaces:**
- Consumes: `Theme.*`
- Produces: `enum AppTab: String, CaseIterable { case today = "Today", prep = "Prep", ranks = "Ranks", record = "Record" }`, `CustomTabBar(selection: Binding<AppTab>)` — consumed by Task 21 (`MainTabView`).

- [ ] **Step 1: Implement**

`SwiftUp/DesignSystem/CustomTabBar.swift`:
```swift
import SwiftUI

enum AppTab: String, CaseIterable {
    case today = "Today"
    case prep = "Prep"
    case ranks = "Ranks"
    case record = "Record"
}

/// Recreates the canvas's shared footer — a hairline rule above four
/// ruled-serif labels — instead of the stock iOS tab bar chrome.
struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.Colors.divider).frame(height: 1)
            HStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue)
                        .font(.system(size: 12.5, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? Theme.Colors.accent700 : Theme.Colors.neutral700)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = tab }
                }
            }
            .padding(.top, 13)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    VStack {
        Spacer()
        CustomTabBar(selection: .constant(.record))
    }
    .background(Theme.Colors.surface)
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/DesignSystem/CustomTabBar.swift
git commit -m "Add AppTab enum and custom ruled tab bar

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 7: Domain models

**Files:**
- Create: `SwiftUp/Models/Question.swift`
- Create: `SwiftUp/Models/UserProfile.swift`
- Create: `SwiftUp/Models/LevelInfo.swift`
- Create: `SwiftUp/Models/Achievement.swift`
- Create: `SwiftUp/Models/TopicAccuracy.swift`
- Create: `SwiftUp/Models/LeaderboardEntry.swift`
- Create: `SwiftUp/Models/InterviewCategory.swift`
- Create: `SwiftUp/Models/InterviewQuestion.swift`
- Test: `SwiftUpTests/ModelDecodingTests.swift`

**Interfaces:**
- Consumes: `AchievementSealKind` (Task 5)
- Produces: every model type below — consumed by Task 9 (repositories) and every feature view task.

- [ ] **Step 1: Write the failing decoding tests**

`SwiftUpTests/ModelDecodingTests.swift`:
```swift
import Testing
import Foundation
@testable import SwiftUp

struct ModelDecodingTests {
    @Test func decodesMultipleChoiceQuestion() throws {
        let json = """
        {
          "id": "q1", "topic": "Concurrency", "format": "multipleChoice",
          "prompt": "What does it not inherit?", "codeSnippet": null,
          "options": [{"id": "A", "text": "Actor context"}, {"id": "B", "text": "Cancellation"}],
          "correctOptionID": "A", "explanation": "Because.", "xp": 15
        }
        """.data(using: .utf8)!
        let q = try JSONDecoder().decode(Question.self, from: json)
        #expect(q.format == .multipleChoice)
        #expect(q.options.count == 2)
        #expect(q.correctOptionID == "A")
    }

    @Test func decodesAchievementWithSealKind() throws {
        let json = """
        {
          "id": "a1", "title": "Perfect week", "detail": "Six of seven days",
          "sealKind": "perfectWeek", "status": "earned", "xpReward": 200,
          "earnedDateDisplay": "7 Sep", "progressCurrent": null, "progressTarget": null
        }
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(Achievement.self, from: json)
        #expect(a.sealKind == .perfectWeek)
        #expect(a.status == .earned)
    }

    @Test func decodesUserProfile() throws {
        let json = """
        {
          "name": "Maya Reyes", "initials": "MR", "level": 7,
          "levelTitle": "Concurrency Compositor", "xp": 3240,
          "xpForCurrentLevel": 2200, "xpForNextLevel": 3700,
          "streakDays": 42, "freezesAvailable": 1, "freezesTotal": 3,
          "answeredCount": 585, "accuracyPercent": 81,
          "memberSinceDisplay": "Since 14 May"
        }
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(p.xpToNextLevel == 460)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: FAIL — models not defined.

- [ ] **Step 3: Implement `Question`**

`SwiftUp/Models/Question.swift`:
```swift
import Foundation

enum QuestionFormat: String, Codable {
    case multipleChoice, trueFalse, spotTheBug, fillInTheBlank
}

struct QuestionOption: Codable, Identifiable, Hashable {
    let id: String
    let text: String
}

struct Question: Codable, Identifiable {
    let id: String
    let topic: String
    let format: QuestionFormat
    let prompt: String
    let codeSnippet: String?
    let options: [QuestionOption]
    let correctOptionID: String
    let explanation: String
    let xp: Int
}
```

- [ ] **Step 4: Implement `UserProfile`**

`SwiftUp/Models/UserProfile.swift`:
```swift
import Foundation

struct UserProfile: Codable {
    let name: String
    let initials: String
    let level: Int
    let levelTitle: String
    let xp: Int
    let xpForCurrentLevel: Int
    let xpForNextLevel: Int
    let streakDays: Int
    let freezesAvailable: Int
    let freezesTotal: Int
    let answeredCount: Int
    let accuracyPercent: Int
    let memberSinceDisplay: String

    var xpToNextLevel: Int { max(0, xpForNextLevel - xp) }

    var levelProgressFraction: Double {
        let span = Double(xpForNextLevel - xpForCurrentLevel)
        guard span > 0 else { return 0 }
        return max(0, min(1, Double(xp - xpForCurrentLevel) / span))
    }
}
```

- [ ] **Step 5: Implement `LevelInfo`**

`SwiftUp/Models/LevelInfo.swift`:
```swift
import Foundation

struct LevelInfo: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let title: String
    let xpThreshold: Int
}
```

- [ ] **Step 6: Implement `Achievement`**

`SwiftUp/Models/Achievement.swift`:
```swift
import Foundation

enum AchievementStatus: String, Codable {
    case earned, inReach, locked
}

struct Achievement: Codable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let sealKind: AchievementSealKind
    let status: AchievementStatus
    let xpReward: Int
    let earnedDateDisplay: String?
    let progressCurrent: Int?
    let progressTarget: Int?

    var progressFraction: Double? {
        guard let current = progressCurrent, let target = progressTarget, target > 0 else { return nil }
        return max(0, min(1, Double(current) / Double(target)))
    }
}
```

- [ ] **Step 7: Implement `TopicAccuracy`**

`SwiftUp/Models/TopicAccuracy.swift`:
```swift
import Foundation

struct TopicAccuracy: Codable, Identifiable {
    var id: String { name }
    let name: String
    let accuracyPercent: Int
}
```

- [ ] **Step 8: Implement `LeaderboardEntry`**

`SwiftUp/Models/LeaderboardEntry.swift`:
```swift
import Foundation

struct LeaderboardEntry: Codable, Identifiable {
    var id: String { name }
    let rank: Int
    let name: String
    let level: Int
    let xp: Int
    let isCurrentUser: Bool
}
```

- [ ] **Step 9: Implement `InterviewCategory`**

`SwiftUp/Models/InterviewCategory.swift`:
```swift
import Foundation

struct InterviewCategory: Codable, Identifiable {
    var id: String { name }
    let name: String
    let reviewedCount: Int
    let totalCount: Int
}
```

- [ ] **Step 10: Implement `InterviewQuestion`**

`SwiftUp/Models/InterviewQuestion.swift`:
```swift
import Foundation

struct InterviewQuestion: Codable, Identifiable {
    let id: String
    let category: String
    let difficulty: String
    let indexInCategory: Int
    let totalInCategory: Int
    let prompt: String
    let modelAnswer: String
    let talkingPoints: [String]
    let followUps: [String]
    let bookmarked: Bool
}
```

- [ ] **Step 11: Run tests to verify they pass**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add SwiftUp/Models SwiftUpTests/ModelDecodingTests.swift
git commit -m "Add Codable domain models for questions, profile, achievements, leaderboard, interview bank

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 8: Bundled mock JSON data

**Files:**
- Create: `SwiftUp/Resources/questions.json`
- Create: `SwiftUp/Resources/profile.json`
- Create: `SwiftUp/Resources/levels.json`
- Create: `SwiftUp/Resources/achievements.json`
- Create: `SwiftUp/Resources/topics.json`
- Create: `SwiftUp/Resources/leaderboard.json`
- Create: `SwiftUp/Resources/interview_categories.json`
- Create: `SwiftUp/Resources/interview_questions.json`

**Interfaces:**
- Consumes: nothing (raw data, shaped to match Task 7's models field-for-field)
- Produces: bundled resources consumed by Task 9's repositories

- [ ] **Step 1: `questions.json`** (5 daily questions; content drawn from canvas screens 1b/1c/1d/1e, with Q3 and Q5 added to complete the daily five)

```json
[
  {
    "id": "q1", "topic": "Concurrency", "format": "multipleChoice",
    "prompt": "A Task.detached block runs a piece of work. What does it not inherit?",
    "codeSnippet": null,
    "options": [
      {"id": "A", "text": "The actor context, priority and task-local values of the caller"},
      {"id": "B", "text": "Only the cancellation state of the parent task"},
      {"id": "C", "text": "Nothing — a detached task inherits everything but runs concurrently"},
      {"id": "D", "text": "Only the executor, but priority still propagates"}
    ],
    "correctOptionID": "A",
    "explanation": "A detached task starts with a clean slate — no actor isolation, no inherited priority, no task-local values. Task { } inherits all three.",
    "xp": 15
  },
  {
    "id": "q2", "topic": "Memory · ARC", "format": "spotTheBug",
    "prompt": "Spot the bug. Which line leaks?",
    "codeSnippet": "// ImageLoader.swift\nfinal class Loader {\n    var onDone: (() -> Void)?\n    func load() {\n        client.fetch { data in\n            self.cache = data\n            self.onDone?()\n        }\n    }\n}",
    "options": [
      {"id": "A", "text": "Line 3 — the closure property should be weak"},
      {"id": "B", "text": "Line 7 — calling onDone retains the caller"},
      {"id": "C", "text": "Line 5 — the escaping closure captures self strongly"}
    ],
    "correctOptionID": "C",
    "explanation": "The retain cycle forms where the escaping closure is created. [weak self] on line 5 breaks it; the property on line 3 is not the cycle.",
    "xp": 15
  },
  {
    "id": "q3", "topic": "SwiftUI state", "format": "trueFalse",
    "prompt": "True or false: @State should only ever be used for value types privately owned by the view that declares it.",
    "codeSnippet": null,
    "options": [
      {"id": "true", "text": "True"},
      {"id": "false", "text": "False"}
    ],
    "correctOptionID": "true",
    "explanation": "@State is for a view's own private, transient value-type storage. Anything shared or reference-typed belongs in @Observable model state instead.",
    "xp": 15
  },
  {
    "id": "q4", "topic": "SwiftUI state", "format": "fillInTheBlank",
    "prompt": "Complete the line. The child must write back to the parent's value.",
    "codeSnippet": "struct RowView: View {\n    ___ var isOn: Bool\n\n    var body: some View {\n        Toggle(\"Mute\", isOn: $isOn)\n    }\n}",
    "options": [
      {"id": "state", "text": "@State"},
      {"id": "binding", "text": "@Binding"},
      {"id": "bindable", "text": "@Bindable"},
      {"id": "observable", "text": "@Observable"},
      {"id": "environment", "text": "@Environment"}
    ],
    "correctOptionID": "binding",
    "explanation": "@Binding gives the child read/write access to a value the parent owns — the blank needs $isOn to type-check, and only a binding can be prefixed with $ here.",
    "xp": 15
  },
  {
    "id": "q5", "topic": "Concurrency", "format": "multipleChoice",
    "prompt": "You mark a class @MainActor. What is guaranteed about its methods?",
    "codeSnippet": null,
    "options": [
      {"id": "A", "text": "They always run synchronously"},
      {"id": "B", "text": "They run on the main thread, isolated from other actors"},
      {"id": "C", "text": "They cannot be called from async code"},
      {"id": "D", "text": "They run on a background queue for performance"}
    ],
    "correctOptionID": "B",
    "explanation": "@MainActor isolates the type's methods and mutable state to the main actor, so they run on the main thread and can safely touch UI state.",
    "xp": 15
  }
]
```

- [ ] **Step 2: `profile.json`**

```json
{
  "name": "Maya Reyes",
  "initials": "MR",
  "level": 7,
  "levelTitle": "Concurrency Compositor",
  "xp": 3240,
  "xpForCurrentLevel": 2200,
  "xpForNextLevel": 3700,
  "streakDays": 42,
  "freezesAvailable": 1,
  "freezesTotal": 3,
  "answeredCount": 585,
  "accuracyPercent": 81,
  "memberSinceDisplay": "Since 14 May"
}
```

- [ ] **Step 3: `levels.json`** (from canvas screen 3c; level 7's own threshold isn't shown in the mockup since it's the current row — 2700 is an interpolated placeholder never displayed, since the "current level" row shows "You are here" instead of an xp figure)

```json
[
  {"number": 1, "title": "Swift Novice", "xpThreshold": 0},
  {"number": 2, "title": "Optional Handler", "xpThreshold": 150},
  {"number": 3, "title": "Protocol Wrangler", "xpThreshold": 400},
  {"number": 4, "title": "View Builder", "xpThreshold": 800},
  {"number": 5, "title": "State Keeper", "xpThreshold": 1400},
  {"number": 6, "title": "Retain Cycle Sleuth", "xpThreshold": 2200},
  {"number": 7, "title": "Concurrency Compositor", "xpThreshold": 2700},
  {"number": 8, "title": "SwiftUI Architect", "xpThreshold": 3700},
  {"number": 9, "title": "Performance Surgeon", "xpThreshold": 5000},
  {"number": 10, "title": "Systems Designer", "xpThreshold": 7000},
  {"number": 11, "title": "Principal Reviewer", "xpThreshold": 9500},
  {"number": 12, "title": "Platform Editor", "xpThreshold": 13000}
]
```

- [ ] **Step 4: `achievements.json`** (24 total — 9 earned matching 2c/3a's "9/24", 2 in-reach matching 3a/3b/2c's "next up" #10/#11, 13 locked filler to reach 24)

```json
[
  {"id": "a01", "title": "Perfect week", "detail": "Six of seven days at 4/5 or better", "sealKind": "perfectWeek", "status": "earned", "xpReward": 200, "earnedDateDisplay": "7 Sep", "progressCurrent": null, "progressTarget": null},
  {"id": "a02", "title": "Thirty in a row", "detail": "A 30-day streak, no freezes spent", "sealKind": "streakMilestone", "status": "earned", "xpReward": 150, "earnedDateDisplay": "26 Aug", "progressCurrent": null, "progressTarget": null},
  {"id": "a03", "title": "Concurrency, mastered", "detail": "90% across 40 questions in one topic", "sealKind": "topicMastery", "status": "earned", "xpReward": 250, "earnedDateDisplay": "19 Aug", "progressCurrent": null, "progressTarget": null},
  {"id": "a04", "title": "First interview session", "detail": "Completed a timed prep session end to end", "sealKind": "firstSession", "status": "earned", "xpReward": 100, "earnedDateDisplay": "2 Aug", "progressCurrent": null, "progressTarget": null},
  {"id": "a05", "title": "Seven in a row", "detail": "Your first full week's streak", "sealKind": "streakMilestone", "status": "earned", "xpReward": 50, "earnedDateDisplay": "21 Jul", "progressCurrent": null, "progressTarget": null},
  {"id": "a06", "title": "Fast learner", "detail": "Ten perfect 5/5 days", "sealKind": "perfectWeek", "status": "earned", "xpReward": 100, "earnedDateDisplay": "14 Jul", "progressCurrent": null, "progressTarget": null},
  {"id": "a07", "title": "Swift language, mastered", "detail": "90% across 30 questions in one topic", "sealKind": "topicMastery", "status": "earned", "xpReward": 200, "earnedDateDisplay": "3 Jul", "progressCurrent": null, "progressTarget": null},
  {"id": "a08", "title": "Century club", "detail": "100 questions answered", "sealKind": "firstSession", "status": "earned", "xpReward": 75, "earnedDateDisplay": "20 Jun", "progressCurrent": null, "progressTarget": null},
  {"id": "a09", "title": "Onboarded", "detail": "Finished onboarding and day one", "sealKind": "firstSession", "status": "earned", "xpReward": 25, "earnedDateDisplay": "14 May", "progressCurrent": null, "progressTarget": null},
  {"id": "a10", "title": "Fifty in a row", "detail": "42 of 50 days · 250 xp on unlock", "sealKind": "streakMilestone", "status": "inReach", "xpReward": 250, "earnedDateDisplay": null, "progressCurrent": 42, "progressTarget": 50},
  {"id": "a11", "title": "Cycle breaker", "detail": "Memory · ARC at 41% — reach 80% · 300 xp", "sealKind": "topicMastery", "status": "inReach", "xpReward": 300, "earnedDateDisplay": null, "progressCurrent": 41, "progressTarget": 80},
  {"id": "a12", "title": "Hundred in a row", "detail": "A 100-day streak", "sealKind": "streakMilestone", "status": "locked", "xpReward": 400, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a13", "title": "Architecture, mastered", "detail": "90% across 40 questions in one topic", "sealKind": "topicMastery", "status": "locked", "xpReward": 250, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a14", "title": "Networking, mastered", "detail": "90% across 30 questions in one topic", "sealKind": "topicMastery", "status": "locked", "xpReward": 200, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a15", "title": "Perfect month", "detail": "Every day this month at 4/5 or better", "sealKind": "perfectWeek", "status": "locked", "xpReward": 500, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a16", "title": "Interview ready", "detail": "Reviewed every category in the FAQ bank once", "sealKind": "firstSession", "status": "locked", "xpReward": 300, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a17", "title": "Five hundred club", "detail": "500 questions answered", "sealKind": "firstSession", "status": "locked", "xpReward": 150, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a18", "title": "Thousand club", "detail": "1,000 questions answered", "sealKind": "firstSession", "status": "locked", "xpReward": 300, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a19", "title": "SwiftUI, mastered", "detail": "90% across 40 questions in one topic", "sealKind": "topicMastery", "status": "locked", "xpReward": 250, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a20", "title": "Testing, mastered", "detail": "90% across 25 questions in one topic", "sealKind": "topicMastery", "status": "locked", "xpReward": 200, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a21", "title": "Two hundred in a row", "detail": "A 200-day streak", "sealKind": "streakMilestone", "status": "locked", "xpReward": 600, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a22", "title": "Second session", "detail": "Completed two timed prep sessions", "sealKind": "firstSession", "status": "locked", "xpReward": 100, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a23", "title": "Level ten", "detail": "Reach Systems Designer", "sealKind": "perfectWeek", "status": "locked", "xpReward": 400, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null},
  {"id": "a24", "title": "Top of the board", "detail": "Finish first on the weekly leaderboard", "sealKind": "streakMilestone", "status": "locked", "xpReward": 350, "earnedDateDisplay": null, "progressCurrent": null, "progressTarget": null}
]
```

- [ ] **Step 5: `topics.json`** (12 topics matching canvas 2b, ranked worst-first; two extra topics beyond the mockup's 10 rows added — Combine and Xcode/tooling — so the count matches 2b's own "Twelve topics" copy)

```json
[
  {"name": "Memory · ARC", "accuracyPercent": 41},
  {"name": "Core Data / SwiftData", "accuracyPercent": 54},
  {"name": "Testing", "accuracyPercent": 62},
  {"name": "Networking", "accuracyPercent": 70},
  {"name": "Architecture", "accuracyPercent": 74},
  {"name": "SwiftUI state", "accuracyPercent": 78},
  {"name": "UIKit", "accuracyPercent": 83},
  {"name": "App lifecycle", "accuracyPercent": 86},
  {"name": "Swift language", "accuracyPercent": 89},
  {"name": "Concurrency", "accuracyPercent": 92},
  {"name": "Combine", "accuracyPercent": 90},
  {"name": "Xcode / tooling", "accuracyPercent": 95}
]
```

- [ ] **Step 6: `leaderboard.json`**

```json
[
  {"rank": 1, "name": "Dana Okafor", "level": 9, "xp": 640, "isCurrentUser": false},
  {"rank": 2, "name": "Tomas Lind", "level": 8, "xp": 505, "isCurrentUser": false},
  {"rank": 3, "name": "You", "level": 7, "xp": 385, "isCurrentUser": true},
  {"rank": 4, "name": "Priya Raman", "level": 7, "xp": 370, "isCurrentUser": false},
  {"rank": 5, "name": "Sam Whitfield", "level": 6, "xp": 310, "isCurrentUser": false},
  {"rank": 6, "name": "Jo Mensah", "level": 6, "xp": 240, "isCurrentUser": false},
  {"rank": 7, "name": "Elif Kaya", "level": 5, "xp": 180, "isCurrentUser": false},
  {"rank": 8, "name": "Ana Sorescu", "level": 5, "xp": 95, "isCurrentUser": false}
]
```

- [ ] **Step 7: `interview_categories.json`**

```json
[
  {"name": "Swift fundamentals", "reviewedCount": 31, "totalCount": 36},
  {"name": "Architecture patterns", "reviewedCount": 12, "totalCount": 40},
  {"name": "System design for iOS", "reviewedCount": 4, "totalCount": 22},
  {"name": "Performance & debugging", "reviewedCount": 9, "totalCount": 28},
  {"name": "Behavioural", "reviewedCount": 0, "totalCount": 24}
]
```

- [ ] **Step 8: `interview_questions.json`** (the fully detailed MVVM question from canvas 7b, plus lightweight stubs so every category has at least one question)

```json
[
  {
    "id": "iq01", "category": "Architecture patterns", "difficulty": "Mid",
    "indexInCategory": 13, "totalInCategory": 40,
    "prompt": "How would you explain MVVM to a team that has only written view controllers?",
    "modelAnswer": "Start from the pain: a view controller that owns formatting, networking and navigation cannot be tested or reused. MVVM moves that state into a view model the view observes, so the view describes state and the view model is testable without a screen.",
    "talkingPoints": [
      "The view model owns no UIKit or SwiftUI types — that is what makes it testable.",
      "Bindings are the contract; in SwiftUI that is @Observable, not a framework.",
      "Name the cost honestly: more files, and indirection a small screen may not need."
    ],
    "followUps": ["Where does navigation live?", "How do you test a view model that calls the network?"],
    "bookmarked": true
  },
  {
    "id": "iq02", "category": "Swift fundamentals", "difficulty": "Junior",
    "indexInCategory": 1, "totalInCategory": 36,
    "prompt": "What is the difference between a struct and a class in Swift?",
    "modelAnswer": "Structs are value types — copied on assignment, no shared mutable state by default. Classes are reference types — assignment shares the same instance, which is what you want for identity-based models but a common source of surprise bugs when you didn't mean to share.",
    "talkingPoints": [
      "Value semantics make structs safer under concurrency by default.",
      "Classes support inheritance; structs support protocol conformance and composition instead.",
      "SwiftUI views are structs on purpose — cheap to recreate, no shared state to corrupt."
    ],
    "followUps": ["When would you reach for a class anyway?"],
    "bookmarked": false
  },
  {
    "id": "iq03", "category": "System design for iOS", "difficulty": "Senior",
    "indexInCategory": 1, "totalInCategory": 22,
    "prompt": "Design the caching layer for an image-heavy feed. What are the failure modes?",
    "modelAnswer": "A two-tier cache: an in-memory LRU for what's on screen, a disk cache keyed by URL hash for what scrolled past. The failure modes are memory pressure evicting the wrong tier under load, and disk cache growing unbounded without a size cap and eviction policy.",
    "talkingPoints": [
      "Memory cache should respond to memory warnings, not just a fixed size cap.",
      "Disk cache needs a background eviction pass, not eviction-on-write.",
      "Cache keys must account for image size variants, or you serve the wrong resolution."
    ],
    "followUps": ["How do you avoid duplicate in-flight requests for the same image?"],
    "bookmarked": false
  },
  {
    "id": "iq04", "category": "Performance & debugging", "difficulty": "Mid",
    "indexInCategory": 1, "totalInCategory": 28,
    "prompt": "A list scrolls at 30fps instead of 60. Walk through how you'd find out why.",
    "modelAnswer": "Profile first, guess never: Instruments' Time Profiler and Core Animation tool to see whether the bottleneck is CPU (view body work per row) or GPU (offscreen rendering, blending). Only after that do you know whether the fix is caching row content or removing a shadow/blur.",
    "talkingPoints": [
      "Cheap-looking modifiers like .shadow and rounded corners with clipping can force offscreen rendering.",
      "Recomputing expensive view state in body on every scroll frame is a common self-inflicted cause.",
      "Measure again after the fix — an unverified fix isn't a fix."
    ],
    "followUps": ["What's the difference between a CPU-bound and GPU-bound frame drop?"],
    "bookmarked": false
  },
  {
    "id": "iq05", "category": "Behavioural", "difficulty": "Junior",
    "indexInCategory": 1, "totalInCategory": 24,
    "prompt": "Tell me about a time you disagreed with a code review comment.",
    "modelAnswer": "Pick a real example with a concrete technical disagreement, state both positions plainly, and land on what actually happened — whether you were persuaded, you persuaded them, or you both learned the constraint was different than either assumed.",
    "talkingPoints": [
      "Specificity beats a polished-sounding generic answer.",
      "Showing you changed your mind at least once reads better than always being right.",
      "Keep it short — this is a door-opener for follow-up questions, not the whole interview."
    ],
    "followUps": ["How did you make sure the disagreement didn't become personal?"],
    "bookmarked": false
  }
]
```

- [ ] **Step 9: Regenerate the project so XcodeGen picks up the new resource files, build, and commit**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

```bash
git add SwiftUp/Resources
git commit -m "Add bundled mock JSON data for all content domains

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 9: Repositories

**Files:**
- Create: `SwiftUp/Data/QuestionRepository.swift`
- Create: `SwiftUp/Data/ProfileRepository.swift`
- Create: `SwiftUp/Data/InterviewRepository.swift`
- Create: `SwiftUp/Data/LeaderboardRepository.swift`
- Test: `SwiftUpTests/RepositoryTests.swift`

**Interfaces:**
- Consumes: models from Task 7, JSON files from Task 8
- Produces:
  - `@Observable final class QuestionRepository { let todayQuestions: [Question]; init(bundle: Bundle = .main) }`
  - `@Observable final class ProfileRepository { let profile: UserProfile; let levels: [LevelInfo]; let achievements: [Achievement]; let topics: [TopicAccuracy]; init(bundle: Bundle = .main) }`
  - `@Observable final class InterviewRepository { let categories: [InterviewCategory]; let questions: [InterviewQuestion]; init(bundle: Bundle = .main); func firstQuestion(in category: String) -> InterviewQuestion?; func nextQuestion(after current: InterviewQuestion) -> InterviewQuestion? }`
  - `@Observable final class LeaderboardRepository { let entries: [LeaderboardEntry]; init(bundle: Bundle = .main) }`

  All four are injected into the environment in Task 21 and read via `@Environment(Type.self)` by every feature view.

- [ ] **Step 1: Write the failing repository tests**

`SwiftUpTests/RepositoryTests.swift`:
```swift
import Testing
@testable import SwiftUp

struct RepositoryTests {
    @Test func questionRepositoryLoadsFiveQuestions() {
        let repo = QuestionRepository(bundle: .main)
        #expect(repo.todayQuestions.count == 5)
    }

    @Test func profileRepositoryLoadsProfileAndLevels() {
        let repo = ProfileRepository(bundle: .main)
        #expect(repo.profile.name == "Maya Reyes")
        #expect(repo.levels.count == 12)
        #expect(repo.achievements.count == 24)
        #expect(repo.topics.count == 12)
    }

    @Test func interviewRepositoryFindsFirstAndNextQuestion() {
        let repo = InterviewRepository(bundle: .main)
        #expect(repo.categories.count == 5)
        let first = repo.firstQuestion(in: "Swift fundamentals")
        #expect(first?.id == "iq02")
        if let first {
            #expect(repo.nextQuestion(after: first) != nil)
        }
    }

    @Test func leaderboardRepositoryLoadsEntriesSortedByRank() {
        let repo = LeaderboardRepository(bundle: .main)
        #expect(repo.entries.count == 8)
        #expect(repo.entries.first?.rank == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: FAIL — repositories not defined. (Note: `.main` bundle resolves correctly in the test target here because the JSON is copied into the *app* target's bundle, not the test target's — the test target must depend on running inside a host app, OR we load resources from the test bundle instead. To keep this simple and robust, Step 3 below loads from `Bundle(for:)`-style resource lookup against whichever bundle is passed in, and the unit test target gets its own copy of the same JSON files as a test-target resource. See step 2a.)

- [ ] **Step 2a: Give the test target its own copy of the JSON fixtures**

Copy the same 8 JSON files into a new `SwiftUpTests/Fixtures/` directory (identical content to `SwiftUp/Resources/*.json` from Task 8):

Run:
```bash
mkdir -p SwiftUpTests/Fixtures
cp SwiftUp/Resources/*.json SwiftUpTests/Fixtures/
```

No `project.yml` changes are needed for this: the `SwiftUpTests` target's `sources: [path: SwiftUpTests]` (already set in Task 1) picks up the new `Fixtures/*.json` files as test-bundle resources automatically, the same rule XcodeGen applies to the app target's `Resources/*.json`. Just re-run `xcodegen generate` after adding the files.

Update the four repository tests above to pass `bundle: .init(for: RepositoryTests.self)` (actually: since `RepositoryTests` is a struct, use a marker class) — add this to the top of `RepositoryTests.swift`:
```swift
private final class TestBundleMarker {}
private let testBundle = Bundle(for: TestBundleMarker.self)
```
and change every `Bundle.main` in the tests above to `testBundle`, and every repository init call to pass `bundle: testBundle`.

- [ ] **Step 3: Implement `QuestionRepository`**

`SwiftUp/Data/QuestionRepository.swift`:
```swift
import Foundation

@Observable
final class QuestionRepository {
    let todayQuestions: [Question]

    init(bundle: Bundle = .main) {
        todayQuestions = Self.decode([Question].self, filename: "questions", bundle: bundle) ?? []
    }
}

func decodeJSONResource<T: Decodable>(_ type: T.Type, filename: String, bundle: Bundle) -> T? {
    guard let url = bundle.url(forResource: filename, withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

private extension QuestionRepository {
    static func decode<T: Decodable>(_ type: T.Type, filename: String, bundle: Bundle) -> T? {
        decodeJSONResource(type, filename: filename, bundle: bundle)
    }
}
```

- [ ] **Step 4: Implement `ProfileRepository`**

`SwiftUp/Data/ProfileRepository.swift`:
```swift
import Foundation

@Observable
final class ProfileRepository {
    let profile: UserProfile
    let levels: [LevelInfo]
    let achievements: [Achievement]
    let topics: [TopicAccuracy]

    init(bundle: Bundle = .main) {
        profile = decodeJSONResource(UserProfile.self, filename: "profile", bundle: bundle)
            ?? UserProfile(name: "", initials: "", level: 0, levelTitle: "", xp: 0, xpForCurrentLevel: 0, xpForNextLevel: 1, streakDays: 0, freezesAvailable: 0, freezesTotal: 0, answeredCount: 0, accuracyPercent: 0, memberSinceDisplay: "")
        levels = decodeJSONResource([LevelInfo].self, filename: "levels", bundle: bundle) ?? []
        achievements = decodeJSONResource([Achievement].self, filename: "achievements", bundle: bundle) ?? []
        topics = decodeJSONResource([TopicAccuracy].self, filename: "topics", bundle: bundle) ?? []
    }

    var earnedAchievements: [Achievement] { achievements.filter { $0.status == .earned } }
    var inReachAchievements: [Achievement] { achievements.filter { $0.status == .inReach } }
    var lockedAchievements: [Achievement] { achievements.filter { $0.status == .locked } }
}
```

- [ ] **Step 5: Implement `InterviewRepository`**

`SwiftUp/Data/InterviewRepository.swift`:
```swift
import Foundation

@Observable
final class InterviewRepository {
    let categories: [InterviewCategory]
    let questions: [InterviewQuestion]

    init(bundle: Bundle = .main) {
        categories = decodeJSONResource([InterviewCategory].self, filename: "interview_categories", bundle: bundle) ?? []
        questions = decodeJSONResource([InterviewQuestion].self, filename: "interview_questions", bundle: bundle) ?? []
    }

    func firstQuestion(in category: String) -> InterviewQuestion? {
        questions.filter { $0.category == category }.sorted { $0.indexInCategory < $1.indexInCategory }.first
    }

    func nextQuestion(after current: InterviewQuestion) -> InterviewQuestion? {
        let sameCategory = questions.filter { $0.category == current.category }
            .sorted { $0.indexInCategory < $1.indexInCategory }
        guard let idx = sameCategory.firstIndex(where: { $0.id == current.id }) else { return nil }
        if idx + 1 < sameCategory.count { return sameCategory[idx + 1] }
        // wrap to the first question of the next category, if any
        guard let categoryIndex = categories.firstIndex(where: { $0.name == current.category }),
              categoryIndex + 1 < categories.count else { return sameCategory.first }
        return firstQuestion(in: categories[categoryIndex + 1].name) ?? sameCategory.first
    }
}
```

- [ ] **Step 6: Implement `LeaderboardRepository`**

`SwiftUp/Data/LeaderboardRepository.swift`:
```swift
import Foundation

@Observable
final class LeaderboardRepository {
    let entries: [LeaderboardEntry]

    init(bundle: Bundle = .main) {
        entries = (decodeJSONResource([LeaderboardEntry].self, filename: "leaderboard", bundle: bundle) ?? [])
            .sorted { $0.rank < $1.rank }
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add SwiftUp/Data SwiftUpTests/RepositoryTests.swift SwiftUpTests/Fixtures
git commit -m "Add JSON-backed repositories for questions, profile, interview bank, leaderboard

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 10: QuizSession state machine

**Files:**
- Create: `SwiftUp/Features/DailyQuiz/QuizSession.swift`
- Test: `SwiftUpTests/QuizSessionTests.swift`

**Interfaces:**
- Consumes: `Question` (Task 7)
- Produces: `@Observable final class QuizSession` with the API below — consumed by Task 12/13/14's quiz views.

```swift
@Observable final class QuizSession {
    init(questions: [Question])
    var questions: [Question] { get }
    var currentIndex: Int { get }
    var currentQuestion: Question? { get }
    var isFinished: Bool { get }
    var correctCount: Int { get }
    var totalXPEarned: Int { get }        // includes the +25 perfect-score bonus
    var elapsedSeconds: Int { get }
    func selectedOptionID(for question: Question) -> String?
    func isAnswered(_ question: Question) -> Bool
    func selectOption(_ optionID: String)  // no-op if current question already answered
    func advance()                          // moves to next question / marks finished
}
```

- [ ] **Step 1: Write the failing tests**

`SwiftUpTests/QuizSessionTests.swift`:
```swift
import Testing
@testable import SwiftUp

private func makeQuestions() -> [Question] {
    (1...5).map { i in
        Question(
            id: "q\(i)", topic: "Topic", format: .multipleChoice,
            prompt: "Prompt \(i)", codeSnippet: nil,
            options: [QuestionOption(id: "A", text: "A"), QuestionOption(id: "B", text: "B")],
            correctOptionID: "A", explanation: "Because.", xp: 15
        )
    }
}

struct QuizSessionTests {
    @Test func startsAtFirstQuestionUnanswered() {
        let session = QuizSession(questions: makeQuestions())
        #expect(session.currentIndex == 0)
        #expect(session.isFinished == false)
        #expect(session.isAnswered(session.currentQuestion!) == false)
    }

    @Test func selectingCorrectOptionCountsTowardScoreAndXP() {
        let session = QuizSession(questions: makeQuestions())
        session.selectOption("A")
        #expect(session.isAnswered(session.currentQuestion!) == true)
        #expect(session.selectedOptionID(for: session.currentQuestion!) == "A")
        session.advance()
        #expect(session.correctCount == 1)
    }

    @Test func secondSelectAfterAnsweringIsIgnored() {
        let session = QuizSession(questions: makeQuestions())
        session.selectOption("A")
        session.selectOption("B")
        #expect(session.selectedOptionID(for: session.currentQuestion!) == "A")
    }

    @Test func advancingPastLastQuestionFinishesSession() {
        let session = QuizSession(questions: makeQuestions())
        for _ in 0..<5 {
            session.selectOption("A")
            session.advance()
        }
        #expect(session.isFinished == true)
        #expect(session.currentQuestion == nil)
        #expect(session.correctCount == 5)
    }

    @Test func perfectScoreEarnsBonusXP() {
        let session = QuizSession(questions: makeQuestions())
        for _ in 0..<5 {
            session.selectOption("A")
            session.advance()
        }
        #expect(session.totalXPEarned == 5 * 15 + 25)
    }

    @Test func imperfectScoreEarnsNoBonus() {
        let session = QuizSession(questions: makeQuestions())
        session.selectOption("B")
        session.advance()
        for _ in 0..<4 {
            session.selectOption("A")
            session.advance()
        }
        #expect(session.totalXPEarned == 4 * 15)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: FAIL — `QuizSession` not defined.

- [ ] **Step 3: Implement `QuizSession`**

`SwiftUp/Features/DailyQuiz/QuizSession.swift`:
```swift
import Foundation

@Observable
final class QuizSession {
    let questions: [Question]
    private(set) var currentIndex: Int = 0
    private var answers: [String: String] = [:]
    private let startedAt = Date()
    private var finishedAt: Date?

    init(questions: [Question]) {
        self.questions = questions
    }

    var currentQuestion: Question? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    var isFinished: Bool { currentIndex >= questions.count }

    var correctCount: Int {
        questions.filter { answers[$0.id] == $0.correctOptionID }.count
    }

    var totalXPEarned: Int {
        let base = questions.reduce(0) { partial, q in
            partial + (answers[q.id] == q.correctOptionID ? q.xp : 0)
        }
        let bonus = (correctCount == questions.count && !questions.isEmpty) ? 25 : 0
        return base + bonus
    }

    var elapsedSeconds: Int {
        Int((finishedAt ?? Date()).timeIntervalSince(startedAt))
    }

    func selectedOptionID(for question: Question) -> String? {
        answers[question.id]
    }

    func isAnswered(_ question: Question) -> Bool {
        answers[question.id] != nil
    }

    func selectOption(_ optionID: String) {
        guard let question = currentQuestion, answers[question.id] == nil else { return }
        answers[question.id] = optionID
    }

    func advance() {
        currentIndex += 1
        if isFinished { finishedAt = Date() }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Features/DailyQuiz/QuizSession.swift SwiftUpTests/QuizSessionTests.swift
git commit -m "Add QuizSession state machine (scoring, progression, perfect-score bonus)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 11: Onboarding flow

**Files:**
- Create: `SwiftUp/Features/Onboarding/WelcomeView.swift`
- Create: `SwiftUp/Features/Onboarding/SkillAssessmentView.swift`
- Create: `SwiftUp/Features/Onboarding/TopicInterestsView.swift`
- Create: `SwiftUp/Features/Onboarding/OnboardingFlowView.swift`

**Interfaces:**
- Consumes: `Theme.*`, atoms from Tasks 3-4, `RuledMasthead`, `PlateNumeral`, `SegmentedPicker`
- Produces: `OnboardingFlowView(onComplete: () -> Void)` — consumed by Task 21's `RootView`.

- [ ] **Step 1: `WelcomeView` (canvas 5a)**

`SwiftUp/Features/Onboarding/WelcomeView.swift`:
```swift
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: "SwiftUp", right: "No. 1")

            VStack(alignment: .leading, spacing: 22) {
                Text("Five\nquestions\na day.")
                    .font(Theme.Fonts.heading(44))
                    .lineSpacing(-2)
                Text("Swift, SwiftUI, concurrency, ARC. Three minutes each morning, and a bank of interview questions for when it counts.")
                    .font(Theme.Fonts.body(16))
                    .foregroundStyle(Theme.Colors.neutral800)
            }
            .padding(.top, 44)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    PlateNumeral("1,240", font: Theme.Fonts.heading(34))
                    EyebrowLabel("Questions in the bank")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("12").font(Theme.Fonts.heading(34))
                    EyebrowLabel("Topics tagged")
                }
            }
            .padding(.top, 36)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Sign in with Apple")
                        .font(Theme.Fonts.heading(16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)

                Button(action: onContinue) {
                    Text("Use email instead")
                        .font(Theme.Fonts.body(15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                .foregroundStyle(Theme.Colors.text)

                Text("Your answers stay on your device unless you join a leaderboard.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Colors.neutral700)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
```

- [ ] **Step 2: `SkillAssessmentView` (canvas 5b)**

`SwiftUp/Features/Onboarding/SkillAssessmentView.swift`:
```swift
import SwiftUI

enum SkillLevel: String, CaseIterable, Identifiable {
    case junior = "Junior", mid = "Mid", senior = "Senior"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .junior: "Shipping with SwiftUI, still meeting the SDK. Under two years."
        case .mid: "Comfortable in UIKit and SwiftUI, reaching for concurrency and architecture. Two to five years."
        case .senior: "Leading work, designing systems, interviewing others. Five years and up."
        }
    }
}

struct SkillAssessmentView: View {
    @State private var selection: SkillLevel = .mid
    @State private var preparingForInterviews = "Yes"
    let onContinue: (SkillLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Step 1 of 2")
                Spacer()
            }
            .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)

            HStack(spacing: 4) {
                Rectangle().fill(Theme.Colors.text).frame(height: 4)
                Rectangle().fill(Theme.Colors.neutral300).frame(height: 4)
            }
            .padding(.top, 6)

            Text("Where are you\nright now?")
                .font(Theme.Fonts.heading(30))
                .padding(.top, 24)
            Text("This only sets your first week. The quiz adapts from your actual answers after that.")
                .font(Theme.Fonts.body(14.5))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 10)

            VStack(spacing: 0) {
                ForEach(SkillLevel.allCases) { level in
                    RuledRow(showBottomRule: level == SkillLevel.allCases.last, minHeight: 60) {
                        Circle()
                            .strokeBorder(selection == level ? Theme.Colors.accent : Theme.Colors.divider, lineWidth: 1.5)
                            .background(Circle().fill(selection == level ? Theme.Colors.accent : Color.clear))
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(level.rawValue).font(Theme.Fonts.heading(17))
                            Text(level.blurb).font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral700)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, selection == level ? 10 : 0)
                    .background(selection == level ? Theme.Colors.accent100 : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = level }
                }
            }
            .padding(.top, 20)

            HStack {
                EyebrowLabel("Preparing for interviews?")
                Spacer()
                SegmentedPicker(options: ["Yes", "Not yet"], selection: $preparingForInterviews)
            }
            .padding(.top, 20)

            Spacer()

            Button {
                onContinue(selection)
            } label: {
                Text("Choose topics")
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }
}

#Preview {
    SkillAssessmentView(onContinue: { _ in })
}
```

- [ ] **Step 3: `TopicInterestsView` (canvas 5c)**

`SwiftUp/Features/Onboarding/TopicInterestsView.swift`:
```swift
import SwiftUI

struct TopicInterestsView: View {
    static let allTopics = [
        "Swift language", "SwiftUI", "Concurrency", "UIKit", "Memory · ARC",
        "Architecture", "Networking", "Core Data", "Testing", "Xcode", "App lifecycle", "Combine"
    ]

    @State private var selected: Set<String> = ["Swift language", "Concurrency", "Memory · ARC", "Testing"]
    let onFinish: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Step 2 of 2")
                Spacer()
            }
            .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)

            HStack(spacing: 4) {
                Rectangle().fill(Theme.Colors.text).frame(height: 4)
                Rectangle().fill(Theme.Colors.text).frame(height: 4)
            }
            .padding(.top, 6)

            Text("What should we\nweight toward?")
                .font(Theme.Fonts.heading(30))
                .padding(.top, 24)
            Text("Pick as many as you like. Everything else still appears, just less often.")
                .font(Theme.Fonts.body(14.5))
                .foregroundStyle(Theme.Colors.neutral800)
                .padding(.top, 10)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                ForEach(Self.allTopics, id: \.self) { topic in
                    Text(topic)
                        .font(.system(size: 14.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(selected.contains(topic) ? Theme.Colors.accent : Color.clear)
                        .foregroundStyle(selected.contains(topic) ? Theme.Colors.bg : Theme.Colors.text)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(selected.contains(topic) ? Color.clear : Theme.Colors.divider))
                        .onTapGesture { toggle(topic) }
                }
            }
            .padding(.top, 26)

            HStack {
                EyebrowLabel("\(selected.count) selected")
                Spacer()
                Button("Select all") { selected = Set(Self.allTopics) }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.accent700)
            }
            .padding(.top, 22)
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Colors.divider).frame(height: 1) }

            Spacer()

            Button(action: onFinish) {
                Text("Start day one")
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private func toggle(_ topic: String) {
        if selected.contains(topic) { selected.remove(topic) } else { selected.insert(topic) }
    }
}

#Preview {
    TopicInterestsView(onFinish: {})
}
```

- [ ] **Step 4: `OnboardingFlowView` container**

`SwiftUp/Features/Onboarding/OnboardingFlowView.swift`:
```swift
import SwiftUI

struct OnboardingFlowView: View {
    enum Step { case welcome, skill, topics }

    @State private var step: Step = .welcome
    let onComplete: () -> Void

    var body: some View {
        switch step {
        case .welcome:
            WelcomeView(onContinue: { step = .skill })
        case .skill:
            SkillAssessmentView(onContinue: { _ in step = .topics })
        case .topics:
            TopicInterestsView(onFinish: onComplete)
        }
    }
}

#Preview {
    OnboardingFlowView(onComplete: {})
}
```

- [ ] **Step 5: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add SwiftUp/Features/Onboarding
git commit -m "Add onboarding flow (welcome, skill assessment, topic interests)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 12: DailyQuizEntryView (canvas 1a)

**Files:**
- Create: `SwiftUp/Features/DailyQuiz/DailyQuizEntryView.swift`

**Interfaces:**
- Consumes: `ProfileRepository`, `QuestionRepository` (via `@Environment`), `PlateNumeral`, `ThinProgressBar`, `RuledMasthead`
- Produces: `DailyQuizEntryView(onBegin: () -> Void)` — consumed by Task 14's `TodayFlowView`.

- [ ] **Step 1: Implement**

`SwiftUp/Features/DailyQuiz/DailyQuizEntryView.swift`:
```swift
import SwiftUI

struct DailyQuizEntryView: View {
    @Environment(ProfileRepository.self) private var profileRepo
    @Environment(QuestionRepository.self) private var questionRepo
    let onBegin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: "Monday, September 7", right: "Edition 128")

            VStack(alignment: .leading, spacing: 12) {
                EyebrowLabel("The daily five", color: Theme.Colors.accent700)
                Text(topicsHeadline)
                    .font(Theme.Fonts.heading(40))
                Text("Five questions, drawn this morning. About three minutes.")
                    .font(Theme.Fonts.body(16))
                    .foregroundStyle(Theme.Colors.neutral700)
            }
            .padding(.top, 40)

            Spacer()

            HStack(alignment: .bottom, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel("Streak")
                    PlateNumeral("\(profileRepo.profile.streakDays)", font: Theme.Fonts.heading(64))
                    Text("days · \(profileRepo.profile.freezesAvailable) freeze held")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
                VStack(alignment: .leading, spacing: 10) {
                    EyebrowLabel("Level \(profileRepo.profile.level)")
                    Text(profileRepo.profile.levelTitle).font(Theme.Fonts.heading(18))
                    ThinProgressBar(fraction: profileRepo.profile.levelProgressFraction)
                        .frame(width: 118)
                    Text("\(profileRepo.profile.xp) xp · \(profileRepo.profile.xpToNextLevel) to L\(profileRepo.profile.level + 1)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.neutral600)
                }
            }

            Button(action: onBegin) {
                Text("Begin today's five")
                    .font(Theme.Fonts.heading(17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.bg)
            .padding(.top, 30)
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private var topicsHeadline: String {
        let topics = Array(Set(questionRepo.todayQuestions.map(\.topic))).sorted()
        return topics.joined(separator: ",\n") + "."
    }
}

#Preview {
    DailyQuizEntryView(onBegin: {})
        .environment(ProfileRepository())
        .environment(QuestionRepository())
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/Features/DailyQuiz/DailyQuizEntryView.swift
git commit -m "Add DailyQuizEntryView (quiz entry / streak+level dashboard)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 13: QuizQuestionView (all 4 formats — canvas 1b/1c/1d/1e)

**Files:**
- Create: `SwiftUp/Features/DailyQuiz/QuizQuestionView.swift`

**Interfaces:**
- Consumes: `QuizSession` (Task 10), `Question`/`QuestionFormat` (Task 7), `RuledRow`
- Produces: `QuizQuestionView(session: QuizSession, onAdvance: () -> Void)` — consumed by Task 14's `TodayFlowView`.

- [ ] **Step 1: Implement**

`SwiftUp/Features/DailyQuiz/QuizQuestionView.swift`:
```swift
import SwiftUI

struct QuizQuestionView: View {
    let session: QuizSession
    let onAdvance: () -> Void

    var body: some View {
        if let question = session.currentQuestion {
            content(for: question)
        }
    }

    @ViewBuilder
    private func content(for question: Question) -> some View {
        let answered = session.isAnswered(question)
        let selected = session.selectedOptionID(for: question)
        let isCorrect = selected == question.correctOptionID

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Question \(String(format: "%02d", session.currentIndex + 1)) / \(String(format: "%02d", session.questions.count))")
                Spacer()
                Text(question.topic)
                    .font(.system(size: 11))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Theme.Colors.accent100)
                    .foregroundStyle(Theme.Colors.accent800)
            }
            .font(.system(size: 10)).foregroundStyle(Theme.Colors.neutral700)

            HStack(spacing: 4) {
                ForEach(0..<session.questions.count, id: \.self) { i in
                    Rectangle()
                        .fill(tickColor(at: i))
                        .frame(height: 4)
                }
            }
            .padding(.top, 6)

            Text(question.prompt)
                .font(answered ? Theme.Fonts.heading(21) : Theme.Fonts.heading(26))
                .foregroundStyle(answered ? Theme.Colors.neutral700 : Theme.Colors.text)
                .padding(.top, answered ? 24 : 34)

            if let code = question.codeSnippet {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.Colors.neutral800)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
                    .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
                    .padding(.top, 16)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(question.options) { option in
                        optionRow(option, question: question, answered: answered, selected: selected)
                    }
                }
            }
            .padding(.top, question.codeSnippet == nil ? 30 : 16)

            if answered {
                VStack(alignment: .leading, spacing: 12) {
                    Text(isCorrect ? "Correct." : "Not quite.")
                        .font(Theme.Fonts.heading(20))
                        .foregroundStyle(isCorrect ? Theme.Colors.accent700 : Theme.Colors.accent2800)
                    Text(question.explanation)
                        .font(Theme.Fonts.body(14.5))
                        .foregroundStyle(Theme.Colors.neutral800)
                }
                .padding(.top, 20)

                Button(action: onAdvance) {
                    Text("Next question")
                        .font(Theme.Fonts.heading(17))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
                .padding(.top, 20)
            } else {
                Spacer(minLength: 20)
                HStack {
                    Button("Skip", action: onAdvance)
                        .foregroundStyle(Theme.Colors.accent)
                    Spacer()
                    EyebrowLabel("Tap an answer")
                }
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }

    private func tickColor(at index: Int) -> Color {
        guard index <= session.currentIndex else { return Theme.Colors.neutral300 }
        guard index < session.currentIndex || session.isAnswered(session.questions[index]) else {
            return Theme.Colors.text
        }
        let q = session.questions[index]
        guard let picked = session.selectedOptionID(for: q) else { return Theme.Colors.text }
        return picked == q.correctOptionID ? Theme.Colors.accent : Theme.Colors.accent2
    }

    @ViewBuilder
    private func optionRow(_ option: QuestionOption, question: Question, answered: Bool, selected: String?) -> some View {
        let isSelected = selected == option.id
        let isCorrectOption = option.id == question.correctOptionID
        let showAsCorrect = answered && isCorrectOption
        let showAsWrong = answered && isSelected && !isCorrectOption

        HStack(alignment: .top, spacing: 12) {
            Text(option.id.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(showAsCorrect ? Theme.Colors.accent700 : (showAsWrong ? Theme.Colors.accent2800 : Theme.Colors.neutral600))
                .frame(width: 14, alignment: .leading)
            Text(option.text)
                .font(Theme.Fonts.body(15.5))
                .foregroundStyle(Theme.Colors.text)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, showAsCorrect || showAsWrong ? 11 : 2)
        .background(showAsCorrect ? Theme.Colors.accent100 : (showAsWrong ? Theme.Colors.accent2100 : Color.clear))
        .opacity(answered && !isSelected && !isCorrectOption ? 0.4 : 1)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !answered else { return }
            session.selectOption(option.id)
        }
    }
}

#Preview("Unanswered") {
    let session = QuizSession(questions: QuestionRepository().todayQuestions)
    return QuizQuestionView(session: session, onAdvance: {})
}

#Preview("Answered") {
    let session = QuizSession(questions: QuestionRepository().todayQuestions)
    session.selectOption("A")
    return QuizQuestionView(session: session, onAdvance: {})
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/Features/DailyQuiz/QuizQuestionView.swift
git commit -m "Add QuizQuestionView covering multiple choice, spot-the-bug, and fill-in-the-blank formats

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 14: QuizSummaryView (canvas 1f) + TodayFlowView wiring

**Files:**
- Create: `SwiftUp/Features/DailyQuiz/QuizSummaryView.swift`
- Create: `SwiftUp/Features/DailyQuiz/TodayFlowView.swift`

**Interfaces:**
- Consumes: `QuizSession` (Task 10), `DailyQuizEntryView` (Task 12), `QuizQuestionView` (Task 13), `PlateNumeral`, `ThinProgressBar`, `ProfileRepository`
- Produces: `TodayFlowView()` — this is the Today tab's root, consumed directly by Task 21's `MainTabView`.

- [ ] **Step 1: `QuizSummaryView`**

`SwiftUp/Features/DailyQuiz/QuizSummaryView.swift`:
```swift
import SwiftUI

struct QuizSummaryView: View {
    let session: QuizSession
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RuledMasthead(left: "Edition 128 · closed just now", right: "\(session.elapsedSeconds / 60) min \(session.elapsedSeconds % 60) s")

            HStack(alignment: .bottom, spacing: 22) {
                PlateNumeral("\(session.correctCount)/\(session.questions.count)", font: Theme.Fonts.heading(84))
                VStack(alignment: .leading, spacing: 6) {
                    Text("+\(session.totalXPEarned) xp")
                        .font(Theme.Fonts.heading(22))
                        .foregroundStyle(Theme.Colors.accent700)
                }
            }
            .padding(.top, 34)

            Spacer()

            HStack(spacing: 12) {
                Button("Review misses", action: onDone)
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .background(Theme.Colors.accent)
                .foregroundStyle(Theme.Colors.bg)
            }
        }
        .padding(24)
        .background(Theme.Colors.bg)
    }
}

#Preview {
    let session = QuizSession(questions: QuestionRepository().todayQuestions)
    return QuizSummaryView(session: session, onDone: {})
}
```

- [ ] **Step 2: `TodayFlowView`**

`SwiftUp/Features/DailyQuiz/TodayFlowView.swift`:
```swift
import SwiftUI

struct TodayFlowView: View {
    enum Stage { case entry, question, summary }

    @Environment(QuestionRepository.self) private var questionRepo
    @State private var stage: Stage = .entry
    @State private var session: QuizSession?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:
                    DailyQuizEntryView(onBegin: startQuiz)
                case .question:
                    if let session {
                        QuizQuestionView(session: session, onAdvance: advance)
                    }
                case .summary:
                    if let session {
                        QuizSummaryView(session: session, onDone: finish)
                    }
                }
            }
        }
    }

    private func startQuiz() {
        session = QuizSession(questions: questionRepo.todayQuestions)
        stage = .question
    }

    private func advance() {
        session?.advance()
        if session?.isFinished == true {
            stage = .summary
        }
    }

    private func finish() {
        session = nil
        stage = .entry
    }
}

#Preview {
    TodayFlowView()
        .environment(ProfileRepository())
        .environment(QuestionRepository())
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/DailyQuiz/QuizSummaryView.swift SwiftUp/Features/DailyQuiz/TodayFlowView.swift
git commit -m "Add QuizSummaryView and wire the Today tab's full quiz flow

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 15: Profile — ProfileHomeView, MilestonesView, AllLevelsView (canvas 3a/3b/3c)

**Files:**
- Create: `SwiftUp/Features/Profile/ProfileHomeView.swift`
- Create: `SwiftUp/Features/Profile/MilestonesView.swift`
- Create: `SwiftUp/Features/Profile/AllLevelsView.swift`

**Interfaces:**
- Consumes: `ProfileRepository` (Task 9), `AchievementSeal`/`LockedSeal` (Task 5), `PlateNumeral`, `ThinProgressBar`, `RuledMasthead`
- Produces: `ProfileHomeView()` (navigates to `MilestonesView`, `AllLevelsView`, and — via Task 16 — `AccuracyByTopicView`/`BadgesView`, and — via Task 17 — `SettingsView`) — this becomes the Record tab's `NavigationStack` root in Task 21.

- [ ] **Step 1: `ProfileHomeView`**

`SwiftUp/Features/Profile/ProfileHomeView.swift`:
```swift
import SwiftUI

struct ProfileHomeView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: repo.profile.name, right: "Top 4% this week")

                HStack(alignment: .top, spacing: 16) {
                    Circle().fill(Theme.Colors.neutral200)
                        .frame(width: 58, height: 58)
                        .overlay(Text(repo.profile.initials).font(Theme.Fonts.heading(22)).foregroundStyle(Theme.Colors.neutral700))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(repo.profile.name).font(Theme.Fonts.heading(28))
                        Text("Level \(repo.profile.level) · \(repo.profile.levelTitle)")
                            .font(Theme.Fonts.body(14.5)).foregroundStyle(Theme.Colors.neutral700)
                        ThinProgressBar(fraction: repo.profile.levelProgressFraction, height: 7)
                            .frame(width: 170)
                    }
                }
                .padding(.top, 24)

                HStack {
                    EyebrowLabel("\(repo.profile.xpToNextLevel) xp to level \(repo.profile.level + 1)", color: Theme.Colors.accent700)
                    Spacer()
                    NavigationLink("All 12 levels →") { AllLevelsView() }
                        .font(.system(size: 12)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 10)

                HStack(spacing: 24) {
                    statBlock("Streak") { PlateNumeral("\(repo.profile.streakDays)", font: Theme.Fonts.heading(52)) }
                    statBlock("Answered") { Text("\(repo.profile.answeredCount)").font(Theme.Fonts.heading(52)) }
                    statBlock("Accuracy") { Text("\(repo.profile.accuracyPercent)%").font(Theme.Fonts.heading(52)) }
                }
                .padding(.top, 26)

                HStack {
                    EyebrowLabel("Seals earned")
                    Spacer()
                    NavigationLink("\(repo.earnedAchievements.count) / \(repo.achievements.count)") { BadgesView() }
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 26)

                HStack(spacing: 14) {
                    ForEach(repo.earnedAchievements.prefix(4)) { a in
                        AchievementSeal(kind: a.sealKind, filled: true, size: 46)
                    }
                    LockedSeal(remainingCount: max(0, repo.earnedAchievements.count - 4), size: 46)
                }
                .padding(.top, 14)

                HStack {
                    EyebrowLabel("Next milestone")
                    Spacer()
                    NavigationLink("All milestones →") { MilestonesView() }
                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.accent700)
                }
                .padding(.top, 28)

                VStack(spacing: 14) {
                    ForEach(repo.inReachAchievements) { a in
                        milestoneRow(a)
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Settings") { SettingsView() }
            }
        }
    }

    @ViewBuilder
    private func statBlock<Content: View>(_ label: String, @ViewBuilder value: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            EyebrowLabel(label)
            value()
        }
    }

    @ViewBuilder
    private func milestoneRow(_ achievement: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                Text(achievement.title).font(Theme.Fonts.heading(18))
                Spacer()
                if let current = achievement.progressCurrent, let target = achievement.progressTarget {
                    EyebrowLabel("\(target - current) to go", color: Theme.Colors.accent700)
                }
            }
            ThinProgressBar(fraction: achievement.progressFraction ?? 0, fillColor: achievement.sealKind == .topicMastery ? Theme.Colors.accent2 : Theme.Colors.accent, height: 8)
            Text(achievement.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
        }
        .padding(.top, 12)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { ProfileHomeView() }
        .environment(ProfileRepository())
}
```

- [ ] **Step 2: `MilestonesView`**

`SwiftUp/Features/Profile/MilestonesView.swift`:
```swift
import SwiftUI

struct MilestonesView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Milestones").font(Theme.Fonts.heading(30))
                Text("\(repo.earnedAchievements.count) printed, \(repo.lockedAchievements.count) to go. \(repo.inReachAchievements.count) are within reach this week.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 10)

                EyebrowLabel("In reach", color: Theme.Colors.accent700).padding(.top, 24)
                VStack(spacing: 16) {
                    ForEach(repo.inReachAchievements) { a in
                        HStack(alignment: .top, spacing: 14) {
                            AchievementSeal(kind: a.sealKind, filled: false, size: 42)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(a.title).font(Theme.Fonts.heading(17))
                                    Spacer()
                                    if let current = a.progressCurrent, let target = a.progressTarget {
                                        EyebrowLabel("\(target - current) to go", color: Theme.Colors.accent700)
                                    }
                                }
                                ThinProgressBar(fraction: a.progressFraction ?? 0, height: 8)
                                Text(a.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                        }
                    }
                }
                .padding(.top, 14)

                EyebrowLabel("Recently printed").padding(.top, 28)
                VStack(spacing: 0) {
                    ForEach(repo.earnedAchievements.prefix(3)) { a in
                        RuledRow {
                            AchievementSeal(kind: a.sealKind, filled: true, size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(Theme.Fonts.heading(15.5))
                                Text("+\(a.xpReward) xp").font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                            Spacer()
                            EyebrowLabel(a.earnedDateDisplay ?? "")
                        }
                    }
                }
                .padding(.top, 12)

                EyebrowLabel("Level ladder").padding(.top, 26)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(repo.levels) { level in
                        VStack(spacing: 6) {
                            Rectangle()
                                .fill(level.number == repo.profile.level ? Theme.Colors.accent : (level.number < repo.profile.level ? Theme.Colors.text : Theme.Colors.neutral200))
                                .frame(height: level.number == repo.profile.level ? 16 : 9)
                            if level.number == 1 || level.number == repo.levels.count || level.number == repo.profile.level {
                                Text("\(level.number)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(level.number == repo.profile.level ? Theme.Colors.accent700 : Theme.Colors.neutral600)
                            }
                        }
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { MilestonesView() }
        .environment(ProfileRepository())
}
```

- [ ] **Step 3: `AllLevelsView`**

`SwiftUp/Features/Profile/AllLevelsView.swift`:
```swift
import SwiftUI

struct AllLevelsView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Twelve levels").font(Theme.Fonts.heading(30))

                HStack(alignment: .bottom, spacing: 16) {
                    PlateNumeral("\(repo.profile.level)", font: Theme.Fonts.heading(60))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(repo.profile.levelTitle).font(Theme.Fonts.heading(17))
                        ThinProgressBar(fraction: repo.profile.levelProgressFraction, height: 9)
                        Text("\(repo.profile.xp) of \(repo.profile.xpForNextLevel) xp · \(repo.profile.xpToNextLevel) to go")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
                .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)

                VStack(spacing: 0) {
                    ForEach(repo.levels) { level in
                        levelRow(level)
                    }
                }
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    @ViewBuilder
    private func levelRow(_ level: LevelInfo) -> some View {
        let isCurrent = level.number == repo.profile.level
        let isPast = level.number < repo.profile.level

        HStack(spacing: 12) {
            Text(String(format: "%02d", level.number))
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                .frame(width: 22, alignment: .leading)
                .foregroundStyle(isCurrent ? Theme.Colors.accent700 : Theme.Colors.neutral700)
            Text(level.title)
                .font(isCurrent ? Theme.Fonts.heading(15.5) : Theme.Fonts.body(14))
            Spacer()
            if isCurrent {
                EyebrowLabel("You are here", color: Theme.Colors.accent700)
            } else {
                Text("\(level.xpThreshold)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isPast ? Theme.Colors.neutral700 : Theme.Colors.accent700)
            }
        }
        .padding(.vertical, isCurrent ? 13 : 6)
        .padding(.horizontal, isCurrent ? 10 : 0)
        .background(isCurrent ? Theme.Colors.accent100 : Color.clear)
        .opacity(isPast ? 0.5 : 1)
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .bottom)
    }
}

#Preview {
    NavigationStack { AllLevelsView() }
        .environment(ProfileRepository())
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add SwiftUp/Features/Profile/ProfileHomeView.swift SwiftUp/Features/Profile/MilestonesView.swift SwiftUp/Features/Profile/AllLevelsView.swift
git commit -m "Add Profile home, milestones, and all-levels views

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 16: AccuracyByTopicView + BadgesView (canvas 2b/2c)

**Files:**
- Create: `SwiftUp/Features/Profile/AccuracyByTopicView.swift`
- Create: `SwiftUp/Features/Profile/BadgesView.swift`

**Interfaces:**
- Consumes: `ProfileRepository`, `ThinProgressBar`, `AchievementSeal`/`LockedSeal`
- Produces: `AccuracyByTopicView()`, `BadgesView()` — both already referenced by Task 15's `ProfileHomeView` `NavigationLink`s.

- [ ] **Step 1: `AccuracyByTopicView`**

`SwiftUp/Features/Profile/AccuracyByTopicView.swift`:
```swift
import SwiftUI

struct AccuracyByTopicView: View {
    @Environment(ProfileRepository.self) private var repo

    private var sortedTopics: [TopicAccuracy] {
        repo.topics.sorted { $0.accuracyPercent < $1.accuracyPercent }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Accuracy by\ntopic").font(Theme.Fonts.heading(30))
                Text("\(repo.topics.count) topics, \(repo.profile.answeredCount) questions answered. Ranked worst first — the quiz weights your next five toward the bottom of this list.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(sortedTopics) { topic in
                        RuledRow(minHeight: 40) {
                            Text(topic.name).font(Theme.Fonts.body(14.5))
                            Spacer()
                            ThinProgressBar(
                                fraction: Double(topic.accuracyPercent) / 100,
                                fillColor: topic.accuracyPercent < 60 ? Theme.Colors.accent2 : Theme.Colors.accent,
                                height: 8
                            )
                            .frame(width: 130)
                            Text("\(topic.accuracyPercent)").font(Theme.Fonts.heading(14)).frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { AccuracyByTopicView() }
        .environment(ProfileRepository())
}
```

- [ ] **Step 2: `BadgesView`**

`SwiftUp/Features/Profile/BadgesView.swift`:
```swift
import SwiftUI

struct BadgesView: View {
    @Environment(ProfileRepository.self) private var repo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Badges").font(Theme.Fonts.heading(30))
                HStack(spacing: 8) {
                    PlateNumeral("\(repo.earnedAchievements.count)", font: Theme.Fonts.heading(32))
                    Text("of \(repo.achievements.count) earned").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                }
                .padding(.top, 10)

                EyebrowLabel("Earned").padding(.top, 26)
                VStack(spacing: 0) {
                    ForEach(Array(repo.earnedAchievements.prefix(4).enumerated()), id: \.element.id) { index, a in
                        RuledRow(minHeight: 50) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(Theme.Fonts.heading(15.5))
                                Text(a.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                            Spacer()
                            EyebrowLabel(a.earnedDateDisplay ?? "")
                        }
                    }
                }
                .padding(.top, 10)

                if repo.earnedAchievements.count > 4 {
                    Text("\(repo.earnedAchievements.count - 4) more earned →")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                        .padding(.top, 10)
                }

                EyebrowLabel("Next up").padding(.top, 24)
                VStack(spacing: 0) {
                    ForEach(Array((repo.inReachAchievements).enumerated()), id: \.element.id) { index, a in
                        RuledRow(minHeight: 50) {
                            Text(String(format: "%02d", 10 + index))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.neutral600)
                                .frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(Theme.Fonts.heading(15.5))
                                Text(a.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral600)
                            }
                            Spacer()
                        }
                        .opacity(0.55)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { BadgesView() }
        .environment(ProfileRepository())
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/Profile/AccuracyByTopicView.swift SwiftUp/Features/Profile/BadgesView.swift
git commit -m "Add accuracy-by-topic and badges detail views

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 17: SettingsView + NotificationSettingsView (canvas 4a/4b)

**Files:**
- Create: `SwiftUp/Features/Settings/SettingsView.swift`
- Create: `SwiftUp/Features/Settings/NotificationSettingsView.swift`

**Interfaces:**
- Consumes: `SegmentedPicker`, `SquareToggle`, `RuledRow`
- Produces: `SettingsView()` (already linked from Task 15's `ProfileHomeView` toolbar), `NotificationSettingsView()`, and a link to `SupportView` (Task 18).

- [ ] **Step 1: `SettingsView`**

`SwiftUp/Features/Settings/SettingsView.swift`:
```swift
import SwiftUI

struct SettingsView: View {
    @State private var difficulty = "Adaptive"
    @State private var cacheOffline = true
    @State private var showOnLeaderboards = true
    @State private var shareStats = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(Theme.Fonts.heading(30))

                EyebrowLabel("Account").padding(.top, 24)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text("Signed in with Apple").font(Theme.Fonts.body(15))
                        Spacer()
                        Text("maya@icloud.com").font(.system(size: 13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Support SwiftUp").font(Theme.Fonts.body(15))
                        Spacer()
                        NavigationLink("Donate →") { SupportView() }
                            .font(.system(size: 13.5)).foregroundStyle(Theme.Colors.accent700)
                    }
                }
                .padding(.top, 8)

                EyebrowLabel("Daily quiz").padding(.top, 22)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text("Reminder").font(Theme.Fonts.body(15))
                        Spacer()
                        Text("07:30 →").font(.system(size: 14)).foregroundStyle(Theme.Colors.accent700)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Cache for offline").font(Theme.Fonts.body(15))
                        Spacer()
                        SquareToggle(isOn: $cacheOffline)
                    }
                }
                .padding(.top, 8)

                EyebrowLabel("Difficulty").padding(.top, 22)
                SegmentedPicker(options: ["Adaptive", "Junior", "Mid", "Senior"], selection: $difficulty)
                    .padding(.top, 10)
                Text("Adaptive weights your next five toward topics under 60%.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 8)

                EyebrowLabel("Privacy & appearance").padding(.top, 22)
                VStack(spacing: 0) {
                    RuledRow(minHeight: 46) {
                        Text("Show me on leaderboards").font(Theme.Fonts.body(15))
                        Spacer()
                        SquareToggle(isOn: $showOnLeaderboards)
                    }
                    RuledRow(minHeight: 46) {
                        Text("Share stats with friends").font(Theme.Fonts.body(15))
                        Spacer()
                        SquareToggle(isOn: $shareStats)
                    }
                    RuledRow(showBottomRule: true, minHeight: 46) {
                        Text("Appearance").font(Theme.Fonts.body(15))
                        Spacer()
                        Text("System →").font(.system(size: 13.5)).foregroundStyle(Theme.Colors.neutral700)
                    }
                }
                .padding(.top, 8)

                HStack(spacing: 18) {
                    Text("Sign out").font(.system(size: 14)).foregroundStyle(Theme.Colors.accent700)
                    Text("Delete account").font(.system(size: 14)).foregroundStyle(Theme.Colors.accent2800)
                }
                .padding(.top, 20)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Notifications") { NotificationSettingsView() }
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
```

- [ ] **Step 2: `NotificationSettingsView`**

`SwiftUp/Features/Settings/NotificationSettingsView.swift`:
```swift
import SwiftUI

private struct NotificationRow: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let defaultOn: Bool
}

struct NotificationSettingsView: View {
    private static let rows = [
        NotificationRow(title: "Daily quiz reminder", detail: "Every day at 07:30", defaultOn: true),
        NotificationRow(title: "Streak at risk", detail: "21:00, only when today is unfinished", defaultOn: true),
        NotificationRow(title: "New questions & topics", detail: "When the bank gains a category", defaultOn: false),
        NotificationRow(title: "Weekly edition", detail: "Sunday summary of the week's accuracy", defaultOn: true),
    ]

    @State private var toggles: [Bool] = NotificationSettingsView.rows.map(\.defaultOn)
    @State private var quietHoursOn = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications").font(Theme.Fonts.heading(30))
                Text("Three a day at most.").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    ForEach(Array(Self.rows.enumerated()), id: \.element.id) { index, row in
                        RuledRow(showBottomRule: index == Self.rows.count - 1, minHeight: 52) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(Theme.Fonts.heading(15.5))
                                Text(row.detail).font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                            }
                            Spacer()
                            SquareToggle(isOn: $toggles[index])
                        }
                    }
                }
                .padding(.top, 22)

                EyebrowLabel("Quiet hours").padding(.top, 22)
                RuledRow(showBottomRule: true, minHeight: 46) {
                    Text("22:00 — 07:00").font(Theme.Fonts.body(15))
                    Spacer()
                    SquareToggle(isOn: $quietHoursOn)
                }
                .padding(.top, 8)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { NotificationSettingsView() }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/Settings
git commit -m "Add Settings and Notifications views

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 18: SupportView (canvas 6a)

**Files:**
- Create: `SwiftUp/Features/Support/SupportView.swift`

**Interfaces:**
- Consumes: `Theme.*`, `RuledMasthead`
- Produces: `SupportView()` — already linked from Task 17's `SettingsView`.

- [ ] **Step 1: Implement**

`SwiftUp/Features/Support/SupportView.swift`:
```swift
import SwiftUI

struct SupportView: View {
    private let promises = [
        "No subscription. Everything is free, and stays free.",
        "No unwanted ads. Nothing plays unless you start it.",
        "No trial that quietly becomes a bill.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "Our promise", right: "Standing notice")

                Text("We won't\nsurprise you.")
                    .font(Theme.Fonts.heading(34))
                    .padding(.top, 22)

                VStack(spacing: 0) {
                    ForEach(Array(promises.enumerated()), id: \.offset) { index, text in
                        RuledRow(showBottomRule: index == promises.count - 1, minHeight: 40) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(text).font(Theme.Fonts.body(15.5))
                        }
                    }
                }
                .padding(.top, 22)

                donationBlock(
                    title: "Donate", tag: "One-off or monthly",
                    detail: "Any amount, cancel-free. It pays for running the app and writing new questions.",
                    buttonTitle: "Make a donation", primary: true
                )
                .padding(.top, 22)

                donationBlock(
                    title: "Watch an ad, at will", tag: "30 seconds",
                    detail: "Start one whenever you feel like helping out. Never shown unprompted.",
                    buttonTitle: "Watch one now", primary: false
                )
                .padding(.top, 20)

                Text("Neither one unlocks anything. You already have all of it.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.neutral700)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    @ViewBuilder
    private func donationBlock(title: String, tag: String, detail: String, buttonTitle: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(Theme.Fonts.heading(19))
                Spacer()
                EyebrowLabel(tag)
            }
            Text(detail).font(Theme.Fonts.body(13.5)).foregroundStyle(Theme.Colors.neutral700)
            Button(buttonTitle) {}
                .font(.system(size: 16))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(primary ? Theme.Colors.accent : Color.clear)
                .foregroundStyle(primary ? Theme.Colors.bg : Theme.Colors.text)
                .overlay(primary ? nil : RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                .padding(.top, 5)
        }
        .padding(.top, 16)
        .overlay(Rectangle().fill(Theme.Colors.divider), alignment: .top)
    }
}

#Preview {
    SupportView()
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/Features/Support/SupportView.swift
git commit -m "Add Support / donate view

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 19: InterviewBankView + InterviewQuestionDetailView (canvas 7a/7b)

**Files:**
- Create: `SwiftUp/Features/InterviewPrep/InterviewBankView.swift`
- Create: `SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift`

**Interfaces:**
- Consumes: `InterviewRepository` (Task 9), `ThinProgressBar`, `SegmentedPicker`
- Produces: `InterviewBankView()` — the Prep tab's `NavigationStack` root, consumed by Task 21.

- [ ] **Step 1: `InterviewBankView`**

`SwiftUp/Features/InterviewPrep/InterviewBankView.swift`:
```swift
import SwiftUI

struct InterviewBankView: View {
    @Environment(InterviewRepository.self) private var repo
    @State private var levelFilter = "All"
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    EyebrowLabel("Interview prep")
                    Spacer()
                    Text("Bookmarks · \(repo.questions.filter(\.bookmarked).count)")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                }

                Text("The question\nbank").font(Theme.Fonts.heading(32)).padding(.top, 8)
                Text("\(repo.questions.count) questions with model answers, talking points and the follow-ups they usually attract.")
                    .font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 12)

                TextField("Search the bank", text: $searchText)
                    .padding(.horizontal, 10).padding(.vertical, 10)
                    .background(Theme.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    .padding(.top, 18)

                SegmentedPicker(options: ["All", "Junior", "Mid", "Senior"], selection: $levelFilter)
                    .padding(.top, 12)

                VStack(spacing: 0) {
                    ForEach(Array(repo.categories.enumerated()), id: \.element.id) { index, category in
                        NavigationLink {
                            if let first = repo.firstQuestion(in: category.name) {
                                InterviewQuestionDetailView(question: first)
                            }
                        } label: {
                            RuledRow(showBottomRule: index == repo.categories.count - 1, minHeight: 56) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.name).font(Theme.Fonts.heading(16.5))
                                    Text("\(category.reviewedCount) of \(category.totalCount) reviewed")
                                        .font(.system(size: 12.5)).foregroundStyle(Theme.Colors.neutral700)
                                }
                                Spacer()
                                ThinProgressBar(
                                    fraction: Double(category.reviewedCount) / Double(max(1, category.totalCount)),
                                    fillColor: category.reviewedCount == 0 ? Theme.Colors.neutral200 : Theme.Colors.accent
                                )
                                .frame(width: 64)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack { InterviewBankView() }
        .environment(InterviewRepository())
}
```

- [ ] **Step 2: `InterviewQuestionDetailView`**

`SwiftUp/Features/InterviewPrep/InterviewQuestionDetailView.swift`:
```swift
import SwiftUI

struct InterviewQuestionDetailView: View {
    @Environment(InterviewRepository.self) private var repo
    @State var question: InterviewQuestion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("← \(question.category)").font(Theme.Fonts.body(15)).foregroundStyle(Theme.Colors.accent700)
                    Spacer()
                    Text(question.bookmarked ? "★ Bookmarked" : "☆ Bookmark")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.accent700)
                }

                HStack(spacing: 8) {
                    Text(question.difficulty)
                        .font(.system(size: 11))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.Colors.accent100).foregroundStyle(Theme.Colors.accent800)
                    EyebrowLabel("Question \(question.indexInCategory) of \(question.totalInCategory)")
                }
                .padding(.top, 12)

                Text(question.prompt).font(Theme.Fonts.heading(27)).padding(.top, 14)

                EyebrowLabel("Model answer", color: Theme.Colors.accent700).padding(.top, 24)
                Text(question.modelAnswer).font(Theme.Fonts.body(15)).padding(.top, 10)

                EyebrowLabel("Talking points").padding(.top, 22)
                VStack(spacing: 0) {
                    ForEach(Array(question.talkingPoints.enumerated()), id: \.offset) { index, point in
                        RuledRow(showBottomRule: index == question.talkingPoints.count - 1, minHeight: 0) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.accent700)
                            Text(point).font(Theme.Fonts.body(14))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 10)

                EyebrowLabel("Follow-ups they ask next").padding(.top, 22)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(question.followUps, id: \.self) { followUp in
                        Text("— \(followUp)").font(Theme.Fonts.body(14)).foregroundStyle(Theme.Colors.neutral800)
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 12) {
                    Button("Mark reviewed") {}
                        .font(.system(size: 15.5))
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.Colors.divider))
                    Button {
                        if let next = repo.nextQuestion(after: question) {
                            question = next
                        }
                    } label: {
                        Text("Next question")
                            .font(.system(size: 15.5))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                    }
                    .background(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.bg)
                }
                .padding(.top, 26)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }
}

#Preview {
    NavigationStack {
        InterviewQuestionDetailView(question: InterviewRepository().questions[0])
    }
    .environment(InterviewRepository())
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SwiftUp/Features/InterviewPrep
git commit -m "Add interview bank and question detail views

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 20: LeaderboardView (canvas 7c)

**Files:**
- Create: `SwiftUp/Features/Leaderboard/LeaderboardView.swift`

**Interfaces:**
- Consumes: `LeaderboardRepository` (Task 9), `SegmentedPicker`
- Produces: `LeaderboardView()` — the Ranks tab's `NavigationStack` root, consumed by Task 21.

- [ ] **Step 1: Implement**

`SwiftUp/Features/Leaderboard/LeaderboardView.swift`:
```swift
import SwiftUI

struct LeaderboardView: View {
    @Environment(LeaderboardRepository.self) private var repo
    @State private var board = "Friends"
    @State private var span = "Week"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RuledMasthead(left: "Week 36", right: "Closes Sunday 24:00")

                Text("Standings").font(Theme.Fonts.heading(32)).padding(.top, 22)

                HStack(spacing: 10) {
                    SegmentedPicker(options: ["Friends", "Global"], selection: $board)
                    SegmentedPicker(options: ["Week", "All time"], selection: $span)
                }
                .padding(.top, 16)

                VStack(spacing: 0) {
                    ForEach(repo.entries) { entry in
                        entryRow(entry)
                    }
                }
                .padding(.top, 24)

                Text("Scored on xp earned this week only — 15 per correct answer, 25 for a perfect five, nothing for streak length.")
                    .font(Theme.Fonts.body(13)).foregroundStyle(Theme.Colors.neutral800)
                    .padding(.top, 18)

                if let currentUser = repo.entries.first(where: \.isCurrentUser),
                   let secondPlace = repo.entries.first(where: { $0.rank == currentUser.rank - 1 }) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("\(secondPlace.xp - currentUser.xp) xp")
                            Text("behind second place").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            EyebrowLabel("Top 4%")
                            Text("globally this week").font(.system(size: 13)).foregroundStyle(Theme.Colors.neutral800)
                        }
                    }
                    .padding(.top, 22)
                    .padding(.top, 14)
                    .overlay(Rectangle().fill(Theme.Colors.text).frame(height: 1), alignment: .top)
                }

                Text("Listed because leaderboards are on in settings. Turn them off and you disappear from everyone else's board too.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.Colors.neutral700)
                    .padding(.top, 16)

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Theme.Colors.bg)
    }

    @ViewBuilder
    private func entryRow(_ entry: LeaderboardEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(entry.rank)")
                .font(Theme.Fonts.heading(entry.isCurrentUser ? 17 : 15))
                .foregroundStyle(entry.isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.text)
                .frame(width: 26, alignment: .leading)
            Text(entry.name)
                .font(entry.isCurrentUser ? Theme.Fonts.heading(16) : Theme.Fonts.body(15))
            Spacer()
            EyebrowLabel("L\(entry.level)", color: entry.isCurrentUser ? Theme.Colors.accent700 : Theme.Colors.neutral700)
            Text("\(entry.xp)")
                .font(Theme.Fonts.heading(entry.isCurrentUser ? 18 : 15))
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.vertical, entry.isCurrentUser ? 14 : 11)
        .padding(.horizontal, entry.isCurrentUser ? 10 : 0)
        .background(entry.isCurrentUser ? Theme.Colors.accent100 : Color.clear)
        .overlay(alignment: .leading) {
            if entry.isCurrentUser {
                Rectangle().fill(Theme.Colors.accent).frame(width: 3)
            }
        }
        .overlay(Rectangle().fill(Theme.Colors.divider).frame(height: 1), alignment: .top)
    }
}

#Preview {
    NavigationStack { LeaderboardView() }
        .environment(LeaderboardRepository())
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add SwiftUp/Features/Leaderboard/LeaderboardView.swift
git commit -m "Add Leaderboard view

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 21: MainTabView, RootView, final app wiring

**Files:**
- Create: `SwiftUp/App/MainTabView.swift`
- Create: `SwiftUp/App/RootView.swift`
- Modify: `SwiftUp/App/SwiftUpApp.swift`
- Delete: `SwiftUp/App/ContentView.swift` (superseded by `RootView`)

**Interfaces:**
- Consumes: `OnboardingFlowView` (Task 11), `TodayFlowView` (Task 14), `InterviewBankView` (Task 19), `LeaderboardView` (Task 20), `ProfileHomeView` (Task 15), `CustomTabBar`/`AppTab` (Task 6), all four repositories (Task 9)
- Produces: the fully wired app — this is the final integration task.

- [ ] **Step 1: `MainTabView`**

`SwiftUp/App/MainTabView.swift`:
```swift
import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .today:
                    TodayFlowView()
                case .prep:
                    NavigationStack { InterviewBankView() }
                case .ranks:
                    NavigationStack { LeaderboardView() }
                case .record:
                    NavigationStack { ProfileHomeView() }
                }
            }
            CustomTabBar(selection: $selectedTab)
        }
    }
}

#Preview {
    MainTabView()
        .environment(QuestionRepository())
        .environment(ProfileRepository())
        .environment(InterviewRepository())
        .environment(LeaderboardRepository())
}
```

- [ ] **Step 2: `RootView`**

`SwiftUp/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let questionRepository = QuestionRepository()
    private let profileRepository = ProfileRepository()
    private let interviewRepository = InterviewRepository()
    private let leaderboardRepository = LeaderboardRepository()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlowView(onComplete: { hasCompletedOnboarding = true })
            }
        }
        .environment(questionRepository)
        .environment(profileRepository)
        .environment(interviewRepository)
        .environment(leaderboardRepository)
    }
}

#Preview {
    RootView()
}
```

- [ ] **Step 3: Wire the app entry point**

`SwiftUp/App/SwiftUpApp.swift`:
```swift
import SwiftUI

@main
struct SwiftUpApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 4: Remove the now-unused placeholder**

Run: `rm SwiftUp/App/ContentView.swift`

- [ ] **Step 5: Regenerate, build, and run the full test suite**

Run: `xcodegen generate && xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'generic/platform=iOS Simulator' build`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Wire MainTabView, RootView, and onboarding gate into the app entry point

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```

---

## Task 22: Manual verification pass

**Files:** none (verification only)

**Interfaces:** none — this task consumes the whole app and produces no new code.

- [ ] **Step 1: Boot a simulator and run the app**

Run: `xcrun simctl list devices available | grep iPhone` to find an available device name, then:
```bash
xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=<device>' build
xcrun simctl boot "<device>" 2>/dev/null || true
open -a Simulator
xcrun simctl install "<device>" $(xcodebuild -project SwiftUp.xcodeproj -scheme SwiftUp -destination 'platform=iOS Simulator,name=<device>' -showBuildSettings | awk -F'= ' '/CODESIGNING_FOLDER_PATH/ {print $2; exit}')
xcrun simctl launch "<device>" com.swiftup.dailyquiz
```

- [ ] **Step 2: Click through the full flow and confirm against the canvas**

- Onboarding: Welcome (5a) → Skill assessment (5b) → Topic interests (5c) → lands on Today tab
- Today: entry (1a) → "Begin today's five" → 5 questions cycling through MCQ/true-false/spot-the-bug/fill-in-blank formats with correct/incorrect feedback → summary (1f) → "Done" returns to entry
- Prep: category list (7a) → tap a category → question detail (7b) → "Next question" advances
- Ranks: leaderboard (7c) renders 8 entries with "You" highlighted at rank 3
- Record: profile home (3a) → "All milestones →" (3b), "All 12 levels →" (3c), badge count link (2c), Settings toolbar button (4a) → Notifications (4b), Support link (6a)
- Confirm force-quitting and relaunching the app skips onboarding (AppStorage persisted)

- [ ] **Step 3: Fix any visual or navigation issues found, per screen, referring back to the corresponding canvas screen ID and this plan's task**

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "Fix issues found during manual verification pass

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_013E5q55KoVehPSvKh3oo6bE"
```
(Skip this commit if step 3 found nothing to fix.)
