#!/usr/bin/env node
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8")
const ctx = {}
vm.createContext(ctx)
vm.runInContext(source, ctx)

const rows = [
  { id: "a1", toolId: "grok", toolName: "Grok", className: "cache", bytes: 100, summary: "mem", summaryZh: "mem", path: "~/.grok/memtrace" },
  { id: "a2", toolId: "grok", toolName: "Grok", className: "cache", bytes: 50, summary: "dl", summaryZh: "dl", path: "~/.grok/downloads" },
  { id: "b1", toolId: "trae", toolName: "Trae", className: "stale", bytes: 200, summary: "dir", summaryZh: "dir", path: "~/.trae" },
  { id: "c1", toolId: "grok", toolName: "Grok", className: "review", bytes: 9, summary: "sessions", summaryZh: "sessions", path: "~/.grok/sessions" }
]

const cache = ctx.groupsForClass(rows, "cache")
if (cache.length !== 1) throw new Error("cache should collapse to one tool")
if (cache[0].items.length !== 2) throw new Error("grok cache should have two items")
if (cache[0].bytes !== 150) throw new Error("grok cache bytes")

const selected = ctx.defaultSelected(rows)
if (!selected.a1 || !selected.a2) throw new Error("cache prechecked")
if (selected.b1 || selected.c1) throw new Error("non-cache must stay unchecked")

const after = ctx.toggleToolSelection(cache[0], selected)
if (after.a1 || after.a2) throw new Error("toggling all-on should clear")

const again = ctx.toggleToolSelection(cache[0], after)
if (!again.a1 || !again.a2) throw new Error("toggling all-off should select")

console.log("ok")
