#!/usr/bin/env python3
"""
LOSO evaluation harness for FlowRep IMU session exports (Doc 15 FR-A9).

Input: directory of JSON files from FlowRep export (flowrep-export-v1) or a
simple list of labeled windows: {"subject": "...", "exercise": "...", "features": [...]}.

This is a lightweight baseline (sklearn if available, else majority-class).
It does NOT ship a production model — it prevents the "memorize subject" trap.

Usage:
  python tools/ml/loso_eval.py --input path/to/exports --out report.json
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


def load_labeled_rows(input_dir: Path) -> list[dict[str, Any]]:
    """Load either flowrep export sessions or flat {subject,exercise,features} rows."""
    rows: list[dict[str, Any]] = []
    for path in sorted(input_dir.glob("**/*")):
        if path.suffix.lower() not in {".json", ".jsonl"}:
            continue
        text = path.read_text(encoding="utf-8")
        if path.suffix.lower() == ".jsonl":
            for line in text.splitlines():
                line = line.strip()
                if not line:
                    continue
                rows.append(json.loads(line))
            continue
        data = json.loads(text)
        if isinstance(data, list):
            rows.extend(data)
            continue
        # FlowRep export: invent a subject from file stem; features = peaks per set
        subject = path.stem
        sessions = data.get("sessions") or []
        for session in sessions:
            for s in session.get("sets") or []:
                peaks = [r.get("peakMagnitude", 0.0) for r in s.get("reps") or []]
                if not peaks:
                    continue
                features = [
                    sum(peaks) / len(peaks),
                    max(peaks),
                    min(peaks),
                    len(peaks),
                ]
                rows.append(
                    {
                        "subject": subject,
                        "exercise": s.get("exerciseId", "unknown"),
                        "features": features,
                    }
                )
    return rows


def majority_predict(train_labels: list[str], test_n: int) -> list[str]:
    if not train_labels:
        return ["unknown"] * test_n
    label, _ = Counter(train_labels).most_common(1)[0]
    return [label] * test_n


def try_sklearn_predict(
    X_train: list[list[float]],
    y_train: list[str],
    X_test: list[list[float]],
) -> list[str] | None:
    try:
        from sklearn.ensemble import RandomForestClassifier  # type: ignore
        from sklearn.preprocessing import LabelEncoder  # type: ignore
    except Exception:
        return None
    if len(set(y_train)) < 2 or len(X_train) < 4:
        return None
    le = LabelEncoder()
    y_enc = le.fit_transform(y_train)
    clf = RandomForestClassifier(n_estimators=50, random_state=0)
    clf.fit(X_train, y_enc)
    pred = clf.predict(X_test)
    return list(le.inverse_transform(pred))


def loso(rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_subject: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        by_subject[str(r.get("subject", "unknown"))].append(r)

    subjects = sorted(by_subject.keys())
    per_subject: dict[str, Any] = {}
    all_true: list[str] = []
    all_pred: list[str] = []

    for holdout in subjects:
        test = by_subject[holdout]
        train = [r for s, rs in by_subject.items() if s != holdout for r in rs]
        X_train = [list(map(float, r["features"])) for r in train if "features" in r]
        y_train = [str(r["exercise"]) for r in train if "features" in r]
        X_test = [list(map(float, r["features"])) for r in test if "features" in r]
        y_test = [str(r["exercise"]) for r in test if "features" in r]
        if not X_test:
            continue
        pred = try_sklearn_predict(X_train, y_train, X_test)
        if pred is None:
            pred = majority_predict(y_train, len(X_test))
        correct = sum(1 for a, b in zip(y_test, pred) if a == b)
        acc = correct / len(y_test) if y_test else 0.0
        per_subject[holdout] = {
            "n": len(y_test),
            "accuracy": acc,
            "labels": y_test,
            "pred": pred,
        }
        all_true.extend(y_test)
        all_pred.extend(pred)

    # Confusion counts
    labels = sorted(set(all_true) | set(all_pred))
    matrix = {a: {b: 0 for b in labels} for a in labels}
    for t, p in zip(all_true, all_pred):
        matrix[t][p] += 1

    overall = (
        sum(1 for a, b in zip(all_true, all_pred) if a == b) / len(all_true)
        if all_true
        else 0.0
    )
    return {
        "subjects": subjects,
        "overall_accuracy": overall,
        "per_subject": per_subject,
        "confusion": matrix,
        "n_rows": len(rows),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="FlowRep LOSO eval harness")
    ap.add_argument("--input", required=True, type=Path, help="Dir with JSON/JSONL")
    ap.add_argument("--out", type=Path, default=None, help="Write report JSON")
    args = ap.parse_args()
    if not args.input.exists():
        print(f"Input not found: {args.input}", file=sys.stderr)
        return 2
    rows = load_labeled_rows(args.input)
    if not rows:
        print("No labeled rows found.", file=sys.stderr)
        return 1
    report = loso(rows)
    text = json.dumps(report, indent=2)
    print(text)
    if args.out:
        args.out.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
