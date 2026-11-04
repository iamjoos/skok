# skok

Keyboard-driven virtual desktop switching for Windows, written in AutoHotkey v2.

**One key per desktop. Each desktop keeps its layout.**

skok gives each virtual desktop a fixed key. Arrange windows on a desktop once, and switching back to it brings back the same layout, with focus on the window you last used there. skok never tiles or resizes windows; move a window to another desktop with a shortcut.

With the default `CapsLock` modifier (`super` below) and the example config:

- `super + 1` / `2` / `3`: switch to that desktop, or cycle its windows if already there.
- `super + Alt + 1` / `2` / `3`: move the active window to that desktop and follow it.
- `super + Tab`: toggle between the current and previous desktop.
- `super + Space`: toggle between the active and previously focused window, switching desktops if needed.
- `super + j` / `k`: cycle forward / backward through windows on the current desktop.
- `super + p`: pin the active window to all desktops, or unpin it.
- `super + Shift + Backspace`: close the active window.
- `super + s`: fuzzy-search windows on all desktops by title, desktop name or executable.

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/) and run skok with the 64-bit `AutoHotkey64.exe`.
2. Download `VirtualDesktopAccessor.dll` from the [VirtualDesktopAccessor releases](https://github.com/Ciantic/VirtualDesktopAccessor/releases) (MIT-licensed, by Jari Pennanen) and put it next to [skok.ahk](skok.ahk). Use the release that supports your Windows version. skok does not ship the DLL and refuses to start without a working one.
3. Run [skok.ahk](skok.ahk). On first launch it creates `%LOCALAPPDATA%\skok\config.ini` from [config.example.ini](config.example.ini), then names your first three desktops `web`, `code` and `terminal`, creating any that are missing.
4. Press `CapsLock + 2` to switch to the `code` desktop, and `CapsLock + Alt + 1` to take the active window back to `web`.
5. Use the tray menu's **Edit config**, then **Reload Script**, to change shortcuts and desktops.

An existing config is never overwritten or merged. Use the tray menu's **Suspend Hotkeys** or **Exit** to pause or stop. To start at sign-in, put a shortcut to the script in `shell:startup`. Invalid hotkeys and incomplete desktop sections are reported at startup.

## Shortcuts

`super` is configurable (`super_key`): **CapsLock by default**, which then no longer toggles caps. Another key such as F24 is safest; a standard modifier such as Alt takes over that modifier's shortcuts in other apps. Win also overrides Windows shortcuts (`Win + V`, `Win + H`, ...), and `Win + L` cannot be bound.

| Shortcut | Action | Config key |
| --- | --- | --- |
| `super + <desktop key>` | Switch to the desktop and focus the window last used there; cycle its windows if already there. | `hotkey` in `[desktop.*]` |
| `super + Alt + <desktop key>` | Move the active window to the desktop and switch there with it. Shift if `super_key` is Alt. | `move_window_modifier` |
| `super + Tab` | Toggle between the current and previous desktop. | `previous_desktop_hotkey` |
| `super + Space` | Toggle between the active and previous window, on any desktop. | `previous_window_hotkey` |
| `super + j` / `k` | Cycle windows on the current desktop. | `cycle_windows_hotkey`, `reverse_cycle_windows_hotkey` |
| `super + p` | Pin the active window to all desktops, or unpin it (and its app, if pinned in Task View). | `pin_window_hotkey` |
| `super + Shift + Backspace` | Ask the active window to close (it may prompt to save). | `close_window_hotkey` |
| `super + s` | Open window search, or cancel it if already open. | `search_windows_hotkey` |

Hotkey values use AHK syntax: `!` is Alt, `+` Shift, `^` Ctrl. A desktop's `hotkey` must not include `move_window_modifier`, which is added for its move shortcut. Minimized windows are restored when focused.

### Desktops and history

skok tracks two histories:

- **Desktops:** the previous desktop changes only when you switch desktops, whether with skok, `Win + Ctrl + Left` / `Right` or Task View. Focusing another window on the same desktop leaves it alone, so `super + Tab` always returns to the desktop you came from.
- **Windows:** `super + Space` returns to the previously focused window, even if it is on another desktop.

Each desktop also remembers its last focused window. Switching to a desktop focuses that window, or the desktop's topmost window if it has moved or closed. Pressing the shortcut of the desktop you are already on cycles forward through its windows, just like `super + j`. Repeated presses advance the preview; release `super` to focus the selection.

Moving a window to another desktop switches to that desktop with the window still focused. A pinned window is already on every desktop, so moving it just switches.

### Cycling

Cycling previews windows in place (like [search](#window-search)) and only focuses the selected one when you release `super`, so it counts as one visit: `super + Space` and the Windows `Alt + Tab` order return to the window where the cycle began, not to each window passed through. Other skok hotkeys pressed while cycling first focus the selection; `super + Shift + Backspace` closes the previewed window instead.

### Cycle strip

While cycling, a click-through title strip lists the windows in order and highlights the selected one, which is previewed and [outlined](#overlays). All disappear when `super` is released. Disable the strip with `show_cycle_titles=0` under `[settings]`.

### Window search

`super + s` lists windows on all virtual desktops, including minimized windows and windows Windows cloaks on inactive desktops. Hidden app windows and tool windows are excluded. Release `super`, then type: characters must appear in order but not adjacent (`rdm` finds `README.md`), and space-separated terms match in any order, against the desktop name, executable and title. For example, `code rdm` finds a window titled `README.md` on the `code` desktop or in `Code.exe`. Search covers windows, not browser tabs or files.

With an empty query, the current window is the top result, so pressing Enter without typing stays in that window. Other windows on the current desktop follow, then the remaining desktops in desktop-number order, with windows in recent-use order within each group. Typing ranks all matches by relevance instead of grouping them. With an empty query, each desktop group starts with a header naming the desktop (for example, `2: code`, or `Desktop 2` if unnamed); ranked results instead show the desktop on the right of each row. The current desktop's name is highlighted, others are muted. Accepting a window on another desktop switches to that desktop first.

| Key | Action |
| --- | --- |
| Up / Down, Ctrl + K / J, Ctrl + P / N | Move selection (and preview its window). |
| Ctrl + number | Accept the numbered result (see below). |
| Ctrl + Backspace | Delete the previous word of the query. |
| Enter | Accept the selected window. |
| Esc or the search shortcut again | Cancel and return to the window where search started (the last focused window on this desktop if started from the taskbar or desktop). |

To accept a result by number, hold Ctrl and type its digits, then release Ctrl. With fewer than 10 results, `Ctrl + 3` accepts result 3 immediately. With more, a digit that could start a longer number only selects (and previews) that result until you release Ctrl or type the next digit: `Ctrl + 1`, `2` accepts result 12, and `Ctrl + 1` then releasing Ctrl accepts result 1. A number is accepted as soon as no further digit could fit, so with 15 results `Ctrl + 3` accepts result 3 without waiting. Pressing any other key while Ctrl is held drops the pending number; a digit beyond the last result starts a new number.

As you type or navigate, the selected window is previewed in place: a live, click-through thumbnail is drawn over its visible frame and [outlined](#overlays), while the search box keeps keyboard focus. Minimized windows are previewed centered on their display without being restored. Nothing is activated until you accept, so `super + Space` and the Windows Alt+Tab order only see the accepted window, and cancelling changes neither. Disable previews with `preview_search_selection=0` under `[settings]`.

Up to 20 results are shown (fewer if the monitor is small); a footer shows how many are hidden. Clicking another window closes search without returning to the starting window.

### Overlays

The cycle strip and search open at the top of the Windows primary (main) display. Set `overlay_display=active` under `[settings]` to use the display of the window that was active when cycling or search started instead. Either way, they stay put while selecting windows on other displays.

An outline around the selected window's preview makes it easy to find across displays. Previews and outlines never move, resize or focus windows, nor block clicks. Disable the outline with `highlight_selection=0`.

Overlays use the Windows accent color. Set `theme=system` (default), `theme=light` or `theme=dark` to follow Windows' app light/dark preference or force a theme. System theme and accent changes are picked up when cycling or search next starts. Invalid `overlay_display` and `theme` values are reported at startup and fall back to `primary` and `system`. Reload after changing settings.

## Configuration

Edit `%LOCALAPPDATA%\skok\config.ini` and reload; [config.example.ini](config.example.ini) lists all options and defaults.

```ini
[settings]
virtual_desktop_accessor=
super_key=CapsLock
previous_desktop_hotkey=Tab
previous_window_hotkey=Space
cycle_windows_hotkey=j
reverse_cycle_windows_hotkey=k
pin_window_hotkey=p
close_window_hotkey=+Backspace
search_windows_hotkey=s
preview_search_selection=1
move_window_modifier=Alt
show_cycle_titles=1
overlay_display=primary
highlight_selection=1
theme=system

[desktop.web]
hotkey=1

[desktop.code]
hotkey=2
```

`virtual_desktop_accessor` is the path to the DLL, relative to `skok.ahk` unless absolute; leave it empty to use `VirtualDesktopAccessor.dll` next to `skok.ahk`.

Each `[desktop.<name>]` section needs a `hotkey`. skok finds desktops by name, so a shortcut keeps reaching its desktop after you reorder desktops in Task View. At startup, each section without a matching desktop takes the desktop at its position in the config (the first section is desktop 1) and renames it, unless that desktop already carries another section's name; then a new desktop is created instead. A shortcut whose desktop was removed or renamed creates a new one with the section's name.

To add a third desktop on `CapsLock + 3`:

```ini
[desktop.browse]
hotkey=3
```

Pick unused keys and don't duplicate section names. Comments must be on their own line; a `;` after a value is part of the value.

A `[send.<name>]` section sends keystrokes instead, which is useful for apps that open fastest through their own global shortcut. `hotkey` is pressed with `super`; `keys` uses AHK [Send](https://www.autohotkey.com/docs/v2/lib/Send.htm) syntax (`#` Win, `!` Alt, `^` Ctrl, `+` Shift). For PowerToys Command Palette on its default `Win + Alt + Space`:

```ini
[send.cmdpal]
hotkey=d
keys=#!{Space}
```

## Limitations

- skok depends on `VirtualDesktopAccessor.dll`, which relies on undocumented Windows interfaces. Major Windows updates can break it until a new release supports them; skok then refuses to start.
- `super + Tab` remembers the previous desktop by position, so reordering desktops in Task View can make it return to a different desktop.
- Cycling covers visible, titled windows on the current desktop (roughly the `Alt + Tab` list); dialogs count as part of their owner. Windows are visited in handle order for a stable sequence.
- Previous-window tracking uses a shell hook; if the previous window closed, it falls back to the most recently used other window on the current desktop.
- Tested only on Windows 11.
- Hotkeys do not work over an elevated window unless skok runs elevated.
- `Win + L` always locks the PC and cannot be a hotkey.

## Alternatives

For tiling or full workspace management, see [Komorebi](https://github.com/LGUG2Z/komorebi), [GlazeWM](https://github.com/glzr-io/glazewm) or [harken](https://github.com/grantith/harken) (also AutoHotkey-based).

Licensed under the [MIT License](LICENSE).
