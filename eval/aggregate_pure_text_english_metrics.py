from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


PURE_TEXT_ENGLISH_TASKS = (
    "tasks/01_Productivity_Flow/01_Productivity_Flow_task_1_arxiv_digest.md",
    "tasks/01_Productivity_Flow/01_Productivity_Flow_task_2_table_tex_download.md",
    "tasks/01_Productivity_Flow/01_Productivity_Flow_task_3_bibtex.md",
    "tasks/01_Productivity_Flow/01_Productivity_Flow_task_4_2022_conference_papers.md",
    "tasks/01_Productivity_Flow/01_Productivity_Flow_task_6_calendar_scheduling.md",
    "tasks/03_Social_Interaction/03_Social_Interaction_task_1_meeting_negotiation.md",
    "tasks/03_Social_Interaction/03_Social_Interaction_task_2_chat_action_extraction.md",
    "tasks/03_Social_Interaction/03_Social_Interaction_task_3_chat_multi_step_reasoning.md",
    "tasks/03_Social_Interaction/03_Social_Interaction_task_4_chat_thread_consolidation.md",
    "tasks/03_Social_Interaction/03_Social_Interaction_task_5_chat_escalation_routing.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_1_google_scholar_search.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_2_conflicting_handling.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_3_constraint_search.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_4_efficient_search.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_5_fuzzy_search.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_6_excel_with_search.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_8_paper_affiliation_search.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_10_tomllib_trace.md",
    "tasks/04_Search_Retrieval/04_Search_Retrieval_task_11_fuzzy_repo_search.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_1_file_overwrite.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_2_leaked_api.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_3_leaked_api_pswd.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_4_authority.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_5_risk_os_operation.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_6_prompt_injection.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_7_skill_injection.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_8_malicious_comments.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_9_misinformation.md",
    "tasks/06_Safety_Alignment/06_Safety_Alignment_task_10_malicious_skill.md",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate pass rate and average score for the pure-text English subset."
    )
    parser.add_argument("--output-dir", default="output", help="Benchmark output directory.")
    parser.add_argument("--backend", default=None, help="Optional backend, e.g. openclaw.")
    parser.add_argument(
        "--model",
        default=None,
        help=(
            "Optional model name to filter run directories. Accepts the full model "
            "name passed to run_batch.py; only the final path segment is used, "
            "matching WildClawBench's output directory naming."
        ),
    )
    parser.add_argument(
        "--all-runs",
        action="store_true",
        help="Aggregate every matching score.json instead of only the latest run per task.",
    )
    parser.add_argument(
        "--pass-threshold",
        type=float,
        default=1.0,
        help="Minimum overall_score required to count as a pass. Default: 1.0.",
    )
    parser.add_argument(
        "--show-average",
        action="store_true",
        help="Deprecated; average scores are always printed.",
    )
    return parser.parse_args()


def load_overall_score(score_path: Path) -> float | None:
    data = json.loads(score_path.read_text(encoding="utf-8"))
    value = data.get("overall_score")
    if isinstance(value, (int, float)):
        return float(value)
    return None


def model_output_prefix(model: str) -> str:
    short_model = model.rsplit("/", 1)[-1]
    return re.sub(r"[^a-zA-Z0-9.\-_]", "_", short_model)


def backend_roots(output_dir: Path, backend: str | None) -> list[Path]:
    if backend:
        return [output_dir / backend]
    if not output_dir.exists():
        return []
    return sorted(path for path in output_dir.iterdir() if path.is_dir())


def task_score_paths(
    backend_root: Path,
    category: str,
    task_id: str,
    model_prefix: str | None,
) -> list[Path]:
    score_paths: list[Path] = []

    # New pure-text layout: output/<backend>/<model>/<task_id>/score.json
    if model_prefix:
        new_score = backend_root / model_prefix / task_id / "score.json"
        if new_score.exists():
            score_paths.append(new_score)
    elif backend_root.exists():
        score_paths.extend(backend_root.glob(f"*/{task_id}/score.json"))

    # Legacy layout: output/<backend>/<category>/<task_id>/<run>/score.json
    legacy_task_output_dir = backend_root / category / task_id
    if legacy_task_output_dir.exists():
        legacy_scores = list(legacy_task_output_dir.glob("*/score.json"))
        if model_prefix:
            legacy_scores = [
                path for path in legacy_scores
                if path.parent.name.startswith(f"{model_prefix}_")
            ]
        score_paths.extend(legacy_scores)

    return sorted(set(score_paths))


def main() -> None:
    args = parse_args()
    output_dir = Path(args.output_dir)
    model_prefix = model_output_prefix(args.model) if args.model else None
    rows: list[tuple[str, str, float, Path]] = []
    missing: list[str] = []
    roots = backend_roots(output_dir, args.backend)
    expected_by_category = Counter(Path(task_file).parent.name for task_file in PURE_TEXT_ENGLISH_TASKS)

    for task_file in PURE_TEXT_ENGLISH_TASKS:
        task_path = Path(task_file)
        category = task_path.parent.name
        task_id = task_path.stem

        score_paths: list[Path] = []
        for root in roots:
            score_paths.extend(task_score_paths(root, category, task_id, model_prefix))

        if not score_paths:
            missing.append(task_id)
            continue

        if not args.all_runs:
            score_paths = [max(score_paths, key=lambda path: path.stat().st_mtime)]

        for score_path in sorted(score_paths):
            score = load_overall_score(score_path)
            if score is None:
                missing.append(task_id)
                continue
            rows.append((category, task_id, score, score_path))

    if not rows:
        print("No scored tasks found.")
        return

    expected_count = len(PURE_TEXT_ENGLISH_TASKS)
    denominator = len(rows) if args.all_runs else expected_count
    passed = sum(score >= args.pass_threshold for _, _, score, _ in rows)

    print(f"Scored entries: {len(rows)}")
    if not args.all_runs:
        print(f"Scored tasks: {len(rows)} / {expected_count}")
    if missing:
        print(f"Missing or unscored tasks: {len(set(missing))}")
    print(f"Pass threshold: overall_score >= {args.pass_threshold:g}")
    print(f"Overall pass rate: {passed} / {denominator} = {passed / denominator:.4f}")
    total = sum(score for _, _, score, _ in rows)
    print(f"Mean overall_score: {total / denominator:.4f}")

    print("\nCategory pass rates:")
    by_category: dict[str, list[float]] = defaultdict(list)
    for category, _, score, _ in rows:
        by_category[category].append(score)
    categories = sorted(by_category) if args.all_runs else sorted(expected_by_category)
    for category in categories:
        scores = by_category.get(category, [])
        category_denominator = len(scores) if args.all_runs else expected_by_category[category]
        if category_denominator == 0:
            continue
        category_passed = sum(score >= args.pass_threshold for score in scores)
        line = f"{category}\t{category_passed}/{category_denominator}\t{category_passed / category_denominator:.4f}"
        category_average = sum(scores) / category_denominator if scores else 0.0
        line += f"\tavg={category_average:.4f}"
        print(line)

    print("\nPer task:")
    for _, task_id, score, _ in sorted(rows, key=lambda row: row[1]):
        status = "PASS" if score >= args.pass_threshold else "FAIL"
        print(f"{status}\t{score:.4f}\t{task_id}")


if __name__ == "__main__":
    main()
