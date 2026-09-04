from __future__ import annotations

import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from .catalog import BLOCKED, CLEANABLE, index_items, load_catalog
from .paths import is_inside_home, measure, resolve_pattern

BATCH = 80


class CleanError(Exception):
    pass


def state_log_path(home: Path) -> Path:
    import os

    env = os.environ.get("XDG_STATE_HOME")
    root = Path(env) if env else home / ".local" / "state"
    return root / "ai-janitor" / "clean.log.jsonl"


def plan_clean(
    *,
    home: Path,
    ids: list[str],
    catalog_path: Path | None = None,
) -> list[dict]:
    catalog = load_catalog(catalog_path)
    index = index_items(catalog)
    planned = []
    for item_id in ids:
        if item_id not in index:
            raise CleanError(f"unknown item: {item_id}")
        tool, item = index[item_id]
        klass = item["class"]
        if klass in BLOCKED:
            raise CleanError(f"refusing to clean {klass} item: {item_id}")
        if klass not in CLEANABLE:
            raise CleanError(f"item is not cleanable: {item_id}")
        resolved = []
        for raw in item["paths"]:
            for path in resolve_pattern(raw, home):
                if not is_inside_home(path, home):
                    raise CleanError(f"path escapes home: {path}")
                resolved.append(path)
        bytes_, _, count = measure(resolved)
        planned.append(
            {
                "id": item_id,
                "tool": tool["id"],
                "class": klass,
                "summary": item.get("summary") or item_id,
                "paths": [str(p) for p in resolved],
                "bytes": bytes_,
                "count": count,
            }
        )
    return planned


def clean(
    *,
    home: Path,
    ids: list[str],
    catalog_path: Path | None = None,
    dry_run: bool = True,
) -> dict:
    planned = plan_clean(home=home, ids=ids, catalog_path=catalog_path)
    results = []
    trashed_bytes = 0
    for entry in planned:
        paths = [Path(p) for p in entry["paths"]]
        if dry_run:
            results.append({**entry, "trashed": False, "dryRun": True})
            trashed_bytes += int(entry["bytes"] or 0)
            continue
        trash_paths(paths)
        results.append({**entry, "trashed": True, "dryRun": False})
        trashed_bytes += int(entry["bytes"] or 0)
        log_clean(home, entry)
    return {
        "ok": True,
        "dryRun": dry_run,
        "bytes": trashed_bytes,
        "items": results,
    }


def trash_paths(paths: list[Path]) -> None:
    if not paths:
        return
    gio = shutil.which("gio")
    if not gio:
        raise CleanError("gio is not on PATH; refusing to delete without trash")
    existing = [str(p) for p in paths if p.exists()]
    for i in range(0, len(existing), BATCH):
        batch = existing[i : i + BATCH]
        completed = subprocess.run(
            [gio, "trash", "--", *batch],
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )
        if completed.returncode != 0:
            err = (completed.stderr or completed.stdout or "gio trash failed").strip()
            raise CleanError(err)


def log_clean(home: Path, entry: dict) -> None:
    path = state_log_path(home)
    path.parent.mkdir(parents=True, exist_ok=True)
    row = {
        "at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        **entry,
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, ensure_ascii=False) + "\n")
