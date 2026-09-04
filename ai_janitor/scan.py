from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

from .catalog import CLEANABLE, detect_status, load_catalog
from .paths import is_inside_home, measure, resolve_pattern

CACHE_NAME = "scan.json"
DEFAULT_TTL_SEC = 600


def cache_path(home: Path) -> Path:
    xdg = os.environ.get("XDG_CACHE_HOME")
    root = Path(xdg) if xdg else home / ".cache"
    return root / "ai-janitor" / CACHE_NAME


def scan(
    *,
    home: Path,
    catalog_path: Path | None = None,
    fresh: bool = False,
    ttl_sec: int = DEFAULT_TTL_SEC,
    classes: set[str] | None = None,
) -> dict:
    if not fresh:
        cached = read_cache(home, ttl_sec)
        if cached is not None:
            return filter_report(cached, classes)
    report = scan_fresh(home=home, catalog_path=catalog_path)
    write_cache(home, report)
    return filter_report(report, classes)


def scan_fresh(*, home: Path, catalog_path: Path | None = None) -> dict:
    catalog = load_catalog(catalog_path)
    tools_out = []
    totals = {
        "bytes": 0,
        "reclaimableCache": 0,
        "reclaimableStale": 0,
        "reclaimableReview": 0,
    }
    for tool in catalog["tools"]:
        live_status = detect_status(tool)
        items_out = []
        tool_bytes = 0
        for item in tool["items"]:
            klass = item["class"]
            if klass not in CLEANABLE:
                continue
            resolved = []
            for raw in item["paths"]:
                for path in resolve_pattern(raw, home):
                    if is_inside_home(path, home):
                        resolved.append(path)
            bytes_, mtime, count = measure(resolved)
            if bytes_ <= 0 and count <= 0:
                continue
            tool_bytes += bytes_
            totals["bytes"] += bytes_
            if klass == "cache":
                totals["reclaimableCache"] += bytes_
            elif klass == "stale":
                totals["reclaimableStale"] += bytes_
            elif klass == "review":
                totals["reclaimableReview"] += bytes_
            items_out.append(
                {
                    "id": item["id"],
                    "class": klass,
                    "summary": item.get("summary") or item["id"],
                    "summary_zh": item.get("summary_zh") or item.get("summary") or item["id"],
                    "paths": [str(p) for p in resolved],
                    "path": item["paths"][0],
                    "bytes": bytes_,
                    "count": count,
                    "exists": True,
                    "mtime": iso_from_mtime(mtime),
                }
            )
        if not items_out:
            continue
        tools_out.append(
            {
                "id": tool["id"],
                "name": tool["name"],
                "status": live_status,
                "bytes": tool_bytes,
                "items": items_out,
            }
        )
    return {
        "scannedAt": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "home": str(home),
        "totals": totals,
        "tools": tools_out,
    }


def iso_from_mtime(mtime: float) -> str | None:
    if not mtime:
        return None
    return datetime.fromtimestamp(mtime).astimezone().isoformat(timespec="seconds")


def read_cache(home: Path, ttl_sec: int) -> dict | None:
    path = cache_path(home)
    try:
        st = path.stat()
    except OSError:
        return None
    age = datetime.now().timestamp() - st.st_mtime
    if age > ttl_sec:
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict) or "tools" not in data:
        return None
    return data


def write_cache(home: Path, report: dict) -> None:
    path = cache_path(home)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def filter_report(report: dict, classes: set[str] | None) -> dict:
    if not classes:
        return report
    tools = []
    totals = {
        "bytes": 0,
        "reclaimableCache": 0,
        "reclaimableStale": 0,
        "reclaimableReview": 0,
    }
    for tool in report.get("tools") or []:
        items = [item for item in tool.get("items") or [] if item.get("class") in classes]
        if not items:
            continue
        tool_bytes = sum(int(item.get("bytes") or 0) for item in items)
        tools.append({**tool, "items": items, "bytes": tool_bytes})
        totals["bytes"] += tool_bytes
        for item in items:
            klass = item.get("class")
            bytes_ = int(item.get("bytes") or 0)
            if klass == "cache":
                totals["reclaimableCache"] += bytes_
            elif klass == "stale":
                totals["reclaimableStale"] += bytes_
            elif klass == "review":
                totals["reclaimableReview"] += bytes_
    return {**report, "tools": tools, "totals": totals}
