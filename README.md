# btop Activity for Omarchy Quattro

Brings btop back to the Omarchy bar: live CPU, RAM, and GPU usage (also vRAM)
and temperatures.

![btop Activity on the Omarchy desktop](preview.png)

## Features

- applies settings live to the running btop application
- preserves Omarchy's btop theme without touching the normal user `btop.conf`

## Quickstart

```bash
omarchy plugin add https://github.com/omarchy-QOL/omarchy-btop-activity --enable
```

The plugin starts with the information Linux already provides: CPU and RAM
usage, available temperature sensors, and any GPU readings exposed by your
driver. Omarchy already includes btop and Fastfetch. If GPU readings are
missing, see the [optional hardware setup](#optional-hardware-setup) for your
hardware. The plugin detects supported tools automatically.

After installation:

- **left-click** bar icon to start/focus btop in the selected window mode
- **right-click** bar icon to open the plugin settings
  - choose **Settings** to change plugin and btop options
  - choose **Help** to open built-in help in the selected window mode
- **hover over it** to see RAM use, CPU use and temperature, and GPU use,
  temperature, and VRAM

## Demo

See btop launch from the bar, switch between floating and tiled layouts, apply a
250 ms refresh interval live, and update its keybinding.

<https://github.com/user-attachments/assets/d8dde155-dd62-4afa-b586-2f4b95a61d4e>

## Settings

The plugin keeps a short list of useful controls before opening btop:

| Setting         | Choices                                  |
| --------------- | ---------------------------------------- |
| Tray icon       | Meters, CPU, Pulse, or a custom image    |
| Keybindings     | opens the Omarchy user bindings file     |
| Window mode     | floating or tiled                        |
| Update interval | any whole number from 100 ms to one day  |
| Process sorting | lazy CPU, direct CPU, memory, or program |
| Process tree    | on or off                                |

For the update interval, press Enter or click the value to edit it. Left/Right
(or `h`/`l`) change it by 1 ms. Up/Down (or `k`/`j`) move through 250, 500,
1000, 2000, and 5000 ms while still letting you type any value in btop's full
range. From a custom value, they jump to the next preset above or below it and
wrap around at the ends.

Edit `~/.config/hypr/bindings.lua` directly, or select **Keybindings** in the
plugin settings to open it. The button prefers Neovim, jumping to an existing
Activity override or to the end of the file; without Neovim, it uses Omarchy's
config editor.

Omarchy assigns `Super+Ctrl+T` to btop by default. To replace it, e.g. with
`Super+Ctrl+Alt+g`, add:

```lua
hl.unbind("SUPER + CTRL + T")
o.bind("SUPER + CTRL + ALT + G", "Activity", { tui = "btop" })
```

After Hyprland reloads, the settings row shows the effective shortcut, or
`Unbound` when no Activity binding remains.

Cycle **Tray icon** through **Meters**, **CPU**, **Pulse**, and **Custom**. The
default CPU icon follows the bar's normal foreground color. The custom path is
stored separately, so switching between styles does not discard it. **CPU** is
the default for new installations.

For **Custom**, enter an absolute path, a `~/path`, or a `file://` URL, then
press Enter or **Save**. SVG and PNG work well. The plugin renders the file
as-is and does not recolor it. An invalid path shows `!`.

Depending on the installed icon themes, useful paths include:

- `/usr/share/icons/hicolor/scalable/apps/btop.svg`
- `/usr/share/icons/HighContrast/scalable/apps/utilities-system-monitor.svg`
- `/usr/share/icons/Yaru/scalable/apps/system-monitor-app-symbolic.svg`

Plugin choices are stored in Omarchy's `shell.json` and survive shell restarts.

Under **Appearance**, choose whether btop opens tiled or floating. The setting
applies to both left-click and Help. Floating is the default and restores
Omarchy's centered 875 x 600 window size when selected.

## Optional hardware setup

AMD Radeon, NVIDIA, and Intel graphics expose different information through
different tools. When a reading is missing, the plugin can use an installed tool
for that hardware to fill the gap. Installing one does not guarantee every
reading: some GPUs do not expose a separate temperature or dedicated video
memory.

Follow only the sections that match your hardware. On a mixed-GPU system, each
card can use a different source. The plugin detects tools automatically and
never installs packages or changes permissions itself. After setup, allow about
30 seconds for discovery and retries, or restart the shell:

```bash
omarchy restart shell
```

Run the verification commands below as your normal desktop user, without `sudo`.
A command that only works as root will not work inside the plugin. The tooltip
and btop's own GPU panel use separate readers; installing a tool for the tooltip
does not necessarily enable the same readings inside btop.

### CPU, RAM, and standard GPU readings

No additional installation is needed for CPU/RAM usage. Temperatures depend on
the sensors your kernel exposes; missing sensors stay `--` rather than being
replaced by another component's temperature.

Fastfetch supplies GPU names and additional readings where supported. It is
already part of Omarchy; if you previously removed it, restore it with:

```bash
sudo pacman -S --needed fastfetch
```

The plugin also reads available Linux GPU counters directly. These paths need no
vendor monitoring package.

### AMD Radeon GPUs: ROCm SMI

With the `amdgpu` driver, Linux may already expose usage, temperature, and VRAM.
For missing readings, and for AMD support in btop's own GPU panel, install ROCm
SMI:

```bash
sudo pacman -S --needed rocm-smi-lib
/opt/rocm/bin/rocm-smi --showbus --showuse --showtemp --showmeminfo vram --json
```

Restart btop if it was open during installation. On our Radeon RX 6400, this
read-only command works without extra permissions. Removing ROCm SMI leaves the
plugin's kernel-provided readings working. That result does not guarantee the
same coverage on every AMD model.

If the command reports GPU-access permission errors, check the device access
described under [AMD SMI](#amd-gpus-alternative-amd-smi) below. Installing the
monitoring tool does not replace or repair the graphics driver.

### AMD GPUs: alternative AMD SMI

The plugin also supports `amd-smi`, supplied by Arch's
[`amdsmi` package](https://archlinux.org/packages/extra/x86_64/amdsmi/files/).
It is an alternative source for usage, temperature, and VRAM on supported
`amdgpu` devices. You do not need both AMD tools when your readings already
work.

```bash
sudo pacman -S --needed amdsmi
/opt/rocm/bin/amd-smi list --json
/opt/rocm/bin/amd-smi metric --json -u -t -m
```

If it reports missing `render`/`video` groups or denied GPU-device access, an
administrator can grant the standard
[AMD GPU access groups](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/native_linux/install-radeon.html):

```bash
sudo usermod -aG render,video "$USER"
```

Log out of the desktop completely and log back in before retrying. This grants
GPU-device access to your account, not just to this plugin. Do not add groups if
the queries already work. AMD SMI also needs a compatible GPU and driver;
permissions cannot make an unsupported device work. This backend is implemented
but has not been hardware-tested here.

### Intel integrated graphics using i915

For Intel graphics using the `i915` driver, the plugin can read usage through
`intel_gpu_top`:

```bash
sudo pacman -S --needed intel-gpu-tools
intel_gpu_top
```

Press Ctrl+C to exit the tool. If it reports `Permission denied` or requests
`CAP_PERFMON`, grant that capability specifically to its executable:

```bash
sudo setcap cap_perfmon=ep /usr/bin/intel_gpu_top
getcap /usr/bin/intel_gpu_top
```

The last command should show `cap_perfmon=ep`. This permits access to
[performance counters](https://www.kernel.org/doc/html/latest/admin-guide/perf-security.html)
without running the tool as root. Reinstalling or upgrading the package can
remove the capability; check and reapply it if usage disappears.

We verified this setup on two Intel Haswell systems, including removing and
reinstalling the package. This reader supplies usage, not GPU temperature.
Integrated graphics can share system RAM with the CPU instead of having
dedicated VRAM. The plugin currently selects this CLI only for `i915`, not `xe`.

### NVIDIA GPUs

On supported NVIDIA systems, Omarchy normally installs `nvidia-smi` with the
graphics driver utilities. It can supply usage, temperature, and VRAM. Check
whether it already works:

```bash
nvidia-smi
```

If you use the current NVIDIA driver branch and its utilities are missing:

```bash
sudo pacman -S --needed nvidia-utils
```

[`nvidia-utils` includes `nvidia-smi`](https://archlinux.org/packages/extra/x86_64/nvidia-utils/files/).
The utilities must match your installed driver branch. For example, a legacy
`nvidia-580xx` installation needs its matching `nvidia-580xx-utils` package, not
a blind switch to `nvidia-utils`. Follow your driver setup if the command
reports a driver/library mismatch or cannot communicate with the GPU.

No Intel-style `CAP_PERFMON` setup is normally needed for these
[read-only NVIDIA queries](https://docs.nvidia.com/deploy/nvidia-smi/index.html).
The plugin does not use `nvidia-smi` with Nouveau, and a working CLI still may
report unsupported fields. This backend has not been hardware-tested here.

### Intel discrete and data-center GPUs: XPU-SMI (experimental)

An additional `xpu-smi` adapter is implemented for Intel GPUs supported by that
tool. It can supply usage, temperature, and memory, but it is not a general
upgrade for older Intel integrated graphics.

This is not yet a verified Arch/Omarchy installation recipe. As checked on
2026-09-05, the AUR's
[`xpu-smi-bin` package](https://aur.archlinux.org/packages/xpu-smi-bin) is
orphaned, flagged out of date, and still at version 1.2.35. We do not recommend
installing that package blindly just to fill a missing tooltip value.

A working installation needs the matching Intel GPU driver, Level Zero loader
and GPU compute runtime, and the dependencies required by its XPU-SMI version.
Follow
[Intel's installation guidance](https://github.com/intel/xpumanager#how-to-get-xpu-manager)
for your device and release. Once `xpu-smi` is installed and available on the
desktop session's `PATH`, verify it as your normal user:

```bash
xpu-smi discovery -j
xpu-smi discovery -d 0 -j
xpu-smi stats -d 0 -j
```

Replace `0` with a device listed by discovery. Successful discovery alone is not
enough: statistics must also be readable without root. If access is denied,
follow that release's device-permission guidance; do not assume the
`intel_gpu_top` capability command applies here. We have not verified this
backend's installation, permissions, or live readings on suitable hardware.

## Config safety and troubleshooting

The plugin stores its choices in Omarchy's `shell.json` and generates a private
btop config under `$XDG_RUNTIME_DIR`. The normal user `btop.conf` is never read
or written.

The runtime file is created from Omarchy's packaged btop config. Quickshell
writes it atomically, and a running btop receives its supported config-reload
signal only after a successful change. Disabling or removing the plugin restores
a file that existed before the plugin was enabled, or removes the file it
created.

GPU temperature and VRAM depend on driver support. If unavailable, the hover
says `--` or `-- (vRAM)`. See the hardware-specific
[setup instructions](#optional-hardware-setup) for optional tools, permissions,
and verification commands.

## Remove

```bash
omarchy plugin remove ilyazar.btop
```

Removing the plugin removes its private btop settings. It does not remove btop
or change btop's normal configuration.

## Roadmap and releases

Planned work stays at the top. Shipped entries come from
[CHANGELOG.md](CHANGELOG.md), newest first.

| Release | Date       | What changed                                      |
| ------- | ---------- | ------------------------------------------------- |
| 0.2.2   | 2026-09-05 | native GPU telemetry without compiled helpers     |
|         |            | keep CPU and RAM sampling responsive              |
|         |            | show each GPU and distinguish VRAM/shared RAM     |
|         |            | document optional tools and Intel permissions     |
|         |            | align tooltip readings and compact legend         |
|         |            | keep popup and tray icons in sync                 |
|         |            | place interval arrows left of the input           |
|         |            | simplify the release table                        |
| 0.2.1   | 2026-09-02 | fix tooltip text and stream Intel GPU data        |
|         |            | keep Intel GPU sampling responsive at scale       |
| 0.2.0   | 2026-08-21 | simplify the release table                        |
| 0.1.10  | 2026-08-21 | allow any update interval or preset stepping      |
|         |            | restore settings on plugin disable or removal     |
|         |            | show Intel/NVIDIA GPU data after helper setup     |
|         |            | keep the widget readable on transparent bars      |
| 0.1.9   | 2026-08-15 | show GPU usage and temperature in hover/menu      |
|         |            | indicate unavailable GPU temperature              |
|         |            | fix Scroll Lock display in shortcuts              |
| 0.1.8   | 2026-08-14 | demo launch, window modes, refresh, and shortcuts |
| 0.1.7   | 2026-08-14 | update preview and explain Activity shortcuts     |
| 0.1.6   | 2026-08-14 | show the current Activity shortcut or Unbound     |
|         |            | place custom icon controls beside icon choice     |
| 0.1.5   | 2026-08-14 | open user bindings from settings                  |
|         |            | apply btop settings without plugin reload         |
|         |            | create private btop config if missing             |
| 0.1.4   | 2026-08-13 | keep settings usable while private config loads   |
|         |            | switch open btop windows: floating or tiled       |
|         |            | add the 250 ms interval                           |
| 0.1.3   | 2026-08-13 | use Omarchy's btop config and current theme       |
| 0.1.2   | 2026-08-12 | isolate plugin settings and clean up on removal   |
| 0.1.1   | 2026-08-12 | show CPU temperature in hover details             |
|         |            | refresh hover data at the chosen interval         |
|         |            | default to the CPU icon for new installs          |
| 0.1.0   | 2026-08-12 | first release                                     |

## Development

The installed plugin is a regular Git checkout; symlinked plugin folders are
not supported. Install it using [Quickstart](#quickstart), then edit that
checkout directly. After making changes, validate and reload it:

```bash
cd ~/.config/omarchy/plugins/ilyazar.btop
omarchy plugin validate .
omarchy-shell shell rescanPlugins
```

If a reload still shows an old component, run `omarchy restart shell`.

## License

MIT
