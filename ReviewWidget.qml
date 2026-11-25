import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "anki.review"
    implicitWidth: barButton.implicitWidth
    implicitHeight: barButton.implicitHeight

    property var decks: []
    property string selectedDeck: ""
    property var card: null
    property bool revealed: false
    property bool choosingDeck: false
    property string action: ""
    property string message: ""

    readonly property color foreground: bar ? bar.foreground : Color.foreground
    readonly property color dim: Qt.darker(foreground, 1.55)
    readonly property color cardFill: Qt.tint(Color.popups.background, Qt.rgba(
        foreground.r, foreground.g, foreground.b, 0.07))

    component ClockButton: Button {
        foreground: root.foreground
        fontSize: Style.font.bodySmall
        bordered: true
        focusable: true
    }

    Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    function run(operation, args) {
        if (action !== "")
            return
        action = operation
        message = ""
        bridge.command = ["python3", decodeURIComponent(Qt.resolvedUrl("bridge.py").toString()).replace(/^file:\/\//, "")]
            .concat(args ? [operation].concat(args) : [operation])
        bridge.running = true
    }

    function finish(result) {
        const operation = action
        action = ""
        if (result.error) {
            card = null
            revealed = false
            message = operation === "grade" && result.error !== "changed"
                ? "error.grade" : "error." + result.error
            return
        }

        if (operation === "decks" || operation === "launch") {
            decks = result.decks
            if (!decks.includes(selectedDeck))
                selectedDeck = decks[0] || ""
            message = decks.length ? "" : "empty"
            return
        }

        card = result.card
        revealed = operation === "reveal" && card !== null
        if (!card)
            message = "done"
    }

    Process {
        id: bridge
        stdout: StdioCollector {
            id: output
        }
        onExited: function(exitCode) {
            try {
                root.finish(exitCode === 0 ? JSON.parse(output.text) : { error: "response" })
            } catch (error) {
                root.finish({ error: "response" })
            }
        }
    }

    BarIconButton {
        id: barButton
        anchors.fill: parent
        bar: root.bar
        slotSize: Style.bar.statusSlot
        text: "󰂺"
        tooltipText: strings.t("title")
        onPressed: function(button) {
            if (button === Qt.LeftButton)
                root.toggle()
        }
    }

    function chooseDeck() {
        card = null
        revealed = false
        message = ""
        choosingDeck = true
    }

    onOpenedChanged: {
        if (opened && card === null && action === "" && message !== "error.grade")
            run("decks")
    }

    KeyboardPanel {
        id: popup
        owner: root
        bar: root.bar
        anchorItem: barButton
        open: root.opened
        focusTarget: popup.loadedContent
        contentWidth: popup.fittedContentWidth(Style.space(340))
        contentHeight: popup.fittedContentHeight(popup.loadedContentHeight, Style.space(540))

        content: Flickable {
            id: scroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: implicitHeight
            implicitHeight: body.implicitHeight
            activeFocusOnTab: true
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Keys.onEscapePressed: {
                if (root.choosingDeck)
                    root.choosingDeck = false
                else
                    root.close()
            }

            Connections {
                target: root
                function onCardChanged() { scroll.contentY = 0 }
            }

            ColumnLayout {
                id: body
                width: scroll.width
                spacing: Style.spacing.panelGap

                PanelHero {
                    Layout.fillWidth: true
                    title: strings.t("title")
                    meta: root.selectedDeck
                    foreground: root.foreground
                    iconComponent: Text {
                        text: "󰂺"
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.display
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.choosingDeck && root.decks.length > 0
                    spacing: Style.spacing.md

                    PanelSectionHeader {
                        Layout.fillWidth: true
                        foreground: root.foreground
                        text: strings.t("deck").toUpperCase()
                    }

                    ListView {
                        id: deckList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(
                            count * (rowHeight + spacing) - spacing, Style.space(205))
                        model: root.decks
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: Style.spacing.md
                        readonly property real rowHeight: Style.space(38)

                        delegate: ClockButton {
                            required property string modelData
                            width: ListView.view.width
                            height: deckList.rowHeight
                            leftAlign: true
                            bordered: false
                            background: root.cardFill
                            enabled: root.action === ""
                            selected: root.selectedDeck === modelData
                            text: modelData
                            onClicked: {
                                root.selectedDeck = modelData
                                root.choosingDeck = false
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.action ? strings.t(root.action === "launch" ? "launching" : "loading")
                                      : root.message ? strings.t(root.message) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                    id: cardSurface
                    Layout.fillWidth: true
                    implicitHeight: cardBody.implicitHeight + 2 * padding
                    visible: root.card !== null
                    radius: Style.cornerRadius
                    color: root.cardFill

                    readonly property int padding: Style.space(15)

                    ColumnLayout {
                        id: cardBody
                        x: cardSurface.padding
                        y: cardSurface.padding
                        width: cardSurface.width - 2 * cardSurface.padding
                        spacing: Style.spacing.md

                        Text {
                            Layout.fillWidth: true
                            text: root.card ? (root.card.front || strings.t("media")) : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }

                        PanelSeparator {
                            Layout.fillWidth: true
                            visible: root.revealed
                            foreground: root.foreground
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.revealed
                            text: root.card && root.revealed ? (root.card.back || strings.t("media")) : ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                        }
                    }
                }

                ClockButton {
                    Layout.fillWidth: true
                    visible: !root.card && !root.choosingDeck && root.selectedDeck !== ""
                             && root.message !== "error.connection"
                    enabled: root.action === ""
                    text: strings.t("start")
                    onClicked: root.run("start", [root.selectedDeck])
                }

                ClockButton {
                    Layout.fillWidth: true
                    visible: root.card !== null && !root.revealed
                    enabled: root.action === ""
                    text: strings.t("reveal")
                    onClicked: root.run("reveal", [root.card.id])
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.revealed
                    spacing: Style.spacing.md

                    Repeater {
                        model: root.card && root.revealed ? root.card.ratings : []
                        ClockButton {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: strings.t(modelData)
                            enabled: root.action === ""
                            onClicked: root.run("grade", [root.card.id, String(index + 1)])
                        }
                    }
                }

                ClockButton {
                    Layout.fillWidth: true
                    visible: root.message === "error.connection"
                    enabled: root.action === ""
                    text: strings.t("launch")
                    onClicked: root.run("launch")
                }

                ClockButton {
                    Layout.fillWidth: true
                    visible: root.choosingDeck || root.card !== null || root.decks.length > 1
                    enabled: root.action === ""
                    text: strings.t(root.choosingDeck ? "back" : "choose")
                    onClicked: {
                        if (root.choosingDeck)
                            root.choosingDeck = false
                        else
                            root.chooseDeck()
                    }
                }

                ClockButton {
                    Layout.fillWidth: true
                    visible: !root.card && (root.message !== "" || !root.decks.length)
                             && root.action === ""
                    text: strings.t("reload")
                    onClicked: root.run("decks")
                }
            }
        }
    }
}
