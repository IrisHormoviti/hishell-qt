pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Floating ghost of a free-placement reposition drag. It mirrors the selection
// in its original arrangement, anchored so the grabbed item stays under the
// cursor, so the whole block is visible while it is being moved.
Item {
	id: dragPreview
	z: 9998

	property bool previewActive: false
	property real cursorX: 0
	property real cursorY: 0
	property var previewData: null
	property var fileManager: null

	readonly property var parsed: {
		const d = previewData;
		if (!d)
			return null;
		// The backend hands this back as a QVariant-wrapped string; parse it, but
		// tolerate an already-parsed object too.
		if (typeof d === "object" && d.items)
			return d;
		try {
			return JSON.parse(String(d));
		} catch (e) {
			return null;
		}
	}

	// Slot sizing mirrors FileSlot so the ghost looks identical to the real icons.
	readonly property real iconSize: parsed && parsed.gridSize ? parsed.gridSize : 64
	readonly property bool showLabels: parsed ? parsed.showLabels !== false : true
	readonly property bool labelsBeside: parsed ? parsed.labelsBeside === true : false

	visible: previewActive && parsed !== null && parsed.items && parsed.items.length > 0
	opacity: visible ? 1.0 : 0.0

	x: cursorX - (parsed ? parsed.hotspotX : 0)
	y: cursorY - (parsed ? parsed.hotspotY : 0)

	Behavior on opacity {
		NumberAnimation {
			duration: 120
			easing.type: Easing.OutCubic
		}
	}

	Repeater {
		model: dragPreview.parsed && dragPreview.parsed.items ? dragPreview.parsed.items : []

		delegate: Item {
			id: previewItem

			required property var modelData
			required property int index

			x: modelData.x
			y: modelData.y
			width: modelData.w
			height: modelData.h

			readonly property string slotIcon: modelData.icon ? String(modelData.icon) : ""
			readonly property string slotTitle: {
				const t = modelData.title ? String(modelData.title) : "";
				if (t !== "")
					return t;
				const p = modelData.path ? String(modelData.path) : "";
				return p.substring(p.lastIndexOf("/") + 1);
			}
			readonly property bool hasIcon: slotIcon !== ""
			readonly property bool labelBeside: dragPreview.labelsBeside && hasIcon

			GridLayout {
				id: contentLayout
				anchors.verticalCenter: parent.verticalCenter
				x: previewItem.labelBeside ? Kirigami.Units.largeSpacing : (parent.width - width) / 2
				columns: previewItem.labelBeside ? 2 : 1

				Item {
					visible: previewItem.hasIcon
					Layout.alignment: previewItem.labelBeside ? Qt.AlignVCenter : Qt.AlignHCenter
					Layout.preferredWidth: dragPreview.iconSize
					Layout.preferredHeight: dragPreview.iconSize

					Loader {
						id: previewIcon
						anchors.fill: parent
						active: previewItem.hasIcon
						sourceComponent: (previewItem.slotIcon.startsWith("file://") || previewItem.slotIcon.startsWith("/")) ? thumbnailComponent : iconComponent
					}

					Component {
						id: thumbnailComponent

						Image {
							anchors.fill: parent
							source: previewItem.slotIcon
							asynchronous: true
							cache: false
							fillMode: Image.PreserveAspectFit
							smooth: true
							clip: true
						}
					}

					Component {
						id: iconComponent

						Kirigami.Icon {
							anchors.fill: parent
							source: previewItem.slotIcon
						}
					}
				}

				Label {
					visible: dragPreview.showLabels
					Layout.alignment: previewItem.labelBeside ? Qt.AlignVCenter : Qt.AlignHCenter
					Layout.maximumWidth: previewItem.labelBeside ? previewItem.width - dragPreview.iconSize - Kirigami.Units.gridUnit * 2 : dragPreview.iconSize + Kirigami.Units.gridUnit * 2
					text: {
						const t = previewItem.slotTitle;
						const idx = t.lastIndexOf('.');
						if (idx > 0 && !(t.startsWith('.') && t.indexOf('.', 1) === -1))
							return t.substring(0, idx) + '<font color="' + Kirigami.Theme.disabledTextColor + '">' + t.substring(idx) + '</font>';
						return t;
					}
					textFormat: Text.StyledText
					color: Kirigami.Theme.textColor
					wrapMode: Text.Wrap
					maximumLineCount: 2
					elide: Text.ElideMiddle
					horizontalAlignment: previewItem.labelBeside ? Text.AlignLeft : Text.AlignHCenter
				}
			}
		}
	}
}
