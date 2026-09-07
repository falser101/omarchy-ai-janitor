from __future__ import annotations

import json
import shutil
from pathlib import Path
from urllib.parse import unquote

CLEANABLE = frozenset({"cache", "stale", "review"})
BLOCKED = frozenset({"secret", "keep"})
CLASSES = CLEANABLE | BLOCKED
CHILD_SEP = "::"


def safe_child_name(name: str) -> bool:
    if not name or name in {".", ".."}:
        return False
    if "/" in name or "\\" in name or "\x00" in name:
        return False
    return True


def child_label(name: str, home: Path) -> str:
    text = unquote(name)
    home_str = str(home)
    if text == home_str or text.startswith(home_str + "/"):
        rel = text[len(home_str) :].lstrip("/")
        return "~/" + rel if rel else "~"
    user = home.name
    claude_prefix = f"-home-{user}"
    if name.startswith(claude_prefix):
        rest = name[len(claude_prefix) :].lstrip("-")
        if not rest:
            return "~"
        for top in ("Projects", "Documents", "Downloads", "Work", "Desktop"):
            if rest == top:
                return "~/" + top
            if rest.startswith(top + "-"):
                return "~/" + top + "/" + rest[len(top) + 1 :]
        return "~/" + rest
    if name.startswith("models--"):
        return name[len("models--") :].replace("--", "/")
    return name

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
        expand = item.get("expand")
        if expand not in (None, "children"):
            raise ValueError(f"bad expand on {item_id}")
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
