# Changelog

Notable changes to btop Activity are documented here.

## 0.2.5 - 2026-10-06

- Read defaults from a shipped `settings.toml`: `poll_intervals` sets the
  interval ladder the Update interval arrows step through, and `left_click`
  chooses whether a left click opens btop or toggles it (@gw7523).
- Add `helpers/toggle-btop.sh`, which closes the plugin's btop window when one
  is open and launches btop otherwise. It backs `left_click = "toggle"` and can
  be bound directly, so one key both opens and closes btop (@gw7523).
- Move the shipped defaults to `settings.example.toml`; More plugin settings
  opens an optional user-owned `settings.toml` outside the checkout. Valid saves
  apply immediately; invalid edits keep the last working settings.
- Reduce idle CPU use by sampling only on hover or while the menu is open,
  without making the icon flicker when sampling resumes.
- Make GPU readings follow the selected update interval alongside CPU and RAM.
- Show theme-colored `[b]`, `[s]`, and `[?]` menu shortcut hints.
- Use `l`/Right to enter Settings and `h`/Left on Back to return to the menu.
- Keep the menu open when starting btop from it, so settings remain accessible.
- Honor custom Omarchy `floating-window` size rules when launching btop and
  preserve its last floating size when switching back from tiled mode
  (@filip-spaldon, #52).

## 0.2.4 - 2026-09-20

- Stop using GNU find's FTS traversal for DRM fdinfo sampling so processes
  exiting during `/proc` discovery cannot abort the collector. Thanks
  @LekkerBelangrijk and @kzagoris for the independent crash reports and @gw7523
  for the fix.
- Keep the proc scanner in a dedicated Python helper and propagate unexpected
  failures to telemetry retry handling.

## 0.2.3 - 2026-09-13

- Validate the user runtime directory and keep the generated btop config in an
  `omarchy-btop-activity` subdirectory.
- Reuse the single runtime config without backups, lifecycle markers, or
  uninstall cleanup.
- Clarify and compact the plugin settings sections.
- Add a live transparent-background setting for plugin-launched btop sessions.
- Show default render GPU usage in the popup when Fastfetch identifies it.

## 0.2.2 - 2026-09-05

- Replace the compiled GPU helper with kernel readings and optional native
  NVIDIA, AMD, and Intel monitoring tools.
- Keep CPU and RAM sampling responsive while optional GPU queries run, with
  timeouts, stale-reading expiry, and checks for sleeping devices.
- Show separate GPU rows using stable device identities and vendor ordering.
- Display VRAM in btop's compact byte format, distinguish shared system RAM, and
  consistently use `--` for unavailable readings.
- Fix Intel GPU device selection and document the optional Intel GPU tools
  package and performance-counter permission.
- Align tooltip readings and place a compact command legend in the top-right
  corner, sharing the tooltip's outer borders.
- Keep the popup header icon in sync with the selected tray icon, including
  custom images.
- Move interval preset arrows to the left of the input, with the unit last.
- Document hardware-specific setup, permissions, and verification commands, and
  simplify the README release table.
- Put quickstart and settings before optional hardware setup, fix the
  development instructions, and refresh the marketplace description.

Hardware checks covered a Radeon RX 6400 and two Intel Haswell systems. NVIDIA,
AMD SMI, and Intel XPU-SMI adapters still need hardware validation; the XPU-SMI
setup is documented as experimental.

## 0.2.1 - 2026-09-02

- Render the bar tooltip as plain text. The bar draws `tooltipText` with
  `textFormat: Text.PlainText`, so the `<pre>`/`<font>` wrapper used to dim
  `<unavailable>` was shown to the user as literal tag text whenever GPU
  temperature was unreadable (@gw7523).
- Stream Intel GPU usage immediately after installation without a privileged
  helper.
- Keep Intel GPU sampling responsive across large descriptor sets.

## 0.2.0 - 2026-08-21

- Rename the GitHub repository to `omarchy-btop-activity` while keeping the
  plugin ID stable (@ilyazar).
- Replace the per-cell release separators with a normal compact table
  (@ilyazar).

## 0.1.10 - 2026-08-21

- Allow any btop-supported update interval while keeping the preset ladder on
  mouse and keyboard controls (@ilyazar).
- Restore a pre-existing runtime btop config when disabling or removing the
  plugin (@ilyazar).
- Add native Intel and NVIDIA GPU telemetry backends with a narrow setup helper
  (@ilyazar).
- Follow the transparent bar's adaptive foreground color so the btop widget
  stays legible (@nate0m, @namilton-ship-it).

## 0.1.9 - 2026-08-15

- Add live GPU usage and temperature to the bar tooltip and menu, with a clear
  fallback when temperature is unavailable.
- Recognize Scroll Lock in formatted shortcuts.

## 0.1.8 - 2026-08-14

- Add a demo of btop launch, floating and tiled modes, live refresh changes, and
  keybinding updates.

## 0.1.7 - 2026-08-14

- Refresh the preview and clarify how to open and override the Activity
  shortcut.

## 0.1.6 - 2026-08-14

- Show the effective Activity shortcut in settings, including its unbound state.
- Keep custom icon controls next to the tray icon selection and share the
  Hyprland shortcut helpers.

## 0.1.5 - 2026-08-14

- Open the Omarchy user bindings file directly from the plugin settings.
- Persist btop options without reloading the plugin and create missing runtime
  configs from Omarchy's packaged defaults.

## 0.1.4 - 2026-08-13

- Keep settings responsive after private btop config initialization.
- Apply floating and tiled modes to open windows and restore centered floating
  geometry.
- Add a 250 ms update interval.

## 0.1.3 - 2026-08-13

- Seed the private btop config from Omarchy's packaged defaults so the current
  theme is preserved.

## 0.1.2 - 2026-08-12

- Isolate plugin settings from the normal user btop config and remove them with
  the plugin.

## 0.1.1 - 2026-08-12

- Add CPU temperature to the hover details and use the selected btop interval
  for all hover stats.
- Default fresh installs to the CPU tray icon.

## 0.1.0 - 2026-08-12

- Initial release.
