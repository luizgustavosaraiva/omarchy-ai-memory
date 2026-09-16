import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

// AI Memory — bar widget + panel for the ai-memory wiki
// (github.com/akitaonrails/ai-memory). Mirrors the built-in web UI:
// open handoff, wiki stats, recent pages, FTS search, and page reading.
Panel {
  id: root
  moduleName: "luizgustavosaraiva.ai-memory"
  ipcTarget: "luizgustavosaraiva.ai-memory"
  manageIpc: false

  // ------------------------------------------------------------ theme
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool cursorActive: false
  property string view: "home" // "home" | "pages" | "page"

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  function openWebUi() {
    // Deep link: open page → project → web root.
    // Built-in web UI routes: /web/w/{ws}/{project} and /web/w/{ws}/{project}/p/{path}
    var url = memory.serverUrl + "/web"
    if (memory.activeWorkspace !== "" && memory.activeProject !== "")
      url += "/w/" + encodeURIComponent(memory.activeWorkspace) + "/" + encodeURIComponent(memory.activeProject)
    if (root.view === "page" && memory.page && String(memory.page.path || "") !== "")
      url += "/p/" + String(memory.page.path).split("/").map(function(segment) {
        return encodeURIComponent(segment)
      }).join("/")
    if (!Qt.openUrlExternally(url) && root.bar)
      root.bar.run("omarchy-notification-send \"AI Memory: could not open browser for " + url + "\"")
    root.close()
  }

  function openPages() {
    memory.loadPages()
    root.view = "pages"
    contentFlick.contentY = 0
  }

  function openPage(path) {
    memory.loadPage(path)
    root.view = "page"
    contentFlick.contentY = 0
  }

  readonly property string barTooltip: {
    if (!memory.online) return "AI Memory — offline · " + memory.serverUrl
    var text = "AI Memory · " + memory.activeWorkspace + "/"
      + (memory.activeProject !== "" ? memory.activeProject : "—")
    var stats = []
    if (memory.counts.pages_latest !== undefined) stats.push(memory.formatCount(memory.counts.pages_latest) + " pages")
    if (memory.counts.sessions !== undefined) stats.push(memory.formatCount(memory.counts.sessions) + " sessions")
    if (memory.counts.observations !== undefined) stats.push(memory.formatCount(memory.counts.observations) + " observations")
    if (stats.length > 0) text += "\n" + stats.join(" · ")
    if (memory.handoff) text += "\nHandoff pending from " + memory.handoff.agent
    return text
  }

  function statRows() {
    if (!memory.briefing) return []
    var counts = memory.counts
    var week = memory.briefing.activity_7d || {}
    return [
      { label: "pages", value: memory.formatCount(counts.pages_latest) },
      { label: "sessions", value: memory.formatCount(counts.sessions) },
      { label: "observations", value: memory.formatCount(counts.observations) },
      { label: "7d obs", value: memory.formatCount(week.observations) }
    ]
  }

  // ------------------------------------------------------------ api client
  Main {
    id: memory
    settings: root.settings
  }

  // ------------------------------------------------------------ bar widget
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (root.view === "page" && !memory.page) root.view = "home"
    memory.refreshAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Timer {
    id: searchDebounce
    interval: 400
    onTriggered: memory.search(searchField.text)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { memory.refreshAll(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰧑"
    active: memory.online && memory.handoff !== null
    tooltipText: root.barTooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openWebUi()
      else if (buttonCode === Qt.MiddleButton) memory.refreshAll()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------ popup
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx < 0 && root.view !== "home") { root.view = "home"; return }
        if (dy !== 0)
          contentFlick.contentY = root.clamp(contentFlick.contentY + dy * Style.space(56), 0,
            Math.max(0, contentFlick.contentHeight - contentFlick.height))
      }
      onActivateRequested: memory.refreshAll()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") memory.refreshAll() }
    }

    Flickable {
      id: contentFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: contentColumn
        width: contentFlick.width
        spacing: Style.space(12)

        // ---------- hero
        PanelHero {
          width: parent.width
          title: "AI Memory"
          meta: !memory.online ? "offline · " + memory.serverUrl
            : memory.activeProject === "" ? "no projects in this workspace yet"
            : memory.activeWorkspace + "/" + memory.activeProject + (memory.loading ? " · refreshing…" : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: memory.online ? 1.0 : 0.45
          iconComponent: Component {
            Item {
              width: Style.font.display
              height: Style.font.display
              Text {
                anchors.centerIn: parent
                text: "󰧑"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }
        }

        // ---------- offline card
        BorderSurface {
          visible: !memory.online
          width: parent.width
          implicitHeight: offlineColumn.implicitHeight + Style.space(20)
          color: root.alpha(root.urgent, 0.10)
          borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
          radius: Style.cornerRadius

          Column {
            id: offlineColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.topMargin: Style.space(10)
            spacing: Style.space(4)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "ai-memory server not reachable at " + memory.serverUrl
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: memory.lastError !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: memory.lastError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Start it:  ai-memory serve --transport http --bind "
                + memory.serverUrl.replace(/^https?:\/\//, "") + " --enable-web"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        // ---------- home view
        Column {
          visible: root.view === "home"
          width: parent.width
          spacing: Style.space(12)

          // project picker (scales to any number of projects)
          Column {
            visible: memory.projects.length > 1
            width: parent.width
            spacing: Style.space(6)

            SearchableDropdown {
              width: parent.width
              label: "Project"
              value: memory.activeProject
              options: memory.projectOptions
              fontFamily: root.fontFamily
              foreground: root.foreground
              hasCursor: root.cursorActive
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              onChanged: function(value) { memory.selectProject(value) }
            }
          }

          // open handoff
          BorderSurface {
            visible: memory.handoff !== null
            width: parent.width
            implicitHeight: handoffInner.implicitHeight + Style.space(20)
            color: root.alpha(root.foreground, 0.05)
            borderSpec: Border.flat(root.alpha(root.accent, 0.45), 1)
            radius: Style.cornerRadius

            Column {
              id: handoffInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              anchors.topMargin: Style.space(10)
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: handoffBadge.implicitHeight

                Text {
                  id: handoffBadge
                  text: "OPEN HANDOFF"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1
                }

                Text {
                  anchors.right: parent.right
                  textFormat: Text.PlainText
                  text: memory.handoff ? String(memory.handoff.agent || "") + " · " + memory.timeAgo(memory.handoff.at) : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: memory.handoff ? memory.clip(memory.handoff.summary, 600) : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Column {
                visible: memory.handoff && (memory.handoff.open_questions || []).length > 0
                width: parent.width
                spacing: Style.space(2)

                Text {
                  text: "Open questions"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: memory.handoff ? (memory.handoff.open_questions || []) : []

                  Text {
                    required property var modelData
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "• " + String(modelData)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }

              Column {
                visible: memory.handoff && (memory.handoff.next_steps || []).length > 0
                width: parent.width
                spacing: Style.space(2)

                Text {
                  text: "Next steps"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: memory.handoff ? (memory.handoff.next_steps || []) : []

                  Text {
                    required property var modelData
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "• " + String(modelData)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }

          // wiki stats
          Column {
            visible: memory.briefing !== null
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              width: parent.width
              text: "WIKI STATS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(28)

              Repeater {
                model: root.statRows()

                StatBlock {
                  required property var modelData
                  label: modelData.label
                  value: modelData.value
                }
              }
            }
          }

          // pages + browser buttons
          Row {
            visible: memory.online && memory.activeProject !== ""
            spacing: Style.space(8)

            Button {
              text: "View pages"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openPages()
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
            }

            Button {
              text: "Open web UI ↗"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openWebUi()
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
            }
          }

          // search + results
          Column {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: searchField
              width: parent.width
              placeholderText: "Search memory…"
              foreground: root.foreground
              hasCursor: root.cursorActive
              font.family: root.fontFamily
              onTextChanged: {
                if (text.trim().length >= 2) searchDebounce.restart()
                else memory.hits = []
              }
              onAccepted: {
                searchDebounce.stop()
                memory.search(text)
              }
              Keys.onEscapePressed: {
                text = ""
                memory.hits = []
                root.close()
              }
            }

            Column {
              visible: memory.hits.length > 0
              width: parent.width
              spacing: Style.space(2)

              PanelSectionHeader {
                width: parent.width
                text: "RESULTS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: memory.hits

                WikiRow {
                  required property var modelData
                  width: parent.width
                  title: String(modelData.title || modelData.path || "")
                  meta: String(modelData.path || "")
                  snippet: memory.stripMarks(modelData.snippet)
                  onRowClicked: root.openPage(String(modelData.path))
                }
              }
            }
          }

          // recent pages
          Column {
            visible: memory.hits.length === 0 && memory.recentPages.length > 0
            width: parent.width
            spacing: Style.space(2)

            PanelSectionHeader {
              width: parent.width
              text: "RECENT PAGES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: memory.recentPages

              WikiRow {
                required property var modelData
                width: parent.width
                title: String(modelData.title || modelData.path || "")
                meta: String(modelData.kind || "")
                  + (modelData.updated_at ? " · " + memory.timeAgo(modelData.updated_at) : "")
                snippet: ""
                onRowClicked: root.openPage(String(modelData.path))
              }
            }
          }
        }

        // ---------- pages listing view
        Column {
          visible: root.view === "pages"
          width: parent.width
          spacing: Style.space(10)

          Row {
            spacing: Style.space(8)

            Button {
              text: "← Back"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.view = "home"
                contentFlick.contentY = 0
              }
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
            }

            Button {
              text: "Open web UI ↗"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openWebUi()
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
            }
          }

          PanelSectionHeader {
            width: parent.width
            text: memory.pagesTotal > memory.sortedPages.length
              ? "PAGES (showing " + memory.sortedPages.length + " of " + memory.pagesTotal + ", newest first)"
              : "PAGES (" + memory.pagesTotal + ")"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: memory.sortedPages

            WikiRow {
              required property var modelData
              width: parent.width
              title: String(modelData.title || modelData.path || "")
              meta: String(modelData.kind || "")
                + (modelData.updated_at ? " · " + memory.timeAgo(modelData.updated_at) : "")
                + "  ·  " + String(modelData.path || "")
              snippet: ""
              onRowClicked: root.openPage(String(modelData.path))
            }
          }
        }

        // ---------- page view
        Column {
          visible: root.view === "page"
          width: parent.width
          spacing: Style.space(10)

          Row {
            spacing: Style.space(8)

            Button {
              text: "← Back"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                root.view = "home"
                memory.page = null
                contentFlick.contentY = 0
              }
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
            }

            Button {
              text: "Wiki ↗"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openWebUi()
              onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: memory.page ? String(memory.page.title || memory.page.path || "") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: memory.page
              ? [String(memory.page.kind || ""), memory.page.updated_at ? "updated " + memory.timeAgo(memory.page.updated_at) : ""]
                .filter(function(part) { return part !== "" }).join(" · ")
              : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { foreground: root.foreground }

          Text {
            width: parent.width
            textFormat: Text.MarkdownText
            text: memory.pageBody
            color: root.foreground
            linkColor: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            // Security (marketplace baseline): page bodies are server-controlled.
            // Only http/https links may leave the panel — never file:, exec:,
            // javascript: or any other scheme embedded in wiki markdown.
            onLinkActivated: function(link) {
              var scheme = String(link).split(":")[0].toLowerCase()
              if (scheme === "http" || scheme === "https") Qt.openUrlExternally(link)
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components
  component StatBlock: Column {
    id: statBlock
    property string label: ""
    property string value: ""
    spacing: Style.space(1)

    Text {
      textFormat: Text.PlainText
      text: statBlock.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      text: statBlock.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component WikiRow: Item {
    id: wikiRow
    property string title: ""
    property string meta: ""
    property string snippet: ""
    signal rowClicked()

    implicitHeight: wikiRowColumn.implicitHeight + Style.space(12)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: rowHover.containsMouse ? root.alpha(root.foreground, 0.06) : "transparent"
    }

    Column {
      id: wikiRowColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: wikiRow.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        visible: wikiRow.meta !== ""
        textFormat: Text.PlainText
        width: parent.width
        text: wikiRow.meta
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        visible: wikiRow.snippet !== ""
        textFormat: Text.PlainText
        width: parent.width
        text: wikiRow.snippet
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: rowHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: wikiRow.rowClicked()
    }
  }
}
