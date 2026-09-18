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


def round5(n: float) -> int:
    return int(round(n / 5.0) * 5)


def build_stages(track_id: str, title: str, multiplier: float) -> list[dict]:
    if track_id == "junior-02":
        stages = JUNIOR_02_STAGES
    else:
        lesson_cost = round5(50 * multiplier)
        assessment_cost = round5(400 * multiplier)
        stages = [
            {"title": f"{title} — lesson {n} of 6", "xpCost": lesson_cost, "kind": "lesson"}
            for n in range(1, 7)
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
