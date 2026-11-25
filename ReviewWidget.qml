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

    WidgetButton {
        id: barButton
        anchors.fill: parent
        bar: root.bar
        text: strings.t("bar")
        labelVisible: true
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
        contentWidth: popup.fittedContentWidth(Style.space(390))
        contentHeight: popup.fittedContentHeight(popup.loadedContentHeight, Style.space(480))

        content: Flickable {
            id: scroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: implicitHeight
            implicitHeight: body.implicitHeight + Style.space(28)
            activeFocusOnTab: true
            clip: true

            Connections {
                target: root
                function onCardChanged() { scroll.contentY = 0 }
            }

            ColumnLayout {
                id: body
                x: Style.space(14)
                y: Style.space(14)
                width: scroll.width - Style.space(28)
                spacing: Style.space(10)

                PanelHero {
                    Layout.fillWidth: true
                    title: strings.t("title")
                    meta: root.selectedDeck
                    iconComponent: Text {
                        text: "󰂺"
                        textFormat: Text.PlainText
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.display
                    }
                }

                PanelSeparator { Layout.fillWidth: true }

                PanelSectionHeader {
                    Layout.fillWidth: true
                    visible: root.choosingDeck && root.decks.length > 0
                    text: strings.t("deck").toUpperCase()
                }

                ListView {
                    id: deckList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count * rowHeight, Style.space(205))
                    visible: root.choosingDeck && count > 0
                    model: root.decks
                    clip: true
                    readonly property real rowHeight: Style.space(36)

                    delegate: Button {
                        required property string modelData
                        width: deckList.width
                        height: deckList.rowHeight
                        leftAlign: true
                        focusable: true
                        enabled: root.action === ""
                        selected: root.selectedDeck === modelData
                        text: modelData
                        onClicked: {
                            root.selectedDeck = modelData
                            root.choosingDeck = false
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.action ? strings.t(root.action === "launch" ? "launching" : "loading") : root.message ? strings.t(root.message) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.card !== null
                    text: root.card ? (root.card.front || strings.t("media")) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                PanelSeparator {
                    Layout.fillWidth: true
                    visible: root.revealed
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.revealed
                    text: root.card && root.revealed ? (root.card.back || strings.t("media")) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Button {
                        focusable: true
                        visible: !root.card
                        enabled: root.action === "" && root.selectedDeck !== ""
                        bordered: true
                        text: strings.t("start")
                        onClicked: root.run("start", [root.selectedDeck])
                    }

                    Button {
                        focusable: true
                        visible: !root.card && (root.message !== "" || !root.decks.length)
                        enabled: root.action === ""
                        text: strings.t("reload")
                        onClicked: root.run("decks")
                    }

                    Button {
                        focusable: true
                        visible: root.card !== null && !root.revealed
                        enabled: root.action === ""
                        bordered: true
                        text: strings.t("reveal")
                        onClicked: root.run("reveal", [root.card.id])
                    }

                    Repeater {
                        model: root.card && root.revealed ? root.card.ratings : []
                        Button {
                            focusable: true
                            bordered: true
                            required property int index
                            required property string modelData
                            text: strings.t(modelData)
                            enabled: root.action === ""
                            onClicked: root.run("grade", [root.card.id, String(index + 1)])
                        }
                    }

                    Button {
                        focusable: true
                        bordered: true
                        visible: root.message === "error.connection"
                        enabled: root.action === ""
                        text: strings.t("launch")
                        onClicked: root.run("launch")
                    }

                    Button {
                        focusable: true
                        visible: !root.choosingDeck && (root.card !== null || root.decks.length > 1)
                        enabled: root.action === ""
                        text: strings.t("choose")
                        onClicked: root.chooseDeck()
                    }
                }
            }
        }
    }
}
