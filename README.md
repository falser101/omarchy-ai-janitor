<p align="center">
  <h1 align="center">AI Janitor</h1>
</p>

<p align="center">
  Scan and trash reclaimable AI-tool data on Omarchy.<br>
  A CLI engine plus a bar widget. Cache is checked by default; sessions, models, and secrets stay out of reach.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/docs-中文-lightgrey.svg" alt="中文"></a>
</p>

<p align="center">
  <a href="README.zh-CN.md">中文</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="#cli">CLI</a>
  ·
  <a href="LICENSE">MIT</a>
</p>

## What this is

AI coding tools leave caches, old runtimes, clobbered config fragments, uninstalled IDE trees, and sometimes local models. This repo turns that inventory into:

- **`ai-janitor`** — scan, dry-run, then `gio trash`
- **Omarchy bar widget** — shows reclaimable cache size; click to pick a class, toggle a tool, expand for per-path detail

The catalog is the source of truth (`catalog.json`). Secret/config paths are listed so they can be *refused*, never offered.

The panel opens on **Cache**. **Uninstalled** and **Review** are separate tabs. Each tool is one row with a master switch; tools with several paths expand for fine selection. Cache items are pre-checked; the other tabs are not.

Deletion always goes to Trash. There is no `rm -rf` fallback.

## Install

Needs Omarchy Quattro shell and Python 3.

```bash
omarchy plugin add https://github.com/falser101/omarchy-ai-janitor.git --enable
omarchy bar move io.github.falser101.ai-janitor --section right
```

From a local checkout while developing:

```bash
omarchy plugin add ./omarchy-ai-janitor --enable
```

Symlink the CLI if you want it on PATH:

```bash
ln -s ~/.config/omarchy/plugins/io.github.falser101.ai-janitor/ai-janitor ~/.local/bin/ai-janitor
```

Saved files under `~/.config/omarchy/plugins/` hot-reload. If the widget is missing:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.falser101.ai-janitor
```

### Menu snippet

Optional row in `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"setup.ai-janitor": {
  "icon": "󰃢",
  "label": "AI data cleanup",
  "action": "omarchy-shell shell summon io.github.falser101.ai-janitor"
}
```

## CLI

```bash
ai-janitor scan              # human table
ai-janitor scan --json       # plugin contract
ai-janitor scan --safe       # cache class only
ai-janitor clean --dry-run --safe
ai-janitor clean --ids openclaw-clobbered,codex-tmp --yes
```

No `--yes` means dry-run. `--safe` is cache only; `--stale` is uninstalled-tool trees; `--review` is sessions/models/memory.

A TTY with `gum` opens a checklist. Escape / no gum prints the table.

## Safety

| Class | Default | Meaning |
|---|---|---|
| `cache` | checked | Logs, tmp, Chromium cache, clobbered fragments, old runtimes |
| `stale` | unchecked | Whole data dirs of uninstalled tools |
| `review` | unchecked | Sessions, Ollama models, Hugging Face, memory palaces |
| `secret` / `keep` | never listed | Auth, credentials, current config, skills |

Paths must stay under `$HOME`. Catalog ids that are `secret` or `keep` fail closed even if you pass `--ids`.

## Development

```bash
python3 tests/test_janitor.py
omarchy plugin validate .
```

## License

MIT
