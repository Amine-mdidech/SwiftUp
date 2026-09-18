#!/usr/bin/env python3
"""Generates scripts/path-content.json (placeholder slides + quiz content for every stage,
plus one regrade quiz per promotable grade) from scripts/path-tracks.json — see design doc
docs/superpowers/specs/2026-09-18-path-gameplay-design.md §2 for why this is formula-generated
placeholder content rather than hand-authored material.

Run: python3 scripts/generate_path_content.py
Re-run any time scripts/path-tracks.json changes; it overwrites scripts/path-content.json
deterministically (same inputs -> same output).
"""
import json
import random
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
TRACKS_PATH = SCRIPT_DIR / "path-tracks.json"

OPTION_LABELS = ["Correct answer", "Incorrect answer 1", "Incorrect answer 2", "Incorrect answer 3"]
OPTION_IDS = ["A", "B", "C", "D"]


def build_quiz_question(stage_id: str, question_index: int, title: str) -> dict:
    # Deterministically seeded so re-running the script produces byte-identical output.
    rng = random.Random(f"{stage_id}-q{question_index}")
    labels = OPTION_LABELS[:]
    rng.shuffle(labels)
    options = [{"id": OPTION_IDS[i], "text": labels[i]} for i in range(4)]
    correct_option_id = next(o["id"] for o in options if o["text"] == "Correct answer")
    return {
        "id": f"{stage_id}-q{question_index:02d}",
        "prompt": f"Placeholder question {question_index} for \"{title}\".",
        "options": options,
        "correctOptionID": correct_option_id,
    }


def build_slide(stage_id: str, slide_index: int, stage_title: str, track_title: str) -> dict:
    has_example = slide_index in (2, 4)
    return {
        "id": f"{stage_id}-slide{slide_index:02d}",
        "order": slide_index,
        "title": f"{stage_title} — part {slide_index} of 4",
        "body": f"This part of {stage_title} continues the {track_title} track.",
        "example": f"// placeholder example for {stage_title}, part {slide_index}" if has_example else None,
    }


def build_stage_content(stage: dict, track_title: str) -> dict:
    stage_id = stage["id"]
    if stage["kind"] == "assessment":
        quiz = [build_quiz_question(stage_id, i, stage["title"]) for i in range(1, 11)]
        return {"stageID": stage_id, "slides": [], "quiz": quiz}
    slides = [build_slide(stage_id, i, stage["title"], track_title) for i in range(1, 5)]
    quiz = [build_quiz_question(stage_id, i, stage["title"]) for i in range(1, 6)]
    return {"stageID": stage_id, "slides": slides, "quiz": quiz}


def build_regrade_quiz(grade: str) -> dict:
    questions = [build_quiz_question(f"regrade-{grade.lower()}", i, f"{grade} regrade") for i in range(1, 11)]
    return {"grade": grade, "questions": questions}


def main() -> None:
    tracks = json.loads(TRACKS_PATH.read_text())

    stage_content = []
    for track in tracks:
        for stage in track["stages"]:
            stage_content.append(build_stage_content(stage, track["title"]))

    # Distinguished has no `.next` grade (SkillLevel.swift) — there is nothing to regrade into,
    # so it gets no regrade quiz.
    grades_with_next = ["Junior", "Mid", "Senior"]
    regrade_quizzes = [build_regrade_quiz(grade) for grade in grades_with_next]

    content = json.dumps(
        {"stageContent": stage_content, "regradeQuizzes": regrade_quizzes},
        indent=2, ensure_ascii=False,
    ) + "\n"

    repo_root = SCRIPT_DIR.parent
    out_paths = [
        SCRIPT_DIR / "path-content.json",
        repo_root / "SwiftUp" / "Resources" / "path_content.json",
        repo_root / "SwiftUpTests" / "Fixtures" / "path_content.json",
    ]
    for out_path in out_paths:
        out_path.write_text(content)
    print(
        f"Wrote {len(stage_content)} stage-content docs and {len(regrade_quizzes)} regrade "
        f"quizzes to {len(out_paths)} files: " + ", ".join(str(p) for p in out_paths)
    )


if __name__ == "__main__":
    main()
