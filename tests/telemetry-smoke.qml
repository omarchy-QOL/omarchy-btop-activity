import QtQuick
import Quickshell

QtObject {
    id: root
    property var telemetry: null
    Component.onCompleted: {
        // Quickshell rewrites relative imports outside its config directory.
        var directory = Quickshell.env("BTOP_PLUGIN_ROOT") || Quickshell.env("PWD")
        var component = Qt.createComponent("file:" + directory + "/Telemetry.qml")
        if (component.status !== Component.Ready) {
            console.error(component.errorString())
            Qt.quit()
            return
        }
        telemetry = component.createObject(root, { updateMs: 1000 })
    }
    property Timer progress: Timer {
        interval: 1000
        repeat: true
        running: root.telemetry !== null
        onTriggered: console.log("TELEMETRY " + JSON.stringify({
            time: Date.now(), cpu: telemetry.cpuUsage,
            memory: telemetry.memoryUsage, temperature: telemetry.cpuTemperature,
            gpus: telemetry.gpus,
            errors: telemetry.backendErrors
        }))
    }
    property Timer stop: Timer {
        interval: Number(Quickshell.env("BTOP_SMOKE_MS") || 6500)
        running: true
        onTriggered: Qt.quit()
    }
}
