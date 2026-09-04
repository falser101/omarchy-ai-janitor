from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from .clean import CleanError, clean
from .format import format_bytes


def run_tui(report: dict, *, home: Path, catalog_path: Path | None, classes: set[str]) -> int | None:
    gum = shutil.which("gum")
    if not gum:
        return None

    ordered: list[str] = []
    by_id: dict[str, str] = {}
    for klass in ("cache", "stale", "review"):
        if klass not in classes:
            continue
        for tool in report.get("tools") or []:
            for item in tool.get("items") or []:
                if item.get("class") != klass:
                    continue
                label = f"{item['id']}  {format_bytes(item.get('bytes'))}  {item.get('summary')}"
                ordered.append(label)
                by_id[label] = item["id"]
    if not ordered:
        print("Nothing reclaimable.")
        return 0

    selected = _gum_choose(gum, ordered)
    if selected is None:
        return 1
    if not selected:
        print("Nothing selected.")
        return 0
    ids = [by_id[label] for label in selected if label in by_id]
    planned = clean(home=home, ids=ids, catalog_path=catalog_path, dry_run=True)
    total = format_bytes(planned.get("bytes"))
    names = ", ".join(ids)
    if not _gum_confirm(gum, f"Move {len(ids)} items ({total}) to trash?\n{names}"):
        print("Canceled.")
        return 0
    try:
        result = clean(home=home, ids=ids, catalog_path=catalog_path, dry_run=False)
    except CleanError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"Trashed {format_bytes(result.get('bytes'))} in {len(ids)} items.")
    return 0


def _gum_choose(gum: str, choices: list[str]) -> list[str] | None:
    completed = subprocess.run(
        [gum, "choose", "--no-limit", "--header", "Select AI data to trash"],
        input="\n".join(choices) + "\n",
        text=True,
        check=False,
        capture_output=True,
    )
    if completed.returncode != 0:
        return None
    return [line for line in completed.stdout.splitlines() if line.strip()]


def _gum_confirm(gum: str, message: str) -> bool:
    completed = subprocess.run([gum, "confirm", message], check=False)
    return completed.returncode == 0
