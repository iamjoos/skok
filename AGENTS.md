# AGENTS.md

Notes for coding agents working on skok. User-facing behavior is documented in [README.md](README.md); read the relevant section before changing behavior.

## What this is

skok is a keyboard-driven virtual desktop switcher for Windows, written in **AutoHotkey v2**. It uses `VirtualDesktopAccessor.dll` (third-party, MIT, git-ignored, not shipped) for virtual desktop APIs. The repo has no build step: run `skok.ahk` directly.

## Layout

| File | Role |
| --- | --- |
| `skok.ahk` | Entry point: reads the config, registers hotkeys, tracks window and desktop history, handles cycling and moving, and builds search entries (`SearchWindows`). Startup code is at the top and functions follow. |
| `virtual-desktops.ahk` | `VirtualDesktopAccessor`: a thin wrapper over the DLL. |
| `window-theme.ahk` | `WindowTheme`: colors (light/dark plus the Windows accent), DPI scaling, popup creation, shared row-cell helpers, icons and work areas. |
| `window-search.ahk` | `WindowSearch`: the `super + s` picker (fuzzy scoring, desktop-grouped rows, Ctrl+number picks, previews). |
| `cycle-strip.ahk` | `CycleStrip`: click-through title strip shown while cycling. |
| `window-peek.ahk` | `WindowPeek`: DWM-thumbnail preview of a window, drawn in place without activating it. |
| `window-outline.ahk` | `WindowOutline`: accent-colored outline around the previewed window. |
| `config.example.ini` | Default config, copied to `%LOCALAPPDATA%\skok\config.ini` on first launch. It documents every setting. |
| `tests\` | Standalone AHK test scripts (see below). |

## Running tests

AutoHotkey v2 isn't on PATH. Run one script at a time; exit code 0 means pass, and failures print the message and stack:

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut tests\window-search.ahk
```

| Test | Needs |
| --- | --- |
| `window-theme`, `window-search` | Nothing special (pure logic plus a small GUI). |
| `desktops`, `cycle-strip`, `window-search-history` | An interactive desktop. They use `FakeDesktops`, so real desktops are never switched. |
| `window-search-focus` | An interactive desktop. It spawns `window-search-fixture.ahk` as a separate process and moves windows across monitors. |
| `window-search-desktops` | The real DLL and at least 2 virtual desktops. It **switches real desktops** (and switches back). |

The GUI tests create windows, steal focus and send keys, so don't type while they run. Run them one at a time, not in parallel. As of Nov 2026, `window-search-history.ahk` fails at "Current-desktop shortcut did not cancel search to origin" on `HEAD` as well; that failure predates the window-search layout change.

There is no runner script and no CI. Run the tests that cover the files you touched.

### Test conventions

- `tests\lib.ahk` provides `Assert`, `AssertEqual`, `ReportError`, `AddTestWindows`, `PressEsc` and `FakeDesktops` (the fake `vd`).
- Tests that need `skok.ahk` functions declare the globals that skok's startup would set (`vd`, `super_key`, `cycle_session`, `desktop_focus`, ...). They then end with `ExitApp(exit_code)` followed by `#Include ..\skok.ahk` **at the bottom**. That loads the functions without running startup or registering hotkeys.
- Use `try ... catch ... finally` and destroy every test window in `finally`.
- Prefer driving real keys (`SendEvent`) over posting messages: the GUI dialog manager can consume Esc before `WM_KEYDOWN`.
- `WindowSearch.edit.Value := "..."` does **not** fire the Change event. Call `WindowSearch.Update()` afterwards.

## Code conventions

- AutoHotkey v2 only (`#Requires AutoHotkey v2.0`). Modules are classes with only static members and state; include them with `#Include %A_LineFile%\..\file.ahk`.
- snake_case for variables and fields; PascalCase for functions, methods and classes.
- Comments explain *why* or non-obvious Win32 behavior, one line where possible. Annotate Win32 constants inline, e.g. `SendMessage(0x171, ...)  ; STM_GETICON`. Don't add comments that restate the code.
- In AHK classes, a field can't share a name with a method because both live in one namespace.
- `StrSplit("", ":")` returns an **empty** array, so indexing `[1]` throws.

### Overlay UI (search, cycle strip)

- Popups use `-DPIScale`: layout is in physical pixels via `WindowTheme.Scale(n)`, while fonts still scale with DPI. Rows are `WindowTheme.row_pitch` apart.
- Controls are created once in `Build()` and rebuilt only when the size, capacity or theme signature changes (`WindowTheme.Refresh()` returns that signature; add any new color to it).
- Avoid flicker: change text only through `WindowTheme.SetText`/`SetIcon`, which skip unchanged values, and restyle a row only when its cached style state changes (`WindowSearch.Style`, `styles[]`).
- Colors come from `WindowTheme` (`text`, `muted_text`, `accent_text`, `divider`, `row_selected_*`, ...); never hard-code colors in a module.
- Row text is never bold (commit `9900945`). The only bold text is the desktop group headers in window search.
- The search window hides itself when it loses activation (`OnActivate`). Anything that activates another window, such as a screenshot helper, closes the picker.
- Peeks and outlines must never activate, move or resize the target window, and must stay click-through.

### Window search specifics

- Entries are `{hwnd, desktop, desktop_number, here, exe, title, current}` built in `SearchWindows()` (skok.ahk). `Prepare()` precomputes search text; `Filter()` orders or ranks them.
- With an empty query, `Update()` builds `lines` (desktop header lines plus entry lines). Headers are grouped by `here`, then by desktop number. Ranked (typed) results have no headers and show a right-aligned desktop tag.
- Result numbers, `selected` and Ctrl+number picks index `matches` (windows only); `line_of[index]` maps a window to its row line.

## Behavior invariants

- skok never tiles or resizes windows.
- A preview never activates anything. Only the accepted or cancelled outcome is activated, so window history and Alt+Tab order only see real choices.
- Cancelling search returns to the origin window. Other skok shortcuts cancel an open search first.
- Desktops are found by **name** (`[desktop.<name>]`), not by position.

## Docs and config

- When adding or changing a setting, update both `config.example.ini` (with a comment) and the README (Configuration or the relevant feature section). Invalid values are pushed to `errors` and reported at startup.
- Existing user configs are never migrated or overwritten.
- README style: short declarative sentences and backticked keys (`super + s`). Shortcut tables use `| Key | Action |`.

## Commits

Imperative, sentence-case subject without a trailing period (e.g. "Cancel window search when another skok shortcut runs"). For non-trivial changes, add a body explaining the problem and why the fix works.