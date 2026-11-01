import QtQuick
import Quickshell
import Quickshell.Io
import "lib/UpdateInterval.js" as UpdateInterval

QtObject {
  id: root

  property var _telemetryUsers: []
  property Telemetry telemetry: Telemetry {
    updateMs: root.updateMs
    active: root._telemetryUsers.length > 0
  }
  readonly property real cpuUsage: telemetry.cpuUsage
  readonly property real memoryUsage: telemetry.memoryUsage
  readonly property real memoryUsed: telemetry.memoryUsed
  readonly property real memoryTotal: telemetry.memoryTotal
  readonly property var cpuTemperature: telemetry.cpuTemperature
  readonly property string cpuTemperatureKind: telemetry.cpuTemperatureKind
  readonly property var gpus: telemetry.gpus
  readonly property bool available: telemetry.available

  property int updateMs: 2000
  property bool configExists: false
  property bool configReady: false
  property string configError: ""
  property var _pendingConfig: null
  property bool _savingConfig: false
  property string _savingText: ""
  property bool _reloadAfterSave: false
  property string _defaultConfigOutput: ""
  property string _defaultConfigError: ""
  property bool _creatingConfig: false
  property bool _usingDefaultConfigFallback: false
  property bool stateReady: false

  readonly property bool configBusy: _pendingConfig !== null
    || _savingConfig
    || _creatingConfig
    || !stateReady
    || stateProcess.running
    || defaultConfigProcess.running
  readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state"
  readonly property string stateDir: stateRoot + "/omarchy-btop-activity"
  readonly property string configPath: stateDir + "/btop.conf"
  readonly property string userConfigPath:
    (Quickshell.env("XDG_CONFIG_HOME")
      || Quickshell.env("HOME") + "/.config") + "/btop/btop.conf"
  property string omarchyConfigPath:
    "/usr/share/omarchy/config/btop/btop.conf"
  readonly property var sortingValues: [
    "pid", "program", "arguments", "threads", "user", "memory",
    "cpu lazy", "cpu direct"
  ]
  readonly property string prepareStateCommand: [
    "set -euo pipefail",
    "state_root=\"$1\"",
    "state_dir=\"$2\"",
    "config_path=\"$3\"",
    "[[ $state_root == /* ]] || exit 20",
    "[[ $state_dir == \"$state_root/omarchy-btop-activity\" ]] || exit 22",
    "[[ $config_path == \"$state_dir/btop.conf\" ]] || exit 22",
    "umask 077",
    "mkdir -p -- \"$state_root\" || exit 21",
    "if [[ -e $state_dir || -L $state_dir ]]; then",
    "  [[ -d $state_dir && ! -L $state_dir && -O $state_dir",
    "      && -w $state_dir && -x $state_dir ]] || exit 23",
    "else",
    "  mkdir -m 0700 -- \"$state_dir\" || exit 24",
    "fi",
    "chmod 0700 -- \"$state_dir\" || exit 24"
  ].join("\n")

  function setTelemetryDemand(owner, needed) {
    var users = _telemetryUsers.filter(function (user) { return user !== owner })
    if (needed) users.push(owner)
    _telemetryUsers = users
  }

  function validatedConfig(interval, sorting, tree, transparentBackground) {
    var update = UpdateInterval.parse(interval)
    var order = String(sorting)
    if (update === null)
      throw new Error("Invalid btop update interval")
    if (sortingValues.indexOf(order) < 0)
      throw new Error("Invalid btop process sorting")
    if (tree !== true && tree !== false)
      throw new Error("Invalid btop process tree value")
    if (transparentBackground !== true && transparentBackground !== false)
      throw new Error("Invalid btop background value")
    return {
      updateMs: update,
      procSorting: order,
      procTree: tree,
      transparentBackground: transparentBackground
    }
  }

  function patchConfig(raw, key, value) {
    var text = String(raw || "")
    var trailingNewline = text.endsWith("\n")
    var lines = text.split("\n")
    if (trailingNewline) lines.pop()

    var pattern = new RegExp(
      "^(\\s*" + key
        + "\\s*=\\s*)(\"(?:\\\\.|[^\"])*\"|[^\\s#]+)"
        + "(\\s*(?:#.*)?)$"
    )
    var changed = false
    for (var i = 0; i < lines.length; i++) {
      var match = pattern.exec(lines[i])
      if (!match) continue
      lines[i] = match[1] + value + match[3]
      changed = true
    }
    if (!changed) lines.push(key + " = " + value)
    return lines.join("\n") + "\n"
  }

  function setConfig(interval, sorting, tree, transparentBackground) {
    if (configBusy) return false
    try {
      var next = validatedConfig(
        interval, sorting, tree, transparentBackground)
      updateMs = next.updateMs
      _pendingConfig = next
      configError = ""
      configFile.reload()
      return true
    } catch (error) {
      configError = String(error)
      return false
    }
  }

  function handleConfigLoaded(raw, createFile) {
    var text = String(raw || "")
    var current = text
    if (!createFile) configExists = true
    if (_pendingConfig === null) {
      configReady = true
      configError = ""
      return
    }

    var values = _pendingConfig
    _pendingConfig = null
    text = patchConfig(text, "update_ms", String(values.updateMs))
    text = patchConfig(text, "proc_sorting", JSON.stringify(values.procSorting))
    text = patchConfig(text, "proc_tree", String(values.procTree))
    text = patchConfig(
      text, "theme_background", String(!values.transparentBackground))
    if (!createFile && text === current) {
      configReady = true
      configError = ""
      return
    }
    saveConfig(text, true)
  }

  function saveConfig(text, reloadAfterSave) {
    _savingConfig = true
    _savingText = text
    _reloadAfterSave = reloadAfterSave
    try {
      configFile.setText(text)
    } catch (error) {
      failConfig(String(error))
    }
  }

  function finishConfigSave() {
    if (!_savingConfig) return
    var text = _savingText
    var shouldReload = _reloadAfterSave
    _savingConfig = false
    _savingText = ""
    _reloadAfterSave = false
    configExists = true
    configReady = true
    configError = ""
    if (shouldReload) reloadBtop()
  }

  function createConfig() {
    if (_creatingConfig || defaultConfigProcess.running) return
    _defaultConfigOutput = ""
    _defaultConfigError = ""
    _creatingConfig = true
    _usingDefaultConfigFallback = false
    userConfigFile.reload()
  }

  function seedConfig(text, tryNext) {
    if (!_creatingConfig) return
    if (String(text).trim() === "") {
      tryNext()
      return
    }
    _defaultConfigOutput = text
    _creatingConfig = false
    finishDefaultConfig()
  }

  function useDefaultConfig() {
    _creatingConfig = false
    _usingDefaultConfigFallback = true
    defaultConfigProcess.running = true
  }

  function finishDefaultConfig() {
    var text = String(_defaultConfigOutput || "")
    if (text.trim() === "") {
      failConfig(_defaultConfigError || "btop returned an empty default config")
      return
    }
    // A seed that opted out would stop btop keeping settings in this file.
    text = patchConfig(text, "save_config_on_exit", "true")
    if (_pendingConfig !== null) {
      handleConfigLoaded(text, true)
      return
    }
    saveConfig(text, false)
  }

  function failConfig(message) {
    _pendingConfig = null
    _savingConfig = false
    _savingText = ""
    _reloadAfterSave = false
    _creatingConfig = false
    _usingDefaultConfigFallback = false
    configReady = false
    configError = String(message || "Could not update btop settings")
  }

  function reloadBtop() {
    if (reloadProcess.running) return
    var user = Quickshell.env("USER")
    reloadProcess.command = user
      ? ["pkill", "-USR2", "-u", user, "-x", "btop"]
      : ["pkill", "-USR2", "-x", "btop"]
    reloadProcess.running = true
  }

  property FileView configFile: FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: root.handleConfigLoaded(text(), false)
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) {
        root.configExists = false
        if (root._pendingConfig !== null) root.createConfig()
        else {
          root.configReady = true
          root.configError = ""
        }
      }
      else root.failConfig("Could not read btop settings: "
        + FileViewError.toString(error))
    }
    onSaved: root.finishConfigSave()
    onSaveFailed: function(error) {
      root.failConfig("Could not save btop settings: "
        + FileViewError.toString(error))
    }
  }

  property Process stateProcess: Process {
    id: stateProcess
    running: true
    command: [
      "bash", "-c", root.prepareStateCommand, "btop-state-prepare",
      root.stateRoot, root.stateDir, root.configPath
    ]
    onExited: function(exitCode) {
      root.stateReady = exitCode === 0
      if (!root.stateReady) {
        root.configReady = false
        root.configError = exitCode === 20
          ? "XDG_STATE_HOME must be an absolute path"
          : "Could not prepare the private btop state directory"
      }
    }
  }

  property FileView userConfigFile: FileView {
    id: userConfigFile
    path: root.userConfigPath
    printErrors: false
    onLoaded: root.seedConfig(text(), omarchyConfigFile.reload)
    onLoadFailed: if (root._creatingConfig) omarchyConfigFile.reload()
  }

  property FileView omarchyConfigFile: FileView {
    id: omarchyConfigFile
    path: root.omarchyConfigPath
    printErrors: false
    onLoaded: root.seedConfig(text(), root.useDefaultConfig)
    onLoadFailed: if (root._creatingConfig) root.useDefaultConfig()
  }

  property Process defaultConfigProcess: Process {
    id: defaultConfigProcess
    running: false
    command: ["btop", "--default-config"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._defaultConfigOutput = text
    }
    stderr: StdioCollector {
      id: defaultConfigStderr
      waitForEnd: true
      onStreamFinished: root._defaultConfigError = text
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        if (root._usingDefaultConfigFallback)
          root._defaultConfigOutput = patchConfig(
            root._defaultConfigOutput,
            "color_theme",
            JSON.stringify("current")
          )
        root.finishDefaultConfig()
      }
      else root.failConfig(
        defaultConfigStderr.text || root._defaultConfigError
          || "Could not generate btop's default config"
      )
    }
  }

  property Process reloadProcess: Process {
    id: reloadProcess
    running: false
    command: []
  }
}
