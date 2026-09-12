# Interview Prep — Flashcard Session Refactor — Design

Source design: Claude Design project "Design prioritization inquiry" (`SwiftUp Daily Quiz.dc.html`), turn 11 ("Interview prep, refactored — flashcards then review", options `11a`-`11d`), which explicitly replaces turn `7b`'s flat question-detail flow.

## 1. Goal

Today, tapping an Interview Prep category (`InterviewBankView` → `7a`-shaped screen) opens a flat article view (`InterviewQuestionDetailView`, the old `7b` shape) with a "Mark reviewed" button that is a no-op and a static `reviewedCount` unrelated to any real state.

This pass replaces that with the new design's flow: tapping a category starts a fixed-size flashcard session (question front → flip to talking points → self-rate Missed/Shaky/Nailed), ends on a session summary, and lets the user immediately review the cards they rated Missed/Shaky in full-article form. Self-ratings are persisted per user to Firestore with a simple due-date schedule (Nailed → 4 days, Shaky/Missed → tomorrow), and bookmarking — currently static, unwired content data — becomes a real per-user toggle. `InterviewBankView`'s "N of M" count becomes real, derived from the user's stored review state instead of static copy.

**Out of scope** (confirmed with user):
- A cross-category "due today" review queue. The source design itself lists this as a "try next" idea, not something turn 11 builds — we store `dueDate` now so it's a clean follow-up, but no screen surfaces it yet.
- Wiring the (already non-functional) search field on the bank screen.
- Any XP/achievement hook for completing a flashcard session — the source design has no XP moment here.

## 2. Firestore schema & rules

Two new per-user subcollections, both mirroring the existing `users/{uid}/dailyCompletions/{date}` shape and rule:

```
users/{uid}/flashcardReviews/{questionId} = {
  rating: "missed" | "shaky" | "nailed",
  dueDate: "yyyy-MM-dd",       // DailyEdition.todayKey format
  lastReviewedAt: Timestamp,   // FieldValue.serverTimestamp()
  reviewCount: Int
}

users/{uid}/bookmarks/{questionId} = {
  bookmarked: true
}
```

`bookmarks` docs are deleted on un-bookmark rather than written `false` — keeps the subcollection to exactly the user's current bookmark set, and "does this doc exist" is what `InterviewRepository` actually queries for.

**`firestore.rules` additions** (inside the existing `match /users/{uid}` block, alongside `dailyCompletions`):

```
match /flashcardReviews/{questionId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
match /bookmarks/{questionId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
```

## 3. Model changes

**`InterviewQuestion`** drops the static `bookmarked` field — it was content data with no real per-user meaning once bookmarking is wired up:

```swift
struct InterviewQuestion: Codable, Identifiable {
    let id: String
    let category: String
    let difficulty: String
    let prompt: String
    let modelAnswer: String
    let talkingPoints: [String]
    let followUps: [String]
}
```

Cascades to remove the `bookmarked` key from `scripts/interview-bank.json`, `SwiftUp/Resources/interview_bank.json`, `SwiftUpTests/Fixtures/interview_bank.json`, and the field validation in `scripts/seed_interview_bank.py`. `InterviewCategoryContent` is unchanged.

**New `FlashcardRating`**:

```swift
enum FlashcardRating: String, Codable {
    case missed, shaky, nailed
}
```

**New `FlashcardReviewState`** — one user's stored state for one question, decoded from `flashcardReviews/{questionId}`:

```swift
struct FlashcardReviewState: Codable {
    let rating: FlashcardRating
    let dueDate: String
    let reviewCount: Int
}
```
(`lastReviewedAt` is written but not read back into the app today — omitted from the decode target the same way other write-only bookkeeping fields are elsewhere in this codebase.)

## 4. `InterviewRepository` changes

Content loading (`load()`, ungated, unchanged) and user-state loading are separate entry points, since content isn't gated on `uid` but review/bookmark state is — matching how `QuestionRepository.load()` (content) and `ProfileRepository.load(for:)` (user state) are already two different repositories' worth of separation, just within one repository here since both concern the same feature.

```swift
@Observable
final class InterviewRepository {
    private(set) var categories: [InterviewCategoryContent] = []
    private(set) var isLoading = false
    private(set) var reviewState: [String: FlashcardReviewState] = [:]   // keyed by question id
    private(set) var bookmarkedIDs: Set<String> = []

    func load() async { ... }                              // unchanged

    /// Fetches this user's flashcard review state and bookmarks. Non-blocking on failure — same
    /// shape as ProfileRepository.load(for:): keeps whatever state is already held rather than
    /// flashing to empty on a transient error.
    func loadUserState(for uid: String) async {
        async let reviewDocs = Firestore.firestore()
            .collection("users").document(uid).collection("flashcardReviews").getDocuments()
        async let bookmarkDocs = Firestore.firestore()
            .collection("users").document(uid).collection("bookmarks").getDocuments()
        do {
            let (reviews, bookmarks) = try await (reviewDocs, bookmarkDocs)
            reviewState = Dictionary(uniqueKeysWithValues: reviews.documents.compactMap { doc in
                (try? doc.data(as: FlashcardReviewState.self)).map { (doc.documentID, $0) }
            })
            bookmarkedIDs = Set(bookmarks.documents.map(\.documentID))
        } catch {
            // Non-blocking — see doc comment above.
        }
    }

    /// Persists a finished flashcard session's ratings in one batch, then reflects the result
    /// locally immediately (no re-fetch), same pattern as ProfileRepository.recordCompletion.
    func recordSession(_ ratings: [String: FlashcardRating], for uid: String) async {
        guard !ratings.isEmpty else { return }
        let batch = Firestore.firestore().batch()
        let userRef = Firestore.firestore().collection("users").document(uid)
        let today = Date()
        for (questionID, rating) in ratings {
            let daysUntilDue = rating == .nailed ? 4 : 1
            let dueDate = DailyEdition.todayKey(for: Calendar.current.date(byAdding: .day, value: daysUntilDue, to: today)!)
            let ref = userRef.collection("flashcardReviews").document(questionID)
            batch.setData([
                "rating": rating.rawValue,
                "dueDate": dueDate,
                "lastReviewedAt": FieldValue.serverTimestamp(),
                "reviewCount": FieldValue.increment(Int64(1)),
            ], forDocument: ref, merge: true)
        }
        do {
            try await batch.commit()
            for (questionID, rating) in ratings {
                let daysUntilDue = rating == .nailed ? 4 : 1
                let dueDate = DailyEdition.todayKey(for: Calendar.current.date(byAdding: .day, value: daysUntilDue, to: today)!)
                let previousCount = reviewState[questionID]?.reviewCount ?? 0
                reviewState[questionID] = FlashcardReviewState(rating: rating, dueDate: dueDate, reviewCount: previousCount + 1)
            }
        } catch {
            // Non-blocking — a failed write is invisible to the user; worst case this session's
            // ratings are lost and the next session's batch recomputes from whatever's stored.
        }
    }

    /// Creates or deletes `bookmarks/{questionId}` and updates local state immediately (optimistic —
    /// matches the button responding instantly with no loading state, consistent with the rest of
    /// this screen's interactions).
    func toggleBookmark(_ question: InterviewQuestion, for uid: String) async {
        let wasBookmarked = bookmarkedIDs.contains(question.id)
        if wasBookmarked { bookmarkedIDs.remove(question.id) } else { bookmarkedIDs.insert(question.id) }
        let ref = Firestore.firestore().collection("users").document(uid).collection("bookmarks").document(question.id)
        do {
            if wasBookmarked {
                try await ref.delete()
            } else {
                try await ref.setData(["bookmarked": true])
            }
        } catch {
            // Revert the optimistic update on failure.
            if wasBookmarked { bookmarkedIDs.insert(question.id) } else { bookmarkedIDs.remove(question.id) }
        }
    }

    func isBookmarked(_ question: InterviewQuestion) -> Bool { bookmarkedIDs.contains(question.id) }

    /// Whether this question has ever been rated — what the bank screen's "N of M" count means now.
    func hasBeenReviewed(_ question: InterviewQuestion) -> Bool { reviewState[question.id] != nil }
}
```

`firstQuestion(in:level:)`, `nextQuestion(after:)`, `position(of:)` are unchanged — they walk content, not review state.

## 5. `FlashcardSession` — new, ephemeral session state

Not a repository: created fresh each time a session starts, holds no Firestore connection of its own, and is discarded when its owning view goes away. Deliberately separate from `InterviewRepository` (which owns durable content/state) so an abandoned session can't leak partial state into it.

```swift
@Observable
final class FlashcardSession {
    let category: String
    let deck: [InterviewQuestion]        // fixed at construction — see §7 for how the deck is built
    private(set) var currentIndex = 0
    private(set) var isFlipped = false
    private(set) var ratings: [String: FlashcardRating] = [:]   // questionId -> rating, in rating order

    init(category: String, deck: [InterviewQuestion]) {
        self.category = category
        self.deck = deck
    }

    var currentCard: InterviewQuestion? { deck.indices.contains(currentIndex) ? deck[currentIndex] : nil }
    var isComplete: Bool { currentIndex >= deck.count }
    var progress: [FlashcardRating?] {   // one entry per deck card, for the front's progress ticks
        deck.map { ratings[$0.id] }
    }

    func flip() { isFlipped = true }

    /// Records a rating for the current card and advances. No-op past the end of the deck.
    func rate(_ rating: FlashcardRating) {
        guard let card = currentCard else { return }
        ratings[card.id] = rating
        advance()
    }

    /// Advances without recording anything — the front's "Skip".
    func skip() { advance() }

    private func advance() {
        currentIndex += 1
        isFlipped = false
    }

    var nailedCount: Int { ratings.values.filter { $0 == .nailed }.count }
    var shakyCount: Int { ratings.values.filter { $0 == .shaky }.count }
    var missedCount: Int { ratings.values.filter { $0 == .missed }.count }

    /// Cards to review now, in the order the design shows them — missed before shaky, each in the
    /// order they were rated within the session (deck order, filtered).
    var cardsToReview: [InterviewQuestion] {
        deck.filter { ratings[$0.id] == .missed } + deck.filter { ratings[$0.id] == .shaky }
    }
}
```

## 6. View changes

All three views below need the signed-in user's id for their `for: uid` calls, via the same `@Environment(AuthRepository.self) private var authRepo` + `authRepo.currentUser?.uid` pattern already used in `TodayFlowView`, `ProfileHomeView`, `LeaderboardView`, etc. (`InterviewBankView` doesn't have this today since content loading isn't uid-gated — it gains the environment property along with `loadUserState`.) Every call below is guarded on `if let uid = authRepo.currentUser?.uid` and silently no-ops otherwise, same as those existing call sites.

**`InterviewBankView`** (`7a`, shell unchanged):
- `.task` gains `await repo.loadUserState(for: uid)` alongside the existing content `load()` (both fired via `async let` — independent fetches, no ordering dependency).
- Category row's count label becomes `"\(reviewedCount) of \(count) reviewed"` where `reviewedCount = category.questions(for: levelFilter).filter(repo.hasBeenReviewed).count` — the same computation the old static copy was faking, now real.
- Category row navigates to a new `FlashcardSessionView(category:, level:)` instead of `InterviewQuestionDetailView`.

**New `FlashcardSessionView`** (`11a`/`11b` combined into one view, not two pushed screens — the mockup's `11a`→`11b` anchor link is a prototyping artifact, not a literal navigation step; a real flip reads better as one screen's state flipping):
- Owns a `@State private var session: FlashcardSession`, built on `init` from `repo.firstQuestion`-style deck construction (§7).
- Renders the front (question, level tag, category eyebrow, progress ticks colored by `session.progress`, Skip / Flip buttons) when `!session.isFlipped`, and the back (talking points, Missed/Shaky/Nailed buttons) when `session.isFlipped`, cross-faded/flipped with `.animation`.
- Missed/Shaky/Nailed buttons call `session.rate(_:)`.
- When `session.isComplete` becomes true, pushes `SessionSummaryView(session:)` and — in the same moment — fires `await repo.recordSession(session.ratings, for: uid)` (fire-and-forget `Task`, not blocking the transition: the summary screen reads from `session` in memory, not from a re-fetch).

**New `SessionSummaryView`** (`11c`):
- Reads directly off the passed-in `FlashcardSession`: nailed count as the big `PlateNumeral`, "N shaky · N missed" subtitle, stacked `ThinProgressBar`-style bar (three segments — reuse `ThinProgressBar` three times at computed widths, or a small new three-segment variant if that's awkward with one bar).
- Review list = `session.cardsToReview`, each row linking to `InterviewQuestionDetailView(question:, reviewQueue:, indexInQueue:)`.
- "Back to bank" pops to root. "Review now" pushes into the first card of the review queue the same way a row tap does.

**`InterviewQuestionDetailView`** (adapted from `7b`/`11d`):
- Gains an optional review-queue context: `var reviewQueue: [InterviewQuestion]? = nil`, `var indexInQueue: Int = 0` — `nil` when reached some other way (there currently isn't another way post-refactor, but keeping it optional rather than required avoids a forced call-site everywhere and matches this view's existing `@State var question` mutation style for in-place navigation).
- When `reviewQueue` is set: shows the rating tag (`session`'s stored rating, not `question.difficulty`'s tag — the two are visually similar `.tag` pills, differently colored per §2's `tag-accent`/`tag-accent-2`), and its two buttons become:
  - **"Card again"** — re-writes this one question's review state at its existing rating (`repo.reviewState[question.id]?.rating`, which is always present here since the card came from `cardsToReview`) via `repo.recordSession([question.id: existingRating], for: uid)` — refreshes `dueDate` to tomorrow again without relabeling a `.missed` card as `.shaky`, since both map to the same +1-day offset (§4) — then advances (below).
  - **"Next review"** — advances `indexInQueue`; on the last card, pops back to the bank (root), matching "Review now" being a closed loop over exactly the session's weak cards rather than opening onto anything else.
- **"Mark reviewed"** is removed — reviewed-ness is now derived from `repo.hasBeenReviewed` (§4/§6), not a separate manual action; the old no-op button is gone rather than kept as decoration.
- Bookmark: `★ Bookmarked` / `☆ Bookmark` becomes a real `Button` calling `repo.toggleBookmark(question, for: uid)`, reading `repo.isBookmarked(question)` instead of a static field.

## 7. Deck construction (session start)

`FlashcardSessionView.init` builds the deck the same way `InterviewBankView`'s category row already resolves its target question — via `InterviewRepository`, not inline in the view:

```swift
/// First `deckSize` questions at `level` in `categoryName`, in that level's existing content
/// order (no shuffling — matches "Card 04/10" being a stable, resumable-feeling position, and
/// keeps a session deterministic for testing). Fewer than `deckSize` if the category has less.
func sessionDeck(in categoryName: String, level: String, deckSize: Int = 10) -> [InterviewQuestion] {
    guard let category = categories.first(where: { $0.name == categoryName }) else { return [] }
    return Array(category.questions(for: level).prefix(deckSize))
}
```
Added to `InterviewRepository` alongside `firstQuestion(in:level:)`. A category+level combo with zero questions can't be tapped into in the first place — `InterviewBankView`'s existing disabled-row behavior for `count == 0` already prevents that navigation.

## 8. Navigation flow

```
InterviewBankView (category list, level filter)
  → tap a non-empty category row
FlashcardSessionView (front ⇄ back flip, N cards)
  → last card rated/skipped
SessionSummaryView (nailed/shaky/missed breakdown)
  → "Review now" (or tap a row)          → "Back to bank"
InterviewQuestionDetailView (review loop,     → pop to InterviewBankView (root)
  "Card again" / "Next review")
  → "Next review" on the last queued card
  → pop to InterviewBankView (root)
```

## 9. Error handling

- `loadUserState(for:)` failure: keeps whatever `reviewState`/`bookmarkedIDs` is already held (empty on first load, stale-but-present on a later transient failure) — same non-blocking shape as `ProfileRepository.load(for:)`. The bank screen's "N of M reviewed" and bookmark stars just read as unreviewed/unbookmarked until the next successful load; nothing crashes or shows an error state.
- `recordSession`/`toggleBookmark` failure: non-blocking, `catch {}` (documented inline per call site) — the user is never blocked on the summary/detail screen behind a failed write. `toggleBookmark` additionally reverts its optimistic local update so the star doesn't lie about what's actually stored.
- A category+level combo with an empty deck can't start a session at all (§7) — not a new error class, same disabled-row handling `InterviewBankView` already has today.

## 10. Testing

- Unit tests (no Firestore, same style as `RepositoryTests.swift`'s existing interview coverage):
  - `FlashcardSession`: rating advances the index, records into `ratings`, `isComplete` flips at deck end; `skip()` advances without recording; `cardsToReview` orders missed-then-shaky in deck order; `nailedCount`/`shakyCount`/`missedCount` tally correctly.
  - `InterviewRepository.sessionDeck(in:level:deckSize:)`: returns `prefix(deckSize)`, and fewer when the category has less.
  - `InterviewRepository.hasBeenReviewed(_:)`: true only once `reviewState` has an entry for that question's id.
  - Due-date arithmetic (`recordSession`'s day-offset logic, factored out as a small pure helper e.g. `dueDate(for: FlashcardRating, from: Date) -> String` so it's testable without a batch/Firestore call): nailed → +4 days, shaky/missed → +1 day.
- Update `SwiftUpTests/Fixtures/interview_bank.json` to drop `bookmarked` (§3).
- Firestore reads/writes themselves aren't unit-testable in this project (no emulator, same limitation noted in the level-filtering spec) — verified by manual run-through: rate a full session, confirm `flashcardReviews` docs appear with the right `dueDate`, confirm bookmark toggle creates/deletes its doc, confirm a second load reflects both.

## 11. Open implementation decisions (flagged, not blocking)

- Exact flip animation/transition for `FlashcardSessionView` (3D flip vs. cross-fade) — implementation-time choice, not a design decision that changes behavior.
- Whether the three-segment session-summary bar reuses `ThinProgressBar` three times side-by-side or needs a small new component — implementation-time choice; no new design tokens are needed either way (the three colors are already `Theme.Colors.text`/`processYellow`/`accent2`, matching `11c`'s ink/yellow/magenta segments).
- `InterviewQuestionDetailView`'s `reviewQueue`/`indexInQueue` parameters could instead be modeled as a small dedicated `ReviewQueue` state object mirroring `FlashcardSession`'s shape — left as plain optional params for now since the queue is short-lived and one screen, revisit if a second review-queue-shaped feature appears.
