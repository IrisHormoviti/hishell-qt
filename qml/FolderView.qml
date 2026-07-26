import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    property var model
    property var config

    property var positions: {
        try {
            return JSON.parse(root.config.arbitrary_positions);
        } catch (e) {
            return {};
        }
    }

    GridView {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing

        // Align content to the top-left, not centered
        flow: GridView.FlowLeftToRight
        verticalLayoutDirection: GridView.TopToBottom

        model: root.model

        cellWidth: root.config.grid_size + Kirigami.Units.gridUnit * 3
        cellHeight: root.config.grid_size + Kirigami.Units.gridUnit * 3

        delegate: Item {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignHCenter
                    source: model.is_dir ? "folder" : "text-plain"
                    Layout.preferredWidth: root.config.grid_size
                    Layout.preferredHeight: root.config.grid_size
                }

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: model.name
                    color: Kirigami.Theme.textColor
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: root.config.grid_size + Kirigami.Units.gridUnit * 2
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onDoubleClicked: {
                    if (model.is_dir) {
                        root.model.current_path = model.path;
                    }
                }
            }
        }
    }
}
