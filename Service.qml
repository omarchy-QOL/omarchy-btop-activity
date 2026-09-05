import QtQuick
import Quickshell
import Quickshell.Io
import "lib/UpdateInterval.js" as UpdateInterval

QtObject {
  id: root

  property Telemetry telemetry: Telemetry { updateMs: root.updateMs }
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
  property bool baselineReady: false

  readonly property bool configBusy: _pendingConfig !== null
    || _savingConfig
    || _creatingConfig
    || !baselineReady
    || baselineProcess.running
    || defaultConfigProcess.running
  readonly property string configPath: Quickshell.env("XDG_RUNTIME_DIR")
    + "/ilyazar-btop.conf"
  readonly property string configBackupPath: configPath + ".before-plugin"
  readonly property string configAbsentPath: configPath + ".absent-before-plugin"
  readonly property string pluginDir: localPath(Qt.resolvedUrl("."))
  readonly property string omarchyConfigPath:
    "/usr/share/omarchy/config/btop/btop.conf"
  readonly property var sortingValues: [
    "pid", "program", "arguments", "threads", "user", "memory",
    "cpu lazy", "cpu direct"
  ]
  readonly property string baselineCommand: [
    "set -euo pipefail",
    "config_path=\"$1\"",
    "backup_path=\"$2\"",
    "absent_path=\"$3\"",
    "if [[ -e $backup_path || -L $backup_path",
    "    || -e $absent_path || -L $absent_path ]]; then exit 0; fi",
    "if [[ -e $config_path || -L $config_path ]]; then",
    "  temporary=\"${backup_path}.tmp.$$\"",
    "  trap 'rm -rf -- \"$temporary\"' EXIT",
    "  cp -a -- \"$config_path\" \"$temporary\"",
    "  mv -T -- \"$temporary\" \"$backup_path\"",
    "else",
    "  umask 077",
    "  : >\"$absent_path\"",
    "fi"
  ].join("\n")
  readonly property string teardownCommand: [
    "plugin_dir=\"$1\"",
    "plugin_id=\"$2\"",
    "config_path=\"$3\"",
    "backup_path=\"$4\"",
    "absent_path=\"$5\"",
    "attempts=\"$6\"",
    "interval=\"$7\"",
    "plugin_state=absent",
    "if [[ -e $plugin_dir ]]; then",
    "  plugin_state=unknown",
    "  plugin_filter='[.[] | select(.id == $id)]'",
    "  plugin_filter+=' | if length != 1 then \"unknown\"'",
    "  plugin_filter+=' elif .[0].enabled == true then \"enabled\"'",
    "  plugin_filter+=' elif .[0].enabled == false then \"disabled\"'",
    "  plugin_filter+=' else \"unknown\" end'",
    "  for ((attempt = 0; attempt < attempts; attempt++)); do",
    "    plugin_json=\"\"",
    "    if plugin_json=\"$(omarchy plugin list --json 2>/dev/null)\"; then",
    "      plugin_state=\"$(jq -r --arg id \"$plugin_id\" \\",
    "        \"$plugin_filter\" <<<\"$plugin_json\" 2>/dev/null \\",
    "        || printf 'unknown')\"",
    "      [[ $plugin_state == enabled ]] && exit 0",
    "      [[ $plugin_state == disabled ]] && break",
    "    fi",
    "    sleep \"$interval\"",
    "  done",
    "  [[ $plugin_state == unknown && -e $plugin_dir ]] && exit 0",
    "fi",
    "if [[ -e $backup_path || -L $backup_path ]]; then",
    "  rm -f -- \"$config_path\" \"$absent_path\"",
    "  mv -T -- \"$backup_path\" \"$config_path\"",
    "elif [[ -e $absent_path || -L $absent_path ]]; then",
    "  rm -f -- \"$config_path\" \"$backup_path\" \"$absent_path\"",
    "fi"
  ].join("\n")

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value).replace(/\/$/, "")
  }

  function validatedConfig(interval, sorting, tree) {
    var update = UpdateInterval.parse(interval)
    var order = String(sorting)
    if (update === null)
      throw new Error("Invalid btop update interval")
    if (sortingValues.indexOf(order) < 0)
      throw new Error("Invalid btop process sorting")
    if (tree !== true && tree !== false)
      throw new Error("Invalid btop process tree value")
    return { updateMs: update, procSorting: order, procTree: tree }
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

  function setConfig(interval, sorting, tree) {
    if (configBusy) return false
    try {
      var next = validatedConfig(interval, sorting, tree)
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

  function teardown() {
    if (baselineProcess.running) baselineProcess.running = false
    Quickshell.execDetached([
      "bash", "-c", teardownCommand, "btop-runtime-teardown",
      pluginDir, "ilyazar.btop", configPath, configBackupPath,
      configAbsentPath, "10", "0.05"
    ])
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
    omarchyConfigFile.reload()
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

  property Process baselineProcess: Process {
    id: baselineProcess
    running: true
    command: [
      "bash", "-c", root.baselineCommand, "btop-runtime-baseline",
      root.configPath, root.configBackupPath, root.configAbsentPath
    ]
    onExited: function(exitCode) {
      root.baselineReady = exitCode === 0
      if (!root.baselineReady)
        root.configError = "Could not protect existing btop runtime settings"
    }
  }

  property FileView omarchyConfigFile: FileView {
    id: omarchyConfigFile
    path: root.omarchyConfigPath
    printErrors: false
    onLoaded: {
      if (!root._creatingConfig) return
      root._defaultConfigOutput = text()
      root._creatingConfig = false
      root.finishDefaultConfig()
    }
    onLoadFailed: if (root._creatingConfig) root.useDefaultConfig()
  }

  property Process defaultConfigProcess: Process {
    id: defaultConfigProcess
    running: false
    command: ["btop", "--default-config"]
    stdout: StdioCollector {
      id: defaultConfigStdout
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

  Component.onDestruction: root.teardown()
}
