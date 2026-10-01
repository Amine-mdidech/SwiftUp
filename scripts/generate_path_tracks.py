#!/usr/bin/env python3
"""Generates scripts/path-tracks.json from the table below — see design doc
docs/superpowers/specs/2026-09-18-path-foundation-design.md §5 for why this
is formula-generated placeholder content rather than hand-authored data.

Run: python3 scripts/generate_path_tracks.py
Re-run any time the GRADES table below changes; it overwrites
scripts/path-tracks.json deterministically (same inputs -> same output).
"""
import json
from pathlib import Path

GRADES = [
    ("Junior", 1.0, ["Swift fundamentals", "Object-oriented Swift", "Architecture basics", "Memory & ARC", "SwiftUI state"]),
    ("Mid", 1.5, ["Concurrency", "Testing", "Networking", "Persistence", "Performance", "App lifecycle"]),
    ("Senior", 2.0, ["System design", "Module boundaries", "Migration strategy", "Code review", "Mentoring"]),
    ("Distinguished", 2.5, ["Platform strategy", "Cross-team architecture", "Technical direction", "Engineering culture"]),
]

# Hand-authored exception, taken verbatim from the design (junior-02).
JUNIOR_02_STAGES = [
    {"title": "Classes, structs and value semantics", "xpCost": 45, "kind": "lesson"},
    {"title": "Initialisers and inheritance", "xpCost": 45, "kind": "lesson"},
    {"title": "Protocols as interfaces", "xpCost": 45, "kind": "lesson"},
    {"title": "Protocol-oriented design", "xpCost": 200, "kind": "lesson"},
    {"title": "Generics and associated types", "xpCost": 200, "kind": "lesson"},
    {"title": "Composition over inheritance", "xpCost": 200, "kind": "lesson"},
    {"title": "Error handling and typed throws", "xpCost": 200, "kind": "lesson"},
    {"title": "Track assessment", "xpCost": 400, "kind": "assessment"},
]


# Per-lesson titles for every track except junior-02 (which has its own table above),
# each summarising that lesson's slides in path-content.json.
LESSON_TITLES = {
    "junior-01": [
        "Constants, variables and type inference",
        "Optionals and unwrapping",
        "Control flow and pattern matching",
        "Functions and closures",
        "Collections and value semantics",
        "Error handling with throws and Result",
    ],
    "junior-03": [
        "MVC and MVVM",
        "Separation of concerns and layering",
        "Dependency injection",
        "View models and one-way data flow",
        "Navigation patterns",
        "Organizing a project by feature",
    ],
    "junior-04": [
        "How ARC counts references",
        "Strong, weak and unowned",
        "Closures and retain cycles",
        "Delegates and weak references",
        "Value types and memory",
        "Finding leaks with Instruments",
    ],
    "junior-05": [
        "@State and local view state",
        "@Binding and two-way data flow",
        "@Observable and @Bindable",
        "The SwiftUI environment",
        "View identity",
        "What triggers a re-render",
    ],
    "mid-01": [
        "async/await basics",
        "Structured concurrency and async let",
        "Actors and isolation",
        "Task and TaskGroup",
        "@MainActor and UI work",
        "Sendable and strict concurrency",
    ],
    "mid-02": [
        "XCTest and Swift Testing",
        "Arrange, act, assert",
        "Test doubles and dependency injection",
        "Testing async code",
        "UI tests with XCUITest",
        "Code coverage and what to test",
    ],
    "mid-03": [
        "URLSession and URLRequest",
        "Decoding JSON with Codable",
        "Async networking",
        "Error handling, retries and backoff",
        "Authentication and token refresh",
        "Caching network responses",
    ],
    "mid-04": [
        "UserDefaults and @AppStorage",
        "Saving Codable files to disk",
        "Core Data fundamentals",
        "SwiftData",
        "Keychain for sensitive data",
        "Choosing a persistence layer",
    ],
    "mid-05": [
        "Profiling with Instruments",
        "Keeping the main thread free",
        "SwiftUI rendering performance",
        "Image loading and downsampling",
        "Launch time",
        "Memory leaks and retain cycles",
    ],
    "mid-06": [
        "App, Scene and scene phases",
        "Background tasks",
        "State restoration",
        "Push and local notifications",
        "Suspension and termination",
        "Multiple scenes",
    ],
    "senior-01": [
        "Caching, pagination and offline-first",
        "Designing API contracts",
        "Data sync and conflict resolution",
        "Designing for testability",
        "Evaluating third-party dependencies",
        "Approaching a system design question",
    ],
    "senior-02": [
        "Why modularize",
        "Modularizing with Swift Package Manager",
        "Designing a module's public API",
        "Avoiding circular dependencies",
        "Dependency inversion across modules",
        "Versioning and deprecating internal APIs",
    ],
    "senior-03": [
        "Planning a migration",
        "The strangler-fig pattern",
        "Feature flags and gradual rollout",
        "Running old and new code paths",
        "Managing rollout risk and rollback",
        "Communicating a migration",
    ],
    "senior-04": [
        "What to look for in a review",
        "Writing actionable review comments",
        "Architecture issues vs nitpicks",
        "When to block a change",
        "Reviewing without full context",
        "Code review as teaching",
    ],
    "senior-05": [
        "Onboarding new engineers",
        "Giving effective feedback",
        "Pair programming",
        "Delegating meaningful work",
        "Knowing when to step in",
        "Growing engineers toward independence",
    ],
    "distinguished-01": [
        "Build vs buy",
        "Building a technical roadmap",
        "Internal platforms as products",
        "When to adopt new frameworks",
        "Managing technical debt",
        "Aligning platform work with business strategy",
    ],
    "distinguished-02": [
        "Designing boundaries across teams",
        "Conway's Law",
        "Avoiding the distributed monolith",
        "Centralization vs team autonomy",
        "Driving alignment without authority",
        "Architecture decision records",
    ],
    "distinguished-03": [
        "Setting a technical vision",
        "Making and managing technical bets",
        "Balancing innovation and stability",
        "Explaining technical decisions to executives",
        "Sunsetting systems",
        "Measuring technical outcomes",
    ],
    "distinguished-04": [
        "Building a culture of excellence",
        "Scaling engineering practices",
        "Psychological safety and quality",
        "Blameless postmortems",
        "Hiring and leveling staff-plus engineers",
        "Culture through reorgs",
    ],
}


def round5(n: float) -> int:
    return int(round(n / 5.0) * 5)


def build_stages(track_id: str, title: str, multiplier: float) -> list[dict]:
    if track_id == "junior-02":
        stages = JUNIOR_02_STAGES
    else:
        lesson_cost = round5(50 * multiplier)
        assessment_cost = round5(400 * multiplier)
        stages = [
            {"title": lesson_title, "xpCost": lesson_cost, "kind": "lesson"}
            for lesson_title in LESSON_TITLES[track_id]
        ] + [{"title": "Track assessment", "xpCost": assessment_cost, "kind": "assessment"}]
    return [
        {"id": f"{track_id}-s{i:02d}", "order": i, "title": s["title"], "xpCost": s["xpCost"], "kind": s["kind"]}
        for i, s in enumerate(stages, start=1)
    ]


def main() -> None:
    tracks = []
    for grade, multiplier, titles in GRADES:
        grade_slug = grade.lower()
        for order, title in enumerate(titles, start=1):
            track_id = f"{grade_slug}-{order:02d}"
            tracks.append({
                "id": track_id,
                "grade": grade,
                "order": order,
                "title": title,
                "stages": build_stages(track_id, title, multiplier),
            })
    content = json.dumps(tracks, indent=2, ensure_ascii=False) + "\n"
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    out_paths = [
        script_dir / "path-tracks.json",
        repo_root / "SwiftUp" / "Resources" / "path_tracks.json",
        repo_root / "SwiftUpTests" / "Fixtures" / "path_tracks.json",
    ]
    for out_path in out_paths:
        out_path.write_text(content)
    print(f"Wrote {len(tracks)} tracks to {len(out_paths)} files: " + ", ".join(str(p) for p in out_paths))


if __name__ == "__main__":
    main()
