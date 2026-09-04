from __future__ import annotations

import json
import shutil
from pathlib import Path

CLEANABLE = frozenset({"cache", "stale", "review"})
BLOCKED = frozenset({"secret", "keep"})
CLASSES = CLEANABLE | BLOCKED

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CATALOG = ROOT / "catalog.json"


def load_catalog(path: Path | None = None) -> dict:
    catalog_path = Path(path) if path else DEFAULT_CATALOG
    data = json.loads(catalog_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("tools"), list):
        raise ValueError(f"invalid catalog: {catalog_path}")
    for tool in data["tools"]:
        _validate_tool(tool)
    return data


def _validate_tool(tool: dict) -> None:
    if not tool.get("id") or not tool.get("name"):
        raise ValueError("tool missing id or name")
    items = tool.get("items")
    if not isinstance(items, list):
        raise ValueError(f"tool {tool['id']} missing items")
    seen = set()
    for item in items:
        item_id = item.get("id")
        klass = item.get("class")
        paths = item.get("paths")
        if not item_id or klass not in CLASSES or not isinstance(paths, list) or not paths:
            raise ValueError(f"bad item in {tool['id']}: {item_id}")
        if item_id in seen:
            raise ValueError(f"duplicate item id: {item_id}")
        seen.add(item_id)


def index_items(catalog: dict) -> dict[str, tuple[dict, dict]]:
    out: dict[str, tuple[dict, dict]] = {}
    for tool in catalog["tools"]:
        for item in tool["items"]:
            out[item["id"]] = (tool, item)
    return out


def detect_status(tool: dict) -> str:
    declared = str(tool.get("status") or "stale")
    detect = tool.get("detect") or {}
    binaries = detect.get("binaries") or []
    if not binaries:
        return declared
    present = any(shutil.which(name) for name in binaries)
    if present:
        return declared
    if declared == "active":
        return "stale"
    return declared


def cleanable_items(catalog: dict, *, classes: set[str] | None = None) -> list[tuple[dict, dict]]:
    wanted = classes or set(CLEANABLE)
    rows = []
    for tool in catalog["tools"]:
        for item in tool["items"]:
            if item["class"] in wanted:
                rows.append((tool, item))
    return rows
