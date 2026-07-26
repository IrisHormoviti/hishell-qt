import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: pathBar
    spacing: Kirigami.Units.smallSpacing

    // Split the current path into breadcrumb segments
    property string currentPath: fileModel ? fileModel.current_path : ""
    property var segments: {
        var p = currentPath;
        if (p === "" || p === ".")
            return ["/"];
        // Remove trailing slash
        if (p.endsWith("/") && p.length > 1)
            p = p.substring(0, p.length - 1);
        var parts = p.split("/");
        // Filter out empty strings but keep a leading "/" for root
        var result = [];
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] !== "") {
                result.push(parts[i]);
            }
        }
        if (result.length === 0)
            result.push("/");
        return result;
    }

    // Build the cumulative path for each breadcrumb index
    function pathForIndex(idx) {
        var p = currentPath;
        if (p === "" || p === ".")
            return "/";
        if (p.endsWith("/") && p.length > 1)
            p = p.substring(0, p.length - 1);
        var parts = p.split("/").filter(function (s) {
            return s !== "";
        });
        var result = "/" + parts.slice(0, idx + 1).join("/");
        return result;
    }

    Repeater {
        model: pathBar.segments

        delegate: RowLayout {
            spacing: Kirigami.Units.smallSpacing

            // Separator arrow (skip for the first segment)
            Label {
                visible: index > 0
                text: "›"
                font.pointSize: 12
                color: Kirigami.Theme.disabledTextColor
            }

            Button {
                id: crumbButton
                flat: true
                text: modelData === "/" ? "Root" : modelData

                // Highlight the last (current) segment
                background: Rectangle {
                    color: index === pathBar.segments.length - 1 ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15) : "transparent"
                    radius: Kirigami.Units.smallSpacing
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        visible: index === pathBar.segments.length - 1
                        source: "folder"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }

                    Label {
                        text: crumbButton.text
                        color: Kirigami.Theme.textColor
                        font.bold: index === pathBar.segments.length - 1
                    }
                }

                onClicked: {
                    var target = pathBar.pathForIndex(index);
                    if (fileModel) {
                        fileModel.current_path = target;
                    }
                }
            }
        }
    }
}
