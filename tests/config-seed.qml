import QtQuick
import Quickshell
import Quickshell.Io
import ".." as Btop

QtObject {
  id: root
  property bool requested: false
  property int deletions: Quickshell.env("SEED_DELETIONS") | 0

  // Keep the fixture away from the real packaged config.
  property Btop.Service service: Btop.Service {
    omarchyConfigPath: Quickshell.env("SEED_OMARCHY_CONFIG")
  }

  property Process remove: Process {
    command: ["rm", "--", root.service.configPath]
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
      } else if (root.deletions > 0 && root.service.configExists) {
        root.deletions--
        root.remove.running = true
      } else if (!root.service.configExists) {
        if (!root.remove.running)
          root.requested = false
      } else {
        console.log("ok - config ready")
        Qt.quit()
      }
    }
  }
}
