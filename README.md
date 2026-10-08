# skok

Keyboard-only window switching for Windows, written in AutoHotkey v2.

**Jump between windows. Don't manage them.**

skok is not a window manager. It never moves, resizes, tiles or arranges windows; it only changes which window has focus. I use it with one maximized window at a time (like the monocle layout in DWM), but maximizing is neither required nor automatic.

It gives you a fixed key per frequent app, direct cycling through an app's windows, and fuzzy search for everything else. With the default `CapsLock` modifier (`super` below):

- `super + Tab`: toggle between the active and previously focused window, without the `Alt + Tab` switcher.
- `super + <app key>`: focus or launch that app; press again to cycle through its windows.
- `super + Shift + <app key>`: run the app's new-instance command (`new_instance_run`, or `run` if unset).
- `super + j` / `k`: cycle forward / backward through windows of the active app, configured or not.
- `super + l` / `h`: cycle through unconfigured windows (those with no matching `[app.*]` section).
- `super + Backspace`: close the active window.
- `super + /`: fuzzy-search all open windows by title, app name or executable.

Windows' own shortcuts (`Win + 1..9`, `Alt + Tab`, `Win + T`) cover much of this, but they depend on taskbar position or opening order, or need the mouse to cycle one app's windows. If they already work for you, you don't need skok.

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Run [skok.ahk](skok.ahk). On first launch it creates `%LOCALAPPDATA%\skok\config.ini` from [config.example.ini](config.example.ini).
3. With two windows open, press `CapsLock + Tab`. The example config also binds `b` (Edge), `v` (VS Code) and `Enter` (Windows Terminal); the launch commands `msedge`, `code` and `wt` must be on your `PATH`.
4. Use the tray menu's **Edit config**, then **Reload Script**, to change shortcuts and apps.

An existing config is never overwritten or merged. Use the tray menu's **Suspend Hotkeys** or **Exit** to pause or stop. To start at sign-in, put a shortcut to the script in `shell:startup`. Invalid hotkeys and incomplete app sections are reported at startup.

## Shortcuts

`super` is configurable (`super_key`): **CapsLock by default**, which then no longer toggles caps. Another key such as F24 is safest; a standard modifier such as Alt takes over that modifier's shortcuts in other apps.

| Shortcut | Action | Config key |
| --- | --- | --- |
| `super + Tab` | Toggle between the active and previous window. | `previous_window_hotkey` |
| `super + <app key>` | Focus the app's topmost window, launch it if none, cycle if already active. | `hotkey` in `[app.*]` |
| `super + Shift + <app key>` | Run `new_instance_run` (else `run`). | `new_instance_modifier` |
| `super + j` / `k` | Cycle windows of the active app. | `cycle_app_windows_hotkey`, `reverse_cycle_app_windows_hotkey` |
| `super + l` / `h` | Cycle windows with no matching `[app.*]` section. | `cycle_unconfigured_hotkey`, `reverse_cycle_unconfigured_hotkey` |
| `super + Backspace` | Ask the active window to close (it may prompt to save). | `close_window_hotkey` |
| `super + /` | Open window search, or cancel it if already open. | `search_windows_hotkey` |

Hotkey values use AHK syntax: `!` is Alt, `+` Shift, `^` Ctrl. Minimized windows are restored when focused.

Cycling previews windows in place (like [search](#window-search)) and only focuses the selected one when you release `super`, so it counts as one visit: `super + Tab` and the Windows `Alt + Tab` order return to the window where the cycle began, not to each window passed through. Other skok hotkeys pressed while cycling first focus the selection; `super + Backspace` closes the previewed window instead.

### Cycle strip

While cycling, a click-through title strip lists the windows in order and highlights the selected one, which is previewed and [outlined](#overlays). All disappear when `super` is released. Disable the strip with `show_cycle_titles=0` under `[settings]`.

### Window search

`super + /` lists every window cycling considers. Release `super`, then type: characters must appear in order but not adjacent (`rdm` finds `README.md`), and space-separated terms match in any order, against the app name, executable and title. For example, `vscode rdm` finds a VS Code window titled `README.md`. Search covers windows, not browser tabs or files.

With an empty query, the current window is the top result, whether configured or not, so pressing Enter without typing stays in that window. Other windows matching configured apps follow, then unconfigured windows, each group in recent-use order. Results show the `[app.<name>]` section name or, for unconfigured windows, the executable.

| Key | Action |
| --- | --- |
| Up / Down, Ctrl + K / J, Ctrl + P / N | Move selection (and preview its window). |
| Ctrl + 1..9 | Accept the numbered result. |
| Enter | Accept the selected window. |
| Esc or the search shortcut again | Cancel and return to the window where search started (the last focused window if started from the taskbar or desktop). |

As you type or navigate, the selected window is previewed in place: a live, click-through thumbnail is drawn over its visible frame and [outlined](#overlays), while the search box keeps keyboard focus. Minimized windows are previewed centered on their display without being restored. Nothing is activated until you accept, so `super + Tab` and the Windows Alt+Tab order only see the accepted window, and cancelling changes neither. Disable previews with `preview_search_selection=0` under `[settings]`.

Up to 20 results are shown (fewer if the monitor is small); a footer shows how many are hidden. Clicking another window closes search without returning to the starting window.

### Overlays

The cycle strip and search open at the top of the Windows primary (main) display. Set `overlay_display=active` under `[settings]` to use the display of the window that was active when cycling or search started instead. Either way, they stay put while selecting windows on other displays.

An outline around the selected window's preview makes it easy to find across displays. Previews and outlines never move, resize or focus windows, nor block clicks. Disable the outline with `highlight_selection=0`.

Overlays use the Windows accent color. Set `theme=system` (default), `theme=light` or `theme=dark` to follow Windows' app light/dark preference or force a theme. System theme and accent changes are picked up when cycling or search next starts. Invalid `overlay_display` and `theme` values are reported at startup and fall back to `primary` and `system`. Reload after changing settings.

## Configuration

Edit `%LOCALAPPDATA%\skok\config.ini` and reload; [config.example.ini](config.example.ini) lists all options and defaults.

```ini
[settings]
super_key=CapsLock
previous_window_hotkey=Tab
cycle_app_windows_hotkey=j
reverse_cycle_app_windows_hotkey=k
cycle_unconfigured_hotkey=l
reverse_cycle_unconfigured_hotkey=h
close_window_hotkey=Backspace
search_windows_hotkey=/
preview_search_selection=1
new_instance_modifier=Shift
show_cycle_titles=1
overlay_display=primary
highlight_selection=1
theme=system

[app.vscode]
hotkey=v
match=ahk_exe Code.exe
run=code
new_instance_run=code --new-window
```

Each `[app.<name>]` section needs `hotkey`, `match` and `run`:

| Key | Description |
| --- | --- |
| `hotkey` | Key pressed with `super` (AHK syntax, e.g. `v`, `Enter`, `1`). |
| `match` | AHK WinTitle that finds the app's windows, e.g. `ahk_exe Code.exe`. |
| `run` | Launch command when no window matches. Quote paths with spaces. |
| `new_instance_run` | Optional; defaults to `run`. Many apps need a flag such as `--new-window`. |
| `run_dir` | Optional working directory for both commands. |

To add Firefox on `CapsLock + f`:

```ini
[app.firefox]
hotkey=f
match=ahk_exe firefox.exe
run="C:\Program Files\Mozilla Firefox\firefox.exe"
new_instance_run="C:\Program Files\Mozilla Firefox\firefox.exe" -new-window
```

Use AutoHotkey's **Window Spy** to find an app's executable; prefer `ahk_exe` over document titles. Pick unused keys, don't duplicate section names, and avoid overlapping `match` values: each matching section registers its own shortcuts, with no priority. Comments must be on their own line; a `;` after a value is part of the value.

A `[send.<name>]` section sends keystrokes instead, which is useful for apps that open fastest through their own global shortcut. `hotkey` is pressed with `super`; `keys` uses AHK [Send](https://www.autohotkey.com/docs/v2/lib/Send.htm) syntax (`#` Win, `!` Alt, `^` Ctrl, `+` Shift). For PowerToys Command Palette on its default `Win + Alt + Space`:

```ini
[send.cmdpal]
hotkey=Space
keys=#!{Space}
```

## Limitations

- App selection follows Windows z-order; there is no separate per-app recent-use list.
- Cycling covers visible, titled windows on the current virtual desktop (roughly the `Alt + Tab` list); dialogs count as part of their owner. Windows are visited in handle order for a stable sequence.
- `super + j` / `k` cycle windows sharing the active window's executable. Classic UWP apps (Settings, Calculator) all run under `ApplicationFrameHost.exe` and cycle together.
- `super + l` / `h` fix their window list on the first press until `super` is released. From a configured app, forward starts at the first unconfigured window and reverse at the last.
- Previous-window tracking uses a shell hook; if the previous window closed, it falls back to the most recently used other window.
- Tested only on Windows 11.
- Hotkeys do not work over an elevated window unless skok runs elevated.
- `Win + L` always locks the PC and cannot be a hotkey.

## Alternatives

For tiling, layouts or workspaces, see [Komorebi](https://github.com/LGUG2Z/komorebi), [GlazeWM](https://github.com/glzr-io/glazewm) or [harken](https://github.com/grantith/harken) (also AutoHotkey-based).

Licensed under the [MIT License](LICENSE).
