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

  readonly property var totals: report && report.totals ? report.totals : Model.emptyReport().totals
  readonly property double cacheBytes: Number(totals.reclaimableCache || 0)
  readonly property double staleBytes: Number(totals.reclaimableStale || 0)
  readonly property double reviewBytes: Number(totals.reclaimableReview || 0)
  readonly property double barBytes: Model.barBytes(report)
  readonly property bool busy: scanProcess.running || cleanProcess.running

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
  property string _cleanOut: ""
  property string _cleanErr: ""

  function refresh(fresh) {
    if (scanProcess.running) return
    _scanOut = ""
    _scanErr = ""
    lastError = ""
    loading = true
    var args = ["python3", helperPath, "scan", "--json"]
    if (fresh) args.push("--fresh")
    scanProcess.command = args
    scanProcess.running = true
  }

  function cleanIds(ids) {
    if (cleanProcess.running || !ids || ids.length === 0) return
    _cleanOut = ""
    _cleanErr = ""
    lastError = ""
    actionStatus = ""
    cleaning = true
    cleanProcess.command = ["python3", helperPath, "clean", "--yes", "--json", "--ids", ids.join(",")]
    cleanProcess.running = true
  }

  function applyReport(raw) {
    report = Model.parseReport(raw)
    reportRevision += 1
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
        root.lastError = ""
      } else {
        root.lastError = String(stderr || stdout || "scan failed").trim()
      }
    }
  }

  Process {
    id: cleanProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: cleanStdout
      waitForEnd: true
      onStreamFinished: root._cleanOut = text
    }
    stderr: StdioCollector {
      id: cleanStderr
      waitForEnd: true
      onStreamFinished: root._cleanErr = text
    }
    onExited: function(exitCode) {
      root.cleaning = false
      var stdout = String(cleanStdout.text || root._cleanOut || "")
      var stderr = String(cleanStderr.text || root._cleanErr || "")
      if (exitCode === 0) {
        root.lastError = ""
        root.actionStatus = "ok"
        root.refresh(true)
      } else {
        root.lastError = String(stderr || stdout || "clean failed").trim()
        root.actionStatus = ""
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: Math.max(30, parseInt(String(root.settings && root.settings.refreshIntervalSec ? root.settings.refreshIntervalSec : 600), 10) || 600) * 1000
    repeat: true
    running: true
    onTriggered: root.refresh(false)
  }

  Component.onCompleted: root.refresh(false)
}
