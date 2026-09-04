<p align="center">
  <h1 align="center">AI Janitor</h1>
</p>

<p align="center">
  扫描并把可回收的 AI 工具数据送进回收站。<br>
  CLI 引擎 + Omarchy 顶栏插件。缓存默认勾选；会话、模型和密钥不会被当成垃圾。
</p>

<p align="center">
  <a href="README.md">English</a>
  ·
  <a href="#安装">安装</a>
  ·
  <a href="#cli">CLI</a>
  ·
  <a href="LICENSE">MIT</a>
</p>

## 这是什么

AI 工具会留下缓存、旧运行时、覆盖残留的配置碎片、已卸 IDE 的数据目录，有时还有本地模型。这个仓库把盘点结果收成：

- **`ai-janitor`**：扫描、dry-run，再 `gio trash`
- **Omarchy 顶栏插件**：显示可回收缓存体积，点开勾选、确认后进回收站

规则在 `catalog.json`。密钥和配置路径写进目录是为了**拒绝删除**，不会出现在可选项里。

删除只走回收站，没有 `rm -rf` 降级。

## 安装

需要已经在跑的 Omarchy Quattro shell，以及 Python 3。

```bash
omarchy plugin add https://github.com/falser101/omarchy-ai-janitor.git --enable
omarchy bar move io.github.falser101.ai-janitor --section right
```

本地开发：

```bash
omarchy plugin add ./omarchy-ai-janitor --enable
```

需要命令行的话：

```bash
ln -s ~/.config/omarchy/plugins/io.github.falser101.ai-janitor/ai-janitor ~/.local/bin/ai-janitor
```

保存 `~/.config/omarchy/plugins/` 下的文件会热重载。若顶栏没有出现：

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.falser101.ai-janitor
```

### 菜单

可选，写入 `~/.config/omarchy/extensions/omarchy-menu.jsonc`：

```jsonc
"setup.ai-janitor": {
  "icon": "󰃢",
  "label": "AI 数据清理",
  "action": "omarchy-shell shell summon io.github.falser101.ai-janitor"
}
```

## CLI

```bash
ai-janitor scan              # 人读表
ai-janitor scan --json       # 插件契约
ai-janitor scan --safe       # 只看缓存
ai-janitor clean --dry-run --safe
ai-janitor clean --ids openclaw-clobbered,codex-tmp --yes
```

不加 `--yes` 就是 dry-run。`--safe` 只清缓存；`--stale` 是已卸工具整目录；`--review` 是会话/模型/记忆。

在 TTY 里且有 `gum` 时走勾选清单。

## 安全

| 档 | 默认 | 含义 |
|---|---|---|
| `cache` | 勾选 | 日志、临时文件、网页缓存、覆盖碎片、旧运行时 |
| `stale` | 不勾 | 已卸工具的整份数据目录 |
| `review` | 不勾 | 会话、Ollama 模型、Hugging Face、记忆库 |
| `secret` / `keep` | 不出现 | 登录态、密钥、当前配置、skills |

路径必须落在 `$HOME` 下。就算命令行写了 `secret`/`keep` 的 id，也会直接拒绝。

## 开发

```bash
python3 tests/test_janitor.py
omarchy plugin validate .
```

## License

MIT
