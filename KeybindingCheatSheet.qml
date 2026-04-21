import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 200
    minHeight: 120

    // ── Settings ───────────────────────────────────────────────────────────────
    readonly property string compositor: pluginData.compositor || "hyprland"
    readonly property int    numColumns: Math.max(1, Math.min(5, parseInt(pluginData.columns) || 1))
    readonly property real   bgOpacity:       Math.max(0, Math.min(1, (pluginData.backgroundOpacity ?? 70) / 100))
    readonly property real   fontScale:       Math.max(0.5, Math.min(2.0, (pluginData.fontScale ?? 100) / 100))
    readonly property string editorCommand: (pluginData.editorCommand || "code").trim() !== "" ? pluginData.editorCommand.trim() : "code"
    readonly property string customBindingFilePath: (pluginData.bindingFilePath || "").trim()
    readonly property color  accentColor: {
        var mode = pluginData.accentColorMode || "primary"
        if (mode === "secondary") return Theme.secondary
        if (mode === "custom") {
            var c = pluginData.accentColorCustom || ""
            if (c !== "") return c
        }
        return Theme.primary
    }
    readonly property var hiddenSections: {
        try { return JSON.parse(pluginData.hiddenSections || "[]") } catch(e) { return [] }
    }

    // ── Runtime state ──────────────────────────────────────────────────────────
    property var    sections:   []
    property bool   loading:    true
    property string parseError: ""
    property var    collapsedSections: []

    readonly property var sectionOrder: {
        try { return JSON.parse(pluginData.sectionOrder || "[]") } catch(e) { return [] }
    }

    function defaultBindingPath(compositor) {
        if (compositor === "hyprland") return "~/.config/hypr/dms/binds.conf"
        if (compositor === "mangowc") return "~/.config/mango/config.conf"
        if (compositor === "scroll") return "~/.config/scroll/config.conf"
        if (compositor === "miracle") return "~/.config/miracle/config.conf"
        if (compositor === "sway") return "~/.config/sway/config"
        if (compositor === "niri") return "~/.config/niri/config.kdl"
        return ""
    }

    readonly property string bindingFilePath:
        customBindingFilePath !== "" ? customBindingFilePath : defaultBindingPath(root.compositor)

    function isSectionCollapsed(sectionId) {
        return (root.collapsedSections || []).indexOf(sectionId) !== -1
    }

    function toggleSection(sectionId) {
        var collapsed = (root.collapsedSections || []).slice()
        var idx = collapsed.indexOf(sectionId)
        if (idx === -1) collapsed.push(sectionId)
        else collapsed.splice(idx, 1)
        root.collapsedSections = collapsed
    }

    function visibleSectionIds() {
        var ids = []
        var hidden = root.hiddenSections || []
        var secs = root.sections || []
        for (var i = 0; i < secs.length; i++) {
            if (hidden.indexOf(secs[i].id) === -1)
                ids.push(secs[i].id)
        }
        return ids
    }

    function collapseAllSections() {
        root.collapsedSections = visibleSectionIds()
    }

    function expandAllSections() {
        root.collapsedSections = []
    }

    function shellQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\"'\"'") + "'"
    }

    function shellPathArg(path) {
        var p = String(path || "")
        if (p.indexOf("~/") === 0)
            return '"${HOME}/' + p.slice(2).replace(/(["\\$`])/g, "\\$1") + '"'
        return shellQuote(p)
    }

    function openBindingFile() {
        if (root.bindingFilePath === "") return
        openEditorProcess.command = [
            "sh",
            "-lc",
            root.editorCommand + " " + shellPathArg(root.bindingFilePath)
        ]
        if (openEditorProcess.running)
            openEditorProcess.running = false
        Qt.callLater(function() { openEditorProcess.running = true })
    }

    // Build section lists and split them across N columns.
    readonly property var columnData: {
        try {
            var secs   = root.sections       || []
            var hidden = root.hiddenSections  || []
            var order  = root.sectionOrder    || []
            var n      = root.numColumns

            // Sort sections: ordered IDs first, then remaining in parse order
            var ordered = []
            var secById = {}
            for (var s = 0; s < secs.length; s++) secById[secs[s].id] = secs[s]

            for (var o = 0; o < order.length; o++) {
                if (secById[order[o]]) ordered.push(secById[order[o]])
            }
            for (var s2 = 0; s2 < secs.length; s2++) {
                if (order.indexOf(secs[s2].id) === -1) ordered.push(secs[s2])
            }

            // Keep sections intact so headers and bindings stay together.
            var flat = []
            for (var i = 0; i < ordered.length; i++) {
                if (hidden.indexOf(ordered[i].id) !== -1) continue
                flat.push({
                    id: ordered[i].id,
                    name: ordered[i].name,
                    bindings: ordered[i].bindings || []
                })
            }

            // Split sections evenly across columns.
            var perCol = Math.ceil(flat.length / n)
            var cols   = []
            for (var c = 0; c < n; c++) {
                cols.push(flat.slice(c * perCol, (c + 1) * perCol))
            }
            return cols
        } catch(e) {
            return [[]]
        }
    }

    readonly property bool hasContent:
        columnData.some(col => col && col.length > 0)

    Component.onCompleted: reload()
    onCompositorChanged:   reload()

    function reload() {
        parseError = ""
        loading    = true
        if (parserProcess.running)
            parserProcess.running = false
        Qt.callLater(function() { parserProcess.running = true })
    }

    // ── Parser process ─────────────────────────────────────────────────────────
    Process {
        id: parserProcess
        command: ["dms", "keybinds", "show", root.compositor]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text)
                    if (parsed.error) {
                        root.parseError = parsed.error
                        root.sections   = []
                    } else {
                        var binds = parsed.binds || {}
                        var secs  = []
                        for (var catName in binds) {
                            var id = catName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
                            secs.push({
                                id: id,
                                name: catName,
                                bindings: binds[catName].map(function(b) { return { key: b.key, description: b.desc } })
                            })
                        }
                        root.sections   = secs
                        root.parseError = ""
                    }
                } catch(e) {
                    root.parseError = "JSON parse failed: " + e
                    root.sections   = []
                }
                root.loading = false
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0 && root.loading) {
                root.parseError = "dms exited with code " + exitCode
                root.loading    = false
            }
        }
    }

    Process {
        id: openEditorProcess
    }

    // ── Background ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:   Theme.surfaceContainer
        opacity: root.bgOpacity
        radius:  Theme.cornerRadius
    }

    // ── Content ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingS

        // Header row
        RowLayout {
            Layout.fillWidth: true

            DankIcon {
                name:  "keyboard"
                size:  Theme.iconSize
                color: root.accentColor
            }

            StyledText {
                text: "Keybindings"
                font.pixelSize: Theme.fontSizeMedium * root.fontScale
                font.bold: true
                color: Theme.surfaceText
            }

            Rectangle {
                visible: root.hasContent
                height: 22
                width: 72
                radius: Theme.cornerRadius / 2
                color: collapseAllHover.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)

                StyledText {
                    anchors.centerIn: parent
                    text: "Collapse"
                    color: root.accentColor
                    font.pixelSize: (Theme.fontSizeSmall - 2) * root.fontScale
                    font.bold: true
                }

                HoverHandler { id: collapseAllHover }
                TapHandler { onTapped: root.collapseAllSections() }
            }

            Rectangle {
                visible: root.hasContent
                height: 22
                width: 64
                radius: Theme.cornerRadius / 2
                color: expandAllHover.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)

                StyledText {
                    anchors.centerIn: parent
                    text: "Expand"
                    color: root.accentColor
                    font.pixelSize: (Theme.fontSizeSmall - 2) * root.fontScale
                    font.bold: true
                }

                HoverHandler { id: expandAllHover }
                TapHandler { onTapped: root.expandAllSections() }
            }

            Rectangle {
                visible: root.bindingFilePath !== ""
                width: 22; height: 22
                radius: Theme.cornerRadius / 2
                color: openFileHover.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)

                DankIcon {
                    anchors.centerIn: parent
                    name: "edit"
                    size: 14
                    color: root.accentColor
                }

                HoverHandler { id: openFileHover }
                TapHandler { onTapped: root.openBindingFile() }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 20; height: 20
                radius: Theme.cornerRadius / 2
                color: refreshHover.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15) : "transparent"

                DankIcon {
                    anchors.centerIn: parent
                    name: "refresh"
                    size: 14
                    color: root.accentColor
                }

                HoverHandler { id: refreshHover }
                TapHandler { onTapped: root.reload() }
            }

            StyledText {
                text: root.compositor.toUpperCase()
                font.pixelSize: (Theme.fontSizeSmall - 1) * root.fontScale
                font.letterSpacing: 1.2
                color: root.accentColor
            }

            Rectangle {
                width: 6; height: 6; radius: 3
                color: root.loading    ? Theme.warning
                     : root.parseError ? Theme.error
                                       : root.accentColor
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.3)
        }

        // Loading / error / empty
        Item {
            visible: root.loading || !root.hasContent
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL
                text: root.loading      ? "Parsing…"
                    : root.parseError   ? "Could not parse config.\nCheck compositor and path in settings."
                                        : "No keybinds found for " + root.compositor + "."
                color: (!root.loading && root.parseError) ? Theme.error : Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall * root.fontScale
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Columns
        Item {
            visible: !root.loading && root.hasContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                id: colFlickable
                anchors.fill: parent
                contentWidth: width
                contentHeight: colRow.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Row {
                    id: colRow
                    width: colFlickable.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: root.columnData

                        delegate: Column {
                            id: colDelegate
                            required property var modelData   // section array for this column
                            required property int index

                            width: {
                                try {
                                    var n = root.columnData ? root.columnData.length : 1
                                    if (n < 1) n = 1
                                    return (colRow.width - (n - 1) * Theme.spacingS) / n
                                } catch(e) { return colRow.width }
                            }
                            spacing: 3

                            Repeater {
                                model: colDelegate.modelData || []

                                delegate: Column {
                                    required property var modelData
                                    required property int index
                                    width: colDelegate.width
                                    spacing: 3

                                    Rectangle {
                                        width: parent.width
                                        height: 28
                                        radius: Theme.cornerRadius / 2
                                        color: headerHover.containsMouse ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12) : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)

                                        HoverHandler { id: headerHover }
                                        TapHandler { onTapped: root.toggleSection(modelData.id) }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.spacingS
                                            anchors.rightMargin: Theme.spacingS
                                            spacing: Theme.spacingS

                                            DankIcon {
                                                name: root.isSectionCollapsed(modelData.id) ? "keyboard_arrow_right" : "keyboard_arrow_down"
                                                size: 16
                                                color: root.accentColor
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                text: (modelData.name || "").toUpperCase()
                                                color: root.accentColor
                                                font.pixelSize: (Theme.fontSizeSmall - 1) * root.fontScale
                                                font.bold: true
                                                font.letterSpacing: 0.8
                                            }

                                            StyledText {
                                                text: modelData.bindings.length + " bindings"
                                                color: Theme.surfaceVariantText
                                                font.pixelSize: (Theme.fontSizeSmall - 2) * root.fontScale
                                            }
                                        }
                                    }

                                    Column {
                                        visible: !root.isSectionCollapsed(modelData.id)
                                        width: parent.width
                                        spacing: 3

                                        Repeater {
                                            model: modelData.bindings || []

                                            delegate: Item {
                                                required property var modelData
                                                width: parent.width
                                                height: 24

                                                readonly property real keyW: Math.floor(width * 0.38)

                                                Rectangle {
                                                    id: keyRect
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.left: parent.left
                                                    width: parent.keyW
                                                    height: 20
                                                    color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
                                                    radius: 3

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        width: parent.width - 6
                                                        text: modelData.key || ""
                                                        color: root.accentColor
                                                        font.pixelSize: (Theme.fontSizeSmall - 2) * root.fontScale
                                                        font.family: "monospace"
                                                        elide: Text.ElideRight
                                                        horizontalAlignment: Text.AlignHCenter
                                                    }
                                                }

                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.left: keyRect.right
                                                    anchors.leftMargin: Theme.spacingS
                                                    anchors.right: parent.right
                                                    text: modelData.description || ""
                                                    color: Theme.surfaceVariantText
                                                    font.pixelSize: (Theme.fontSizeSmall - 1) * root.fontScale
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
