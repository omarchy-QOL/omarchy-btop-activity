import QtQuick
import Quickshell
import ".." as Btop

QtObject {
  id: root
  property bool requested: false

  // Keep the fixture away from the real packaged config.
  property Btop.Service service: Btop.Service {
    omarchyConfigPath: Quickshell.env("SEED_OMARCHY_CONFIG")
  }

  property Timer check: Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      if (root.service.configError !== "") {
        console.error(root.service.configError)
        Qt.exit(1)
      } else if (root.service.configBusy) {
        return
      } else if (!root.requested) {
        root.requested = root.service.setConfig(1234, "memory", true, true)
      } else {
        console.log("ok - config ready")
        Qt.quit()
      }
    }
  }
}
