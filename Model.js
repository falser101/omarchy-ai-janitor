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
    reclaim: zh ? "清理选中" : "Clean selected",
    cleanTab: zh ? "清理本页" : "Clean this tab",
    selectFirst: zh ? "先勾选要删的项" : "Select items first",
    cleanThis: zh ? "清理这项" : "Clean this tool",
    cleaning: zh ? "正在清理…" : "Cleaning…",
    cleaned: zh ? "已清理" : "Cleaned",
    confirm: zh ? "进回收站" : "Move to trash",
    cancel: zh ? "取消" : "Cancel",
    warningReview: zh ? "会话、模型和记忆删了可能找不回。" : "Sessions, models, and memory may be unrecoverable.",
    done: zh ? "已送进回收站" : "Moved to trash",
    error: zh ? "清理失败" : "Clean failed",
    emptyCache: zh ? "没有可回收的缓存" : "No reclaimable cache",
    emptyStale: zh ? "没有已卸工具的数据" : "No leftover tool data",
    emptyReview: zh ? "没有需要确认的数据" : "Nothing in review"
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

function emptyForClass(strings, className) {
  if (className === "cache") return strings.emptyCache
  if (className === "stale") return strings.emptyStale
  if (className === "review") return strings.emptyReview
  return strings.empty
}

function classBytes(report, className) {
  var totals = report && report.totals ? report.totals : {}
  if (className === "cache") return Number(totals.reclaimableCache || 0)
  if (className === "stale") return Number(totals.reclaimableStale || 0)
  if (className === "review") return Number(totals.reclaimableReview || 0)
  return 0
}

function tabModel(strings, report) {
  return [
    { value: "cache", label: strings.cache + "  " + formatBytes(classBytes(report, "cache")) },
    { value: "stale", label: strings.stale + "  " + formatBytes(classBytes(report, "stale")) },
    { value: "review", label: strings.review + "  " + formatBytes(classBytes(report, "review")) }
  ]
}

function groupsForClass(rows, className) {
  var groups = []
  var indexById = {}
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || row.className !== className) continue
    var key = String(row.toolId || "")
    if (indexById[key] === undefined) {
      indexById[key] = groups.length
      groups.push({
        toolId: key,
        toolName: String(row.toolName || key),
        bytes: 0,
        items: []
      })
    }
    var group = groups[indexById[key]]
    group.items.push(row)
    group.bytes += Number(row.bytes || 0)
  }
  groups.sort(function(a, b) { return b.bytes - a.bytes })
  return groups
}

function toolAllSelected(group, selected) {
  var items = group && group.items ? group.items : []
  if (items.length === 0) return false
  for (var i = 0; i < items.length; i++) {
    if (!selected || !selected[items[i].id]) return false
  }
  return true
}

function toolAnySelected(group, selected) {
  var items = group && group.items ? group.items : []
  for (var i = 0; i < items.length; i++) {
    if (selected && selected[items[i].id]) return true
  }
  return false
}

function groupIds(group) {
  var ids = []
  var items = group && group.items ? group.items : []
  for (var i = 0; i < items.length; i++) {
    if (items[i] && items[i].id) ids.push(String(items[i].id))
  }
  return ids
}

function tabIds(groups) {
  var ids = []
  var list = groups || []
  for (var g = 0; g < list.length; g++) {
    var part = groupIds(list[g])
    for (var i = 0; i < part.length; i++) ids.push(part[i])
  }
  return ids
}

function dropItem(report, id) {
  var source = report && typeof report === "object" ? report : emptyReport()
  var next = {
    scannedAt: source.scannedAt || "",
    home: source.home || "",
    totals: { bytes: 0, reclaimableCache: 0, reclaimableStale: 0, reclaimableReview: 0 },
    tools: []
  }
  var tools = Array.isArray(source.tools) ? source.tools : []
  for (var t = 0; t < tools.length; t++) {
    var tool = tools[t]
    var kept = []
    var toolBytes = 0
    var items = Array.isArray(tool.items) ? tool.items : []
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (!item || String(item.id) === String(id)) continue
      kept.push(item)
      var bytes = Number(item.bytes || 0)
      toolBytes += bytes
      next.totals.bytes += bytes
      var klass = String(item.class || item.className || "")
      if (klass === "cache") next.totals.reclaimableCache += bytes
      else if (klass === "stale") next.totals.reclaimableStale += bytes
      else if (klass === "review") next.totals.reclaimableReview += bytes
    }
    if (kept.length === 0) continue
    next.tools.push({
      id: tool.id,
      name: tool.name,
      status: tool.status,
      bytes: toolBytes,
      items: kept
    })
  }
  return next
}

function pruneSelected(selected, rows) {
  var live = {}
  for (var i = 0; i < rows.length; i++) live[rows[i].id] = true
  var next = {}
  if (!selected) return next
  for (var key in selected) {
    if (selected[key] && live[key]) next[key] = true
  }
  return next
}

function progressLabel(strings, state) {
  if (!state) return strings.cleaning
  var label = String(state.currentLabel || "")
  var batchTotal = Number(state.batchTotal || 0)
  var batchDone = Number(state.batchDone || 0)
  if (batchTotal > 1 && label) {
    var pct = Math.max(0, Math.min(100, Math.round(100 * batchDone / batchTotal)))
    return strings.cleaning + " " + label + "  " + pct + "%"
  }
  var total = Number(state.total || 0)
  var done = Number(state.done || 0)
  var head = strings.cleaning
  if (total > 0) head += " " + done + "/" + total
  if (label) head += " · " + label
  return head
}

function bytesForIds(rows, ids) {
  var wanted = {}
  for (var i = 0; i < ids.length; i++) wanted[ids[i]] = true
  var total = 0
  for (var r = 0; r < rows.length; r++) {
    if (wanted[rows[r].id]) total += Number(rows[r].bytes || 0)
  }
  return total
}

function toggleToolSelection(group, selected) {
  var next = {}
  if (selected) {
    for (var key in selected) next[key] = selected[key]
  }
  var all = toolAllSelected(group, selected)
  var items = group && group.items ? group.items : []
  for (var i = 0; i < items.length; i++) next[items[i].id] = !all
  return next
}
