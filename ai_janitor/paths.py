from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path


def expand_user(raw: str, home: Path) -> str:
    text = str(raw)
    if text == "~":
        return str(home)
    if text.startswith("~/"):
        return str(home / text[2:])
    if text.startswith("~"):
        raise ValueError(f"other-user home is not allowed: {raw}")
    return text


def resolve_pattern(raw: str, home: Path) -> list[Path]:
    expanded = expand_user(raw, home)
    if any(ch in expanded for ch in "*?["):
        return _glob_paths(expanded)
    path = Path(expanded)
    return [path] if path.exists() else []


def _glob_paths(pattern: str) -> list[Path]:
    path = Path(pattern)
    parts = path.parts
    if "**" in parts:
        return _rglob_parts(path)
    parent = path.parent
    name = path.name
    if not parent.exists() or not parent.is_dir():
        return []
    found: list[Path] = []
    with os.scandir(parent) as entries:
        for entry in entries:
            if _fnmatch_name(entry.name, name):
                found.append(Path(entry.path))
    return found


def _fnmatch_name(name: str, pattern: str) -> bool:
    from fnmatch import fnmatch

    return fnmatch(name, pattern)


def _rglob_parts(path: Path) -> list[Path]:
    parts = list(path.parts)
    try:
        star = parts.index("**")
    except ValueError:
        return []
    root = Path(*parts[:star]) if star > 0 else Path("/")
    rest = parts[star + 1 :]
    if not rest:
        return [root] if root.exists() else []
    if not root.exists():
        return []
    needle = Path(*rest)
    found: list[Path] = []
    if len(rest) == 1:
        for match in root.rglob(rest[0]):
            if match.name == rest[0] or _fnmatch_name(match.name, rest[0]):
                found.append(match)
        return found
    suffix = str(needle)
    for match in root.rglob(rest[-1]):
        try:
            rel = match.relative_to(root)
        except ValueError:
            continue
        if str(rel) == suffix or rel.match(suffix):
            found.append(match)
    return found


def is_inside_home(path: Path, home: Path) -> bool:
    try:
        resolved = path.resolve()
        home_resolved = home.resolve()
        resolved.relative_to(home_resolved)
        return True
    except (OSError, ValueError):
        return False


def measure(paths: list[Path]) -> tuple[int, float, int]:
    total = 0
    mtime = 0.0
    count = 0
    seen: set[str] = set()
    for path in paths:
        key = str(path)
        if key in seen:
            continue
        seen.add(key)
        bytes_, stamp, n = measure_one(path)
        total += bytes_
        if stamp > mtime:
            mtime = stamp
        count += n
    return total, mtime, count


def measure_one(path: Path) -> tuple[int, float, int]:
    try:
        st = path.lstat()
    except OSError:
        return 0, 0.0, 0
    if stat.S_ISLNK(st.st_mode):
        return 0, st.st_mtime, 0
    if stat.S_ISREG(st.st_mode):
        return int(st.st_size), st.st_mtime, 1
    if stat.S_ISDIR(st.st_mode):
        return _du_dir(path, st.st_mtime)
    return 0, st.st_mtime, 0


def _du_dir(path: Path, fallback_mtime: float) -> tuple[int, float, int]:
    try:
        completed = subprocess.run(
            ["du", "-sb", "--apparent-size", str(path)],
            check=False,
            capture_output=True,
            text=True,
            timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired):
        return _walk_dir(path, fallback_mtime)
    if completed.returncode != 0 or not completed.stdout:
        return _walk_dir(path, fallback_mtime)
    first = completed.stdout.split(None, 1)[0]
    try:
        size = int(first)
    except ValueError:
        return _walk_dir(path, fallback_mtime)
    return size, fallback_mtime, 1


def _walk_dir(path: Path, fallback_mtime: float) -> tuple[int, float, int]:
    total = 0
    mtime = fallback_mtime
    count = 0
    for root, dirs, files in os.walk(path, followlinks=False):
        dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(root, name))]
        for name in files:
            file_path = os.path.join(root, name)
            try:
                st = os.lstat(file_path)
            except OSError:
                continue
            if stat.S_ISLNK(st.st_mode):
                continue
            total += int(st.st_size)
            if st.st_mtime > mtime:
                mtime = st.st_mtime
            count += 1
    return total, mtime, max(count, 1)
