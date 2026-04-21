# Keybinding Cheat Sheet

A [DankMaterialShell](https://danklinux.com/docs/dankmaterialshell) desktop widget that shows compositor keybindings by calling `dms keybinds show <compositor>`.

Supports **Hyprland**, **MangoWC**, **Scroll**, **Miracle**, **Sway**, and **Niri**.

![Keybinding Cheat Sheet widget](example.png)

---

## Features

- Reads keybindings from `dms keybinds show <compositor>`
- Uses section/category names provided by DMS
- Show/hide individual sections from the settings panel
- Reorder sections in settings
- Configure columns, accent color, font scale, and background opacity

---

## Installation

1. Copy or symlink this directory into your DMS plugins folder:

   ```bash
   ln -s ~/path/to/dank-keybinding-cheat-sheet \
         ~/.config/DankMaterialShell/plugins/KeybindingCheatSheet
   ```

2. Open DMS Settings → Plugins, scan for plugins, and enable **Keybinding Cheat Sheet**.

3. Add the widget to your desktop.


---

## Settings

| Setting | Description |
|---|---|
| **Compositor** | Which compositor source to request from DMS |
| **Columns** | Number of columns used to display bindings |
| **Color** | Accent color mode: primary, secondary, or custom |
| **Background Opacity** | Transparency of the widget background |
| **Font Scale** | Scale factor for all text in the widget |
| **Sections** | Toggle individual sections on/off in the widget |
| **Section Order** | Move sections up/down in settings |

### Compositor options

| Compositor |
|---|
| Hyprland |
| MangoWC |
| Scroll |
| Miracle |
| Sway |
| Niri |

---

## How It Works

The widget runs a Quickshell `Process` command:

```bash
dms keybinds show <compositor>
```

It expects JSON output with categories/sections and keybind entries, then renders them into the cheat sheet UI.

Section visibility and section order are stored in plugin settings and applied client-side.

---

## Manual check

Run the DMS command directly to verify available data for a compositor:

```bash
dms keybinds show hyprland
```

---

## License

Public domain — see [LICENSE](LICENSE). Do whatever you want with it.
