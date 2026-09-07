import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool loading: false
  property bool cleaning: false
  property string lastError: ""
  property string actionStatus: ""
  property var report: Model.emptyReport()
  property int reportRevision: 0

  property int cleanTotal: 0
  property int cleanDone: 0
  property string cleanCurrentId: ""
  property string cleanCurrentLabel: ""
  property string cleanCurrentTool: ""
  property int batchDone: 0
  property int batchTotal: 0
  property double lastFreedBytes: 0

  readonly property var totals: report && report.totals ? report.totals : Model.emptyReport().totals
  readonly property double cacheBytes: Number(totals.reclaimableCache || 0)
  readonly property double staleBytes: Number(totals.reclaimableStale || 0)
  readonly property double reviewBytes: Number(totals.reclaimableReview || 0)
  readonly property double barBytes: Model.barBytes(report)
  readonly property bool busy: scanProcess.running || cleanProcess.running
  readonly property real cleanProgress: {
    var total = Number(root.cleanTotal || 0)
    if (total <= 0) return root.cleaning ? 0.08 : 0
    var itemPart = Number(root.cleanDone || 0)
    if (root.batchTotal > 1)
      itemPart += Math.min(0.99, Number(root.batchDone || 0) / Number(root.batchTotal))
    return Math.max(0, Math.min(1, itemPart / total))
  }

  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) {
      var path = decodeURIComponent(url.substring(7))
      while (path.length > 1 && path.charAt(path.length - 1) === "/")
        path = path.substring(0, path.length - 1)
      return path
    }
    return url
  }
  readonly property string helperPath: root.pluginDir + "/ai-janitor"

  property string _scanOut: ""
  property string _scanErr: ""
  property string _cleanErr: ""
  property bool _silentScan: false
  property bool _gotDoneEvent: false

  function refresh(fresh, silent) {
    if (scanProcess.running) return
    _scanOut = ""
    _scanErr = ""
    if (!silent) lastError = ""
    loading = silent !== true
    _silentScan = silent === true
    var args = ["python3", helperPath, "scan", "--json"]
    if (fresh) args.push("--fresh")
    scanProcess.command = args
    scanProcess.running = true
  }

  function cleanIds(ids) {
    if (cleanProcess.running || !ids || ids.length === 0) return
    _cleanErr = ""
    lastError = ""
    actionStatus = ""
    cleaning = true
    _gotDoneEvent = false
    cleanTotal = ids.length
    cleanDone = 0
    cleanCurrentId = ""
    cleanCurrentLabel = ""
    cleanCurrentTool = ""
    batchDone = 0
    batchTotal = 0
    lastFreedBytes = 0
    cleanProcess.command = ["python3", "-u", helperPath, "clean", "--yes", "--progress", "--ids", ids.join(",")]
    cleanProcess.running = true
  }

  function applyReport(raw) {
    report = Model.parseReport(raw)
    reportRevision += 1
  }

  function dropCleanedItem(id) {
    if (!id) return
    report = Model.dropItem(report, id)
    reportRevision += 1
  }

  function resetCleanState() {
    cleaning = false
    cleanCurrentId = ""
    cleanCurrentLabel = ""
    cleanCurrentTool = ""
    batchDone = 0
    batchTotal = 0
  }

  function handleProgress(line) {
    var text = String(line || "").trim()
    if (text === "") return
    var ev = null
    try { ev = JSON.parse(text) } catch (e) { return }
    if (!ev || typeof ev !== "object") return
    var kind = String(ev.event || "")
    if (kind === "start") {
      cleanTotal = Number(ev.count || cleanTotal || 0)
      lastFreedBytes = Number(ev.bytes || 0)
      return
    }
    if (kind === "item") {
      cleanCurrentId = String(ev.id || "")
      cleanCurrentLabel = String(ev.summary || ev.id || "")
      cleanCurrentTool = String(ev.tool || "")
      if (String(ev.status || "") === "start") {
        batchDone = 0
        batchTotal = Number(ev.count || 0)
      } else if (String(ev.status || "") === "done") {
        cleanDone += 1
        batchDone = 0
        batchTotal = 0
        dropCleanedItem(ev.id)
      }
      return
    }
    if (kind === "batch") {
      if (ev.id) cleanCurrentId = String(ev.id)
      batchDone = Number(ev.done || 0)
      batchTotal = Number(ev.total || 0)
      return
    }
    if (kind === "done") {
      _gotDoneEvent = true
      lastFreedBytes = Number(ev.bytes || lastFreedBytes)
      actionStatus = "ok"
      return
    }
    if (kind === "error") {
      lastError = String(ev.message || "clean failed")
      actionStatus = ""
    }
  }

  Process {
    id: scanProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: scanStdout
      waitForEnd: true
      onStreamFinished: root._scanOut = text
    }
    stderr: StdioCollector {
      id: scanStderr
      waitForEnd: true
      onStreamFinished: root._scanErr = text
    }
    onExited: function(exitCode) {
      root.loading = false
      var stdout = String(scanStdout.text || root._scanOut || "")
      var stderr = String(scanStderr.text || root._scanErr || "")
      if (exitCode === 0) {
        root.applyReport(stdout)
        if (!root._silentScan) root.lastError = ""
      } else if (!root._silentScan) {
        root.lastError = String(stderr || stdout || "scan failed").trim()
      }
      root._silentScan = false
    }
  }

  Process {
    id: cleanProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(data) { root.handleProgress(data) }
    }
    stderr: StdioCollector {
      id: cleanStderr
      waitForEnd: true
      onStreamFinished: root._cleanErr = text
    }
    onExited: function(exitCode) {
      var stderr = String(cleanStderr.text || root._cleanErr || "")
      if (exitCode === 0) {
        if (!root._gotDoneEvent) root.actionStatus = "ok"
        root.lastError = ""
        root.resetCleanState()
        root.refresh(true, true)
      } else {
        root.resetCleanState()
        if (root.lastError === "")
          root.lastError = String(stderr || "clean failed").trim()
        root.actionStatus = ""
        root.refresh(true, true)
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: Math.max(30, parseInt(String(root.settings && root.settings.refreshIntervalSec ? root.settings.refreshIntervalSec : 600), 10) || 600) * 1000
    repeat: true
    running: true
    onTriggered: if (!root.cleaning) root.refresh(false, true)
  }

  Component.onCompleted: root.refresh(false)
}
