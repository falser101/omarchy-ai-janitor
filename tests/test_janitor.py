#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from ai_janitor.catalog import load_catalog
from ai_janitor.clean import CleanError, clean
from ai_janitor.scan import scan_fresh


FIXTURE_CATALOG = {
    "version": 1,
    "tools": [
        {
            "id": "demo",
            "name": "Demo",
            "status": "active",
            "items": [
                {
                    "id": "demo-cache",
                    "class": "cache",
                    "summary": "Cache files",
                    "paths": ["~/.demo/cache"],
                },
                {
                    "id": "demo-glob",
                    "class": "cache",
                    "summary": "Clobbered fragments",
                    "paths": ["~/.demo/clobbered.*"],
                },
                {
                    "id": "demo-auth",
                    "class": "secret",
                    "summary": "Auth",
                    "paths": ["~/.demo/auth.json"],
                },
                {
                    "id": "demo-keep",
                    "class": "keep",
                    "summary": "Keep me",
                    "paths": ["~/.demo/keep.txt"],
                },
            ],
        }
    ],
}


class JanitorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        demo = self.home / ".demo"
        demo.mkdir()
        (demo / "cache").mkdir()
        (demo / "cache" / "a.bin").write_bytes(b"x" * 100)
        (demo / "clobbered.1").write_text("one")
        (demo / "clobbered.2").write_text("two")
        (demo / "auth.json").write_text('{"token":"secret"}')
        (demo / "keep.txt").write_text("keep")
        self.catalog = Path(self.tmp.name) / "catalog.json"
        self.catalog.write_text(json.dumps(FIXTURE_CATALOG), encoding="utf-8")
        self.trash = Path(self.tmp.name) / "trash"
        self.trash.mkdir()
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        gio = self.bin / "gio"
        gio.write_text(
            "#!/bin/sh\n"
            'if [ "$1" != "trash" ]; then echo "expected trash" >&2; exit 1; fi\n'
            "shift\n"
            '[ "$1" = "--" ] && shift\n'
            f'mkdir -p "{self.trash}"\n'
            "for f in \"$@\"; do mv \"$f\" "
            f'"{self.trash}/$(basename "$f")" || exit 1; done\n',
            encoding="utf-8",
        )
        gio.chmod(gio.stat().st_mode | stat.S_IEXEC)
        self.old_path = os.environ.get("PATH", "")
        os.environ["PATH"] = str(self.bin) + os.pathsep + self.old_path
        os.environ["XDG_CACHE_HOME"] = str(Path(self.tmp.name) / "cache")
        os.environ["XDG_STATE_HOME"] = str(Path(self.tmp.name) / "state")

    def tearDown(self) -> None:
        os.environ["PATH"] = self.old_path
        self.tmp.cleanup()

    def test_catalog_loads(self) -> None:
        catalog = load_catalog(ROOT / "catalog.json")
        ids = [item["id"] for tool in catalog["tools"] for item in tool["items"]]
        self.assertIn("openclaw-clobbered", ids)
        self.assertIn("grok-auth", ids)
        self.assertIn("ollama-models", ids)

    def test_scan_omits_secrets(self) -> None:
        report = scan_fresh(home=self.home, catalog_path=self.catalog)
        ids = [item["id"] for tool in report["tools"] for item in tool["items"]]
        self.assertIn("demo-cache", ids)
        self.assertIn("demo-glob", ids)
        self.assertNotIn("demo-auth", ids)
        self.assertNotIn("demo-keep", ids)
        self.assertGreater(report["totals"]["reclaimableCache"], 0)

    def test_scan_safe_flag_via_cli(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "ai-janitor"),
                "scan",
                "--json",
                "--fresh",
                "--home",
                str(self.home),
                "--catalog",
                str(self.catalog),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        data = json.loads(completed.stdout)
        ids = [item["id"] for tool in data["tools"] for item in tool["items"]]
        self.assertEqual(set(ids), {"demo-cache", "demo-glob"})

    def test_clean_refuses_secret(self) -> None:
        with self.assertRaises(CleanError):
            clean(home=self.home, ids=["demo-auth"], catalog_path=self.catalog, dry_run=False)
        self.assertTrue((self.home / ".demo" / "auth.json").exists())

    def test_clean_dry_run_does_not_delete(self) -> None:
        result = clean(home=self.home, ids=["demo-cache"], catalog_path=self.catalog, dry_run=True)
        self.assertTrue(result["dryRun"])
        self.assertTrue((self.home / ".demo" / "cache" / "a.bin").exists())

    def test_clean_trashes_cache_and_glob(self) -> None:
        result = clean(
            home=self.home,
            ids=["demo-cache", "demo-glob"],
            catalog_path=self.catalog,
            dry_run=False,
        )
        self.assertTrue(result["ok"])
        self.assertFalse((self.home / ".demo" / "cache").exists())
        self.assertFalse((self.home / ".demo" / "clobbered.1").exists())
        self.assertTrue((self.home / ".demo" / "auth.json").exists())
        self.assertTrue((self.home / ".demo" / "keep.txt").exists())
        self.assertTrue((self.trash / "cache").exists() or (self.trash / "a.bin").exists() or list(self.trash.iterdir()))

    def test_clean_progress_events(self) -> None:
        events = []
        result = clean(
            home=self.home,
            ids=["demo-cache"],
            catalog_path=self.catalog,
            dry_run=False,
            on_event=events.append,
        )
        kinds = [event.get("event") for event in events]
        self.assertEqual(kinds[0], "start")
        self.assertIn("item", kinds)
        self.assertEqual(kinds[-1], "done")
        self.assertTrue(result["ok"])
        statuses = [event.get("status") for event in events if event.get("event") == "item"]
        self.assertEqual(statuses, ["start", "done"])

    def test_cli_progress_ndjson(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "ai-janitor"),
                "clean",
                "--yes",
                "--progress",
                "--ids",
                "demo-glob",
                "--home",
                str(self.home),
                "--catalog",
                str(self.catalog),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        events = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
        self.assertEqual(events[0]["event"], "start")
        self.assertEqual(events[-1]["event"], "done")
        self.assertFalse((self.home / ".demo" / "clobbered.1").exists())

    def test_cli_clean_secret_exits_nonzero(self) -> None:
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "ai-janitor"),
                "clean",
                "--yes",
                "--ids",
                "demo-auth",
                "--home",
                str(self.home),
                "--catalog",
                str(self.catalog),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("secret", completed.stderr)
        self.assertTrue((self.home / ".demo" / "auth.json").exists())


if __name__ == "__main__":
    unittest.main()
