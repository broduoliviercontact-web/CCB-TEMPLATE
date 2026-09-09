#!/usr/bin/env python3
"""Telemetry aggregator for CCB.

Reads usage.jsonl (proxy events) and outcomes.jsonl (user-recorded task
outcomes) and prints per-task and per-complexity reports.

Stdlib only. No third-party dependency. Tolerant to malformed lines: they
are silently skipped and counted.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from typing import Any


def _stream_jsonl(path: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    if not path:
        return events
    try:
        with open(path, encoding="utf-8") as source:
            for line in source:
                line = line.strip()
                if not line:
                    continue
                try:
                    document = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(document, dict):
                    events.append(document)
    except FileNotFoundError:
        pass
    return events


def _fmt(number: int) -> str:
    return f"{number:,}"


def _ratio(numerator: int, denominator: int) -> str:
    if denominator <= 0:
        return "n/a"
    return f"{(numerator / denominator) * 100:.1f}%"


def _latest_outcomes(events: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    latest: dict[str, dict[str, Any]] = {}
    for event in events:
        task_id = event.get("task_id")
        if not isinstance(task_id, str) or not task_id:
            continue
        latest[task_id] = event
    return latest


def _initial_complexity(event: dict[str, Any]) -> str | None:
    value = event.get("initial_complexity")
    if isinstance(value, str) and value:
        return value
    value = event.get("complexity")
    if isinstance(value, str) and value:
        return value
    return None


def _current_complexity(event: dict[str, Any]) -> str | None:
    value = event.get("current_complexity")
    if isinstance(value, str) and value:
        return value
    value = event.get("complexity")
    if isinstance(value, str) and value:
        return value
    return None


def _tokens(event: dict[str, Any]) -> int:
    in_tokens = int(event.get("input_tokens") or 0)
    out_tokens = int(event.get("output_tokens") or 0)
    return in_tokens + out_tokens


def report_task(usage_events: list[dict[str, Any]], task_id: str) -> None:
    events = [e for e in usage_events if e.get("task_id") == task_id]
    in_total = sum(int(e.get("input_tokens") or 0) for e in events)
    out_total = sum(int(e.get("output_tokens") or 0) for e in events)
    calls = len(events)
    ms_total = sum(int(e.get("duration_ms") or 0) for e in events)

    print(f"TASK {task_id}")
    initial = next((_initial_complexity(e) for e in events if _initial_complexity(e)), None)
    if initial is None:
        initial = "unknown"
    print(f"Complexity: {initial}")

    print("\nTokens:")
    print(f"  input:  {_fmt(in_total)}")
    print(f"  output: {_fmt(out_total)}")
    print(f"  total:  {_fmt(in_total + out_total)}")
    print(f"  calls:  {_fmt(calls)}")
    print(f"  ms:     {_fmt(ms_total)}")

    by_agent: dict[str, dict[str, int]] = defaultdict(lambda: {"in": 0, "out": 0, "calls": 0})
    for event in events:
        agent = event.get("agent") or "?"
        by_agent[agent]["in"] += int(event.get("input_tokens") or 0)
        by_agent[agent]["out"] += int(event.get("output_tokens") or 0)
        by_agent[agent]["calls"] += 1
    print("\nAgents:")
    print(f"  {'agent':<10} {'input':>10} {'output':>10} {'calls':>6}")
    for agent in sorted(by_agent):
        data = by_agent[agent]
        print(f"  {agent:<10} {_fmt(data['in']):>10} {_fmt(data['out']):>10} {_fmt(data['calls']):>6}")


def report_tasks(
    usage_events: list[dict[str, Any]],
    outcome_events: list[dict[str, Any]],
) -> None:
    latest_outcomes = _latest_outcomes(outcome_events)
    print("AGGREGATE BY COMPLEXITY\n")
    for level in ("simple", "normal", "complex"):
        scoped = [
            e for e in usage_events
            if (_current_complexity(e) or _initial_complexity(e)) == level
        ]
        tokens = sum(_tokens(e) for e in scoped)
        calls = len(scoped)
        print(f"  {level:<8} tokens: {_fmt(tokens):>10}   calls: {_fmt(calls):>6}")

    print("\nPER-COMPLEXITY METRICS")
    for level in ("simple", "normal", "complex"):
        scoped_outcomes = [
            outcome for outcome in latest_outcomes.values()
            if _initial_complexity(outcome) == level
        ]
        if not scoped_outcomes:
            print(f"\n  {level.upper()}:")
            print("    no outcomes recorded")
            continue
        accepted = sum(1 for o in scoped_outcomes if o.get("status") == "accepted")
        needs_fix = sum(1 for o in scoped_outcomes if o.get("status") == "needs_fix")
        failed = sum(1 for o in scoped_outcomes if o.get("status") == "failed")
        abandoned = sum(1 for o in scoped_outcomes if o.get("status") == "abandoned")
        rework = sum(1 for o in scoped_outcomes if (int(o.get("rework_count") or 0)) > 0)
        reviewed = sum(
            1 for o in scoped_outcomes
            if o.get("review") in ("pass", "findings")
        )
        with_findings = sum(1 for o in scoped_outcomes if o.get("review") == "findings")
        # Escalation_rate: tasks with initial_complexity=level and escalated=true
        # over tasks with initial_complexity=level.
        eligible = scoped_outcomes
        escalated = sum(
            1 for o in eligible
            if str(o.get("escalated") or "").lower() == "true"
        )
        accepted_tokens = sum(
            _tokens(e) for e in usage_events
            if e.get("task_id") in {
                tid for tid, o in latest_outcomes.items()
                if _initial_complexity(o) == level and o.get("status") == "accepted"
            }
        )

        print(f"\n  {level.upper()}:")
        print(f"    outcomes: {len(scoped_outcomes)}  accepted: {accepted}  needs_fix: {needs_fix}  failed: {failed}  abandoned: {abandoned}")
        print(f"    acceptance_rate:    {_ratio(accepted, len(scoped_outcomes))}")
        print(f"    rework_rate:        {_ratio(rework, len(scoped_outcomes))}")
        if reviewed > 0:
            print(f"    reviewer_findings_rate: {_ratio(with_findings, reviewed)}")
        if level == "simple":
            print(f"    escalation_rate:    {_ratio(escalated, len(scoped_outcomes))}")
        if accepted > 0:
            print(f"    tokens_per_accepted_task: {_fmt(accepted_tokens // accepted)}")
        else:
            print("    tokens_per_accepted_task: n/a")


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        return 2
    usage_path, outcomes_path, query = argv[1], argv[2], argv[3]
    usage_events = _stream_jsonl(usage_path) if usage_path else []
    outcome_events = _stream_jsonl(outcomes_path) if outcomes_path else []

    if query == "task":
        if len(argv) < 5:
            return 2
        report_task(usage_events, argv[4])
    elif query == "tasks":
        report_tasks(usage_events, outcome_events)
    else:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))