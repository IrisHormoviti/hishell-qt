import QtQuick
import ClamOS.Theme

// Loaded only when a ClamOS theme is active. Keeping the import in this small,
// on-demand component means a desktop without the ClamOS QML module can still
// start the shell: the loader simply never activates here.
QtObject {
	property var theme: ClamTheme
}
