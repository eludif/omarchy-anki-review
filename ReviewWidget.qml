import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons as Commons
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
    property string action: ""
    property string message: ""

    Commons.Translations {
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

        if (operation === "decks") {
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

    onOpenedChanged: {
        if (opened && !decks.length && action === "")
            run("decks")
    }

    KeyboardPanel {
        id: popup
        owner: root
        bar: root.bar
        anchorItem: barButton
        open: root.opened
        contentWidth: popup.fittedContentWidth(Commons.Style.space(390))
        contentHeight: popup.fittedContentHeight(popup.loadedContentHeight, Commons.Style.space(480))

        content: Flickable {
            id: scroll
            anchors.fill: parent
            contentWidth: width
            contentHeight: implicitHeight
            implicitHeight: body.implicitHeight + 28
            clip: true

            Connections {
                target: root
                function onCardChanged() { scroll.contentY = 0 }
            }

            ColumnLayout {
                id: body
                x: 14
                y: 14
                width: scroll.width - 28
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: strings.t("title")
                    color: Commons.Color.foreground
                    font.bold: true
                    textFormat: Text.PlainText
                }

                Controls.ComboBox {
                    id: deckPicker
                    Layout.fillWidth: true
                    visible: !root.card && root.decks.length > 0
                    enabled: root.action === ""
                    model: root.decks
                    currentIndex: root.decks.indexOf(root.selectedDeck)
                    Accessible.name: strings.t("deck")
                    contentItem: Text {
                        text: deckPicker.displayText
                        textFormat: Text.PlainText
                        color: Commons.Color.foreground
                        leftPadding: 8
                        rightPadding: 28
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    delegate: Controls.ItemDelegate {
                        id: deckOption
                        required property int index
                        required property string modelData
                        width: deckPicker.width
                        highlighted: deckPicker.highlightedIndex === index
                        contentItem: Text {
                            text: deckOption.modelData
                            textFormat: Text.PlainText
                            color: Commons.Color.foreground
                            elide: Text.ElideRight
                        }
                    }
                    onActivated: function(index) { root.selectedDeck = root.decks[index] }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.action ? strings.t("loading") : root.message ? strings.t(root.message) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Commons.Color.foreground
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.card !== null
                    text: root.card ? (root.card.front || strings.t("media")) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Commons.Color.foreground
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.revealed
                    text: root.card && root.revealed ? (root.card.back || strings.t("media")) : ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Commons.Color.foreground
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Controls.Button {
                        visible: !root.card
                        enabled: root.action === "" && root.selectedDeck !== ""
                        text: strings.t("start")
                        onClicked: root.run("start", [root.selectedDeck])
                    }

                    Controls.Button {
                        visible: !root.card
                        enabled: root.action === ""
                        text: strings.t("reload")
                        onClicked: root.run("decks")
                    }

                    Controls.Button {
                        visible: root.card !== null && !root.revealed
                        enabled: root.action === ""
                        text: strings.t("reveal")
                        onClicked: root.run("reveal", [root.card.id])
                    }

                    Repeater {
                        model: root.card && root.revealed ? root.card.ratings : []
                        Controls.Button {
                            required property int index
                            required property string modelData
                            text: strings.t(modelData)
                            enabled: root.action === ""
                            onClicked: root.run("grade", [root.card.id, String(index + 1)])
                        }
                    }

                    Controls.Button {
                        visible: root.card !== null
                        enabled: root.action === ""
                        text: strings.t("choose")
                        onClicked: {
                            root.card = null
                            root.revealed = false
                            root.message = ""
                        }
                    }
                }
            }
        }
    }
}
