from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import __version__
from .catalog import CLEANABLE
from .clean import CleanError, clean
from .format import format_bytes, format_table
from .scan import scan
from .tui import run_tui


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    home = Path(args.home).expanduser() if args.home else Path.home()
    catalog_path = Path(args.catalog) if args.catalog else None
    classes = selected_classes(args)

    if args.command == "scan":
        report = scan(
            home=home,
            catalog_path=catalog_path,
            fresh=args.fresh,
            classes=classes,
        )
        if args.json:
            print(json.dumps(report, ensure_ascii=False, indent=2))
        else:
            sys.stdout.write(format_table(report))
        return 0

    if args.command == "clean":
        ids = parse_ids(args.ids)
        if not ids:
            report = scan(home=home, catalog_path=catalog_path, fresh=args.fresh, classes=classes)
            ids = [item["id"] for tool in report.get("tools") or [] for item in tool.get("items") or []]
        if not ids:
            print("Nothing to clean.")
            return 0
        dry_run = not args.yes
        try:
            result = clean(home=home, ids=ids, catalog_path=catalog_path, dry_run=dry_run)
        except CleanError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            verb = "Would trash" if dry_run else "Trashed"
            print(f"{verb} {format_bytes(result.get('bytes'))} in {len(result.get('items') or [])} items.")
            if dry_run:
                print("Re-run with --yes to move them to trash.")
        return 0

    report = scan(home=home, catalog_path=catalog_path, fresh=args.fresh, classes=classes)
    if sys.stdin.isatty() and sys.stdout.isatty():
        code = run_tui(report, home=home, catalog_path=catalog_path, classes=classes)
        if code is not None:
            return code
    sys.stdout.write(format_table(report))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ai-janitor",
        description="Scan and trash reclaimable AI-tool data. Default clean is dry-run.",
    )
    parser.add_argument("--version", action="version", version=f"ai-janitor {__version__}")
    parser.add_argument("command", nargs="?", choices=["scan", "clean"], help="scan (default) or clean")
    parser.add_argument("--home", help="Home directory (tests / override)")
    parser.add_argument("--catalog", help="Path to catalog.json")
    parser.add_argument("--json", action="store_true", help="Machine-readable output")
    parser.add_argument("--safe", action="store_true", help="Only cache-class items")
    parser.add_argument("--stale", action="store_true", help="Include uninstalled-tool directories")
    parser.add_argument("--review", action="store_true", help="Include sessions/models/memory")
    parser.add_argument("--fresh", action="store_true", help="Ignore the scan cache")
    parser.add_argument("--ids", help="Comma-separated item ids (clean)")
    parser.add_argument("--yes", action="store_true", help="Actually trash; without this, clean is dry-run")
    parser.add_argument("--dry-run", action="store_true", help="Explicit dry-run (the default for clean)")
    return parser


def selected_classes(args: argparse.Namespace) -> set[str] | None:
    flags = []
    if args.safe:
        flags.append("cache")
    if args.stale:
        flags.append("stale")
    if args.review:
        flags.append("review")
    if not flags:
        return set(CLEANABLE)
    return set(flags)


def parse_ids(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [part.strip() for part in raw.split(",") if part.strip()]
