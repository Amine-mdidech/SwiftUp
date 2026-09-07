# SwiftUp — iOS Dev Daily Quiz & Interview Prep App

## 1. Overview

**Working name:** SwiftUp (placeholder — rename as desired)

**Purpose:** A native iOS app that helps iOS developers and engineers keep their skills sharp through short daily gamified quizzes, and prepares them for technical interviews with curated Q&A and hands-on live coding sessions.

**Platform:** iOS (SwiftUI, native app)

**Target users:**
- Junior-to-senior iOS developers who want to stay sharp on Swift/SwiftUI/UIKit/iOS SDK knowledge
- Engineers actively preparing for iOS technical interviews
- Bootcamp grads / self-taught devs building interview confidence

---

## 2. Core Feature Areas

### 2.1 Daily Quiz (Habit Loop)
- **5 questions per day**, refreshed every 24 hours (fixed daily reset time, e.g. midnight local time)
- Question formats: multiple choice, true/false, "spot the bug" code snippet, fill-in-the-blank code
- Topics pulled from a tagged question bank: Swift language, SwiftUI, UIKit, Concurrency (async/await, GCD), Memory management (ARC/retain cycles), Architecture (MVVM/MV, Combine), Networking, Core Data/SwiftData, Testing, Xcode/tooling, App lifecycle
- Difficulty auto-adapts over time based on user performance (adaptive difficulty engine, v2 candidate — v1 can start with a fixed difficulty curve)
- Immediate feedback after each question: correct/incorrect + short explanation + optional "learn more" link/snippet
- End-of-quiz summary screen: score, XP earned, streak status, topics to review
- Push notification reminder if the daily quiz hasn't been completed (user-configurable time)

### 2.2 Gamification System
- **XP & Levels:** XP awarded per correct answer, bonus XP for perfect 5/5 days; level progression with titles (e.g. "Swift Novice" → "SwiftUI Architect")
- **Streaks:** Daily streak counter with streak-freeze/grace mechanic (e.g. 1 free miss per week) to reduce churn guilt
- **Badges/Achievements:** Unlockable badges for milestones (7-day streak, 30-day streak, topic mastery, perfect week, first interview session completed, etc.)
- **Leaderboards:** Global and friends-based leaderboards (weekly + all-time), ranked by XP; optional opt-out for privacy
- **Profile/Stats dashboard:** Streak history, accuracy by topic (radar/bar chart), total questions answered, badges earned

### 2.3 Advanced Interview Prep
- **Question Bank (FAQ mode):** Curated frequently-asked iOS interview questions, organized by category (Swift fundamentals, system design for iOS, architecture patterns, performance/debugging, behavioral) and difficulty (Junior/Mid/Senior)
- Each question includes: model answer, key talking points, common follow-up questions, related resources
- Bookmark/favorite questions for later review
- Progress tracking per category (e.g. "12/40 Architecture questions reviewed")

- **Live Coding Interview Sessions:**
  - In-app code editor supporting Swift syntax highlighting
  - **Live code execution** within the app (sandboxed Swift runtime/interpreter) so users can write and run solutions to coding prompts
  - Curated coding challenges typical of iOS interviews (data structures/algorithms in Swift, practical iOS tasks e.g. "implement a simple debounce", "detect a retain cycle", "build a basic Codable parser")
  - Timer mode to simulate real interview pressure (optional, toggleable)
  - Post-attempt: reveal reference solution + complexity/approach notes; self-assessment rating (how confident did you feel?)
  - Session history so users can revisit past attempts

---

## 3. Supporting Features

- **Onboarding:** Skill self-assessment (junior/mid/senior) + topic interests to personalize initial question difficulty/mix
- **Authentication:** Sign in with Apple (primary), email/password fallback
- **Notifications:** Daily quiz reminder, streak-at-risk alert, new content alerts
- **Offline support:** Daily quiz + FAQ content cacheable for offline use; code execution requires connectivity (or bundled sandboxed runtime if feasible)
- **Settings:** Notification preferences, leaderboard privacy toggle, difficulty override, dark/light mode, account management

---

## 4. Non-Functional Requirements

- Native SwiftUI app, targeting current + previous major iOS version
- Smooth, snappy micro-interactions for gamification moments (XP gain, streak increment, badge unlock) — these are key emotional/reward moments and deserve polished animation
- Content must be easily updatable without app releases (backend-driven question bank, e.g. via a lightweight CMS or remote JSON/Firestore-style backend)
- Analytics on quiz completion rates, drop-off points, and topic weak spots (to improve content over time)
- Accessibility: Dynamic Type support, VoiceOver labels on interactive elements

---

## 5. Out of Scope (v1)

- Android/web versions
- Real-time multiplayer/head-to-head quiz battles (candidate for v2)
- AI-generated personalized questions (candidate for v2 — v1 uses curated static bank)
- Video-based mock interviews with real humans

---

## 6. Next Steps

1. Use this document as input to **Claude Design** to define the visual identity, key screens (Daily Quiz, Interview Prep, Code Editor, Profile/Leaderboard), and design system (colors, typography, gamification visual language).
2. Once look & feel is approved, hand off the design + this requirements doc to **Claude Code** to scaffold the SwiftUI app and implement features incrementally, starting with: Onboarding → Daily Quiz → Gamification layer → Interview FAQ bank → Live Coding Editor.
