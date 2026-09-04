function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "K", "M", "G", "T"]
  var index = 0
  while (value >= 1024 && index < units.length - 1) {
    value = value / 1024
    index += 1
  }
  if (index === 0) return Math.round(value) + " B"
  var digits = value >= 10 ? 1 : 1
  return value.toFixed(digits).replace(/\.0$/, "") + units[index]
}

function emptyReport() {
  return {
    scannedAt: "",
    home: "",
    totals: { bytes: 0, reclaimableCache: 0, reclaimableStale: 0, reclaimableReview: 0 },
    tools: []
  }
}

function parseReport(raw) {
  var text = String(raw || "").trim()
  if (text === "") return emptyReport()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return emptyReport()
    parsed.tools = Array.isArray(parsed.tools) ? parsed.tools : []
    parsed.totals = parsed.totals || emptyReport().totals
    return parsed
  } catch (e) {
    return emptyReport()
  }
}

function strings(localeName) {
  var zh = String(localeName || "").toLowerCase().indexOf("zh") === 0
  return {
    zh: zh,
    title: zh ? "AI 清理" : "AI Janitor",
    tooltip: zh ? "可回收的 AI 工具数据" : "Reclaimable AI tool data",
    scanning: zh ? "正在扫描…" : "Scanning…",
    empty: zh ? "没有可回收的数据" : "Nothing reclaimable",
    cache: zh ? "缓存" : "Cache",
    stale: zh ? "已卸工具" : "Uninstalled",
    review: zh ? "需确认" : "Review",
    reclaim: zh ? "回收选中项" : "Reclaim selected",
    confirm: zh ? "进回收站" : "Move to trash",
    cancel: zh ? "取消" : "Cancel",
    warningReview: zh ? "会话、模型和记忆删了可能找不回。" : "Sessions, models, and memory may be unrecoverable.",
    done: zh ? "已送进回收站" : "Moved to trash",
    error: zh ? "清理失败" : "Clean failed"
  }
}

function flattenItems(report) {
  var rows = []
  var tools = report && Array.isArray(report.tools) ? report.tools : []
  for (var t = 0; t < tools.length; t++) {
    var tool = tools[t]
    var items = Array.isArray(tool.items) ? tool.items : []
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (!item || !item.id) continue
      if (item.class === "secret" || item.class === "keep") continue
      rows.push({
        id: String(item.id),
        toolId: String(tool.id || ""),
        toolName: String(tool.name || tool.id || ""),
        className: String(item.class || ""),
        summary: String(item.summary || item.id),
        summaryZh: String(item.summary_zh || item.summary || item.id),
        path: String(item.path || ""),
        bytes: Number(item.bytes || 0),
        count: Number(item.count || 0)
      })
    }
  }
  return rows
}

function defaultSelected(rows) {
  var selected = {}
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].className === "cache") selected[rows[i].id] = true
  }
  return selected
}

function selectedList(selected) {
  var ids = []
  if (!selected) return ids
  for (var key in selected) {
    if (selected[key]) ids.push(key)
  }
  return ids
}

function selectedBytes(rows, selected) {
  var total = 0
  for (var i = 0; i < rows.length; i++) {
    if (selected && selected[rows[i].id]) total += Number(rows[i].bytes || 0)
  }
  return total
}

function barBytes(report) {
  var totals = report && report.totals ? report.totals : {}
  var cache = Number(totals.reclaimableCache || 0)
  if (cache > 0) return cache
  return Number(totals.reclaimableStale || 0)
}

function classLabel(strings, className) {
  if (className === "cache") return strings.cache
  if (className === "stale") return strings.stale
  if (className === "review") return strings.review
  return className
}
