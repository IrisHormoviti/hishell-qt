import QtQuick
import QtCore

Item {
	Component.onCompleted: {
		var paths = StandardPaths.standardLocations(StandardPaths.HomeLocation);
		console.log("Home path is: " + paths[0]);
		Qt.quit();
	}
}
