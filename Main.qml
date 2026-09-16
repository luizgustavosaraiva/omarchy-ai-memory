import QtQuick
import qs.Commons

// Read-only client for the ai-memory /api/v1 surface.
// Endpoint shapes follow docs/frontend-api.md of akitaonrails/ai-memory:
// workspaces, projects, project overview (handoff + briefing + health),
// FTS5 search, and full page reads. Everything here is GET-only.
Item {
  id: root

  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    if (value === undefined || value === null || value === "") return fallback
    return value
  }

  // ------------------------------------------------------------ config
  readonly property string serverUrl: String(setting("serverUrl", "http://127.0.0.1:49374")).replace(/\/+$/, "")
  readonly property string token: String(setting("token", ""))
  readonly property int pollIntervalSec: {
    var n = Number(setting("pollIntervalSec", 30))
    return isFinite(n) && n >= 5 ? Math.floor(n) : 30
  }
  readonly property string preferredWorkspace: {
    var v = String(setting("preferredWorkspace", "default"))
    return v === "" ? "default" : v
  }
  readonly property string preferredProject: String(setting("preferredProject", ""))

  // ------------------------------------------------------------ state
  property bool online: false
  property bool loading: false
  property string statusText: "connecting…"
  property string lastError: ""
  property var projects: []
  property string activeWorkspace: preferredWorkspace
  property string activeProject: ""
  property var overview: null
  property var hits: []
  property var page: null
  property var pages: []

  readonly property int pagesTotal: pages.length
  readonly property var sortedPages: {
    var list = pages.slice()
    list.sort(function(a, b) {
      return String(b.updated_at || "").localeCompare(String(a.updated_at || ""))
    })
    // Cap the rendered list: the /pages endpoint has no limit param, so a huge
    // wiki would try to build hundreds of rows. Anything older is reachable
    // through FTS search, which hits the full store.
    return list.slice(0, 100)
  }

  readonly property var projectOptions: {
    var list = []
    for (var i = 0; i < projects.length; i++)
      list.push({ value: String(projects[i].project_name), label: String(projects[i].project_name) })
    return list
  }

  readonly property var briefing: overview && overview.briefing ? overview.briefing : null

  // v2.2.x names the page body "body_markdown"; older docs say "body"
  readonly property string pageBody: page ? String(page.body_markdown || page.body || "") : ""
  readonly property var handoff: overview && overview.handoff ? overview.handoff : null
  readonly property var counts: briefing && briefing.counts ? briefing.counts : ({})
  readonly property var recentPages: briefing && briefing.recent_pages ? briefing.recent_pages : []

  // ------------------------------------------------------------ helpers
  function timeAgo(iso) {
    var ms = new Date(String(iso || "")).getTime()
    if (!isFinite(ms)) return ""
    var diff = Date.now() - ms
    if (diff < 0) diff = 0
    var minutes = Math.floor(diff / 60000)
    if (minutes < 1) return "just now"
    if (minutes < 60) return minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"
    var days = Math.floor(hours / 24)
    if (days < 30) return days + "d ago"
    return Math.floor(days / 30) + "mo ago"
  }

  function stripMarks(s) {
    return String(s || "").replace(/<\/?mark>/g, "")
  }

  function clip(s, n) {
    var text = String(s || "")
    return text.length > n ? text.slice(0, n).replace(/\s+\S*$/, "") + "…" : text
  }

  function formatCount(n) {
    n = Number(n) || 0
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "k"
    return String(n)
  }

  // ------------------------------------------------------------ http
  // Security bounds (marketplace baseline): every request has a hard deadline
  // (the XHR is aborted) and responses larger than maxResponseBytes are
  // rejected before parsing — a bad server cannot hang the shell or balloon
  // memory with an unbounded body.
  readonly property int requestTimeoutMs: 8000
  readonly property int maxResponseBytes: 8 * 1024 * 1024
  property int _reqSeq: 0
  property var _pending: ({})

  function request(path, cb) {
    if (root.serverUrl === "") { cb("no server URL configured", null); return }
    var seq = ++_reqSeq
    var xhr = new XMLHttpRequest()
    xhr.open("GET", root.serverUrl + path)
    if (root.token !== "") xhr.setRequestHeader("Authorization", "Bearer " + root.token)
    xhr.setRequestHeader("Accept", "application/json")
    var settled = false
    function finish(err, data) {
      if (settled) return
      settled = true
      delete root._pending[seq]
      cb(err, data)
    }
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || settled) return
      if (xhr.status >= 200 && xhr.status < 300) {
        if (xhr.responseText.length > root.maxResponseBytes) {
          finish("response exceeds size limit (" + root.maxResponseBytes + " bytes)", null)
          return
        }
        try {
          finish(null, JSON.parse(xhr.responseText))
        } catch (e) {
          finish("invalid JSON response", null)
        }
      } else if (xhr.status === 0) {
        finish("connection failed", null)
      } else {
        var message = "HTTP " + xhr.status
        try {
          var body = JSON.parse(xhr.responseText)
          if (body && body.error) message = body.error
        } catch (e) {}
        finish(message, null)
      }
    }
    root._pending[seq] = { xhr: xhr, started: Date.now(), finish: finish }
    try {
      xhr.send()
    } catch (e) {
      finish(String(e), null)
    }
  }

  Timer {
    interval: 500
    running: true
    repeat: true
    onTriggered: {
      var now = Date.now()
      for (var seq in root._pending) {
        var entry = root._pending[seq]
        if (!entry || now - entry.started <= root.requestTimeoutMs) continue
        try { entry.xhr.abort() } catch (e) {}
        entry.finish("request timed out after " + root.requestTimeoutMs + " ms", null)
      }
    }
  }

  // ------------------------------------------------------------ flows
  function refreshAll() {
    loading = true
    request("/api/v1/workspaces", function(err, data) {
      if (err) { setOffline(err); return }
      online = true
      lastError = ""
      statusText = "online"
      loadProjects()
    })
  }

  function setOffline(err) {
    online = false
    loading = false
    statusText = "offline"
    if (err !== undefined && err !== null) lastError = String(err)
    overview = null
    projects = []
    activeProject = ""
    pages = []
  }

  function loadProjects() {
    request("/api/v1/projects?workspace=" + encodeURIComponent(activeWorkspace), function(err, data) {
      if (err) { setOffline(err); return }
      // v2.2.x returns a bare array here; older docs wrap it in {"projects": []}
      var list = Array.isArray(data) ? data : (data && data.projects ? data.projects : [])
      projects = list
      var chosen = ""
      if (preferredProject !== "") {
        for (var i = 0; i < list.length; i++) {
          if (String(list[i].project_name) === preferredProject) { chosen = preferredProject; break }
        }
      }
      if (chosen === "") {
        var bestTime = ""
        for (var j = 0; j < list.length; j++) {
          var t = String(list[j].last_updated || "")
          if (t > bestTime) { bestTime = t; chosen = String(list[j].project_name) }
        }
      }
      activeProject = chosen
      if (chosen !== "") loadOverview()
      else { loading = false; overview = null }
    })
  }

  function loadOverview() {
    var base = "/api/v1/workspaces/" + encodeURIComponent(activeWorkspace)
      + "/projects/" + encodeURIComponent(activeProject)
    request(base + "/overview?limit=8", function(err, data) {
      loading = false
      if (err) { setOffline(err); return }
      online = true
      overview = data
    })
  }

  function selectProject(name) {
    if (name === activeProject) return
    activeProject = name
    overview = null
    hits = []
    page = null
    pages = []
    loading = true
    loadOverview()
  }

  function search(query) {
    var q = String(query || "").trim()
    if (q === "" || activeProject === "") { hits = []; return }
    request("/api/v1/search?q=" + encodeURIComponent(q)
      + "&workspace=" + encodeURIComponent(activeWorkspace)
      + "&project=" + encodeURIComponent(activeProject)
      + "&limit=15", function(err, data) {
      if (err) { lastError = String(err); hits = []; return }
      // v2.2.x returns a bare array here; older docs wrap it in {"hits": []}
      hits = Array.isArray(data) ? data : (data && data.hits ? data.hits : [])
    })
  }

  function loadPage(path) {
    loading = true
    var base = "/api/v1/workspaces/" + encodeURIComponent(activeWorkspace)
      + "/projects/" + encodeURIComponent(activeProject)
    var encoded = String(path || "").split("/").map(function(segment) {
      return encodeURIComponent(segment)
    }).join("/")
    request(base + "/pages/" + encoded, function(err, data) {
      loading = false
      if (err) { lastError = String(err); return }
      page = data
    })
  }

  function loadPages() {
    loading = true
    var base = "/api/v1/workspaces/" + encodeURIComponent(activeWorkspace)
      + "/projects/" + encodeURIComponent(activeProject)
    request(base + "/pages", function(err, data) {
      loading = false
      if (err) { lastError = String(err); pages = []; return }
      // v2.2.x returns a bare array; older docs wrap it in {"pages": []}
      pages = Array.isArray(data) ? data : (data && data.pages ? data.pages : [])
    })
  }

  onSettingsChanged: Qt.callLater(refreshAll)

  Timer {
    interval: root.pollIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }
}
