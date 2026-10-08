#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_LineFile%\..\window-theme.ahk
#Include %A_LineFile%\..\cycle-strip.ahk
#Include %A_LineFile%\..\window-outline.ahk
#Include %A_LineFile%\..\window-search.ahk

; Jump between windows from the keyboard (never moves or resizes them):
; - super + <key>: focus an app's most recently used window, otherwise launch it
; - super + <previous_window_hotkey>: toggle to the previously focused window (default: Space)
; - super + <new_instance_modifier> + <key>: launch a new instance of the app (default modifier: alt)
; - super + <close_window_hotkey>: close the active window (default: shift + Backspace)
; - repeated super + <app key>: cycle through that app's windows
; - super + j / k: cycle forward / backward through the current app's windows
; - super + l / h: cycle forward / backward through windows no [app.*] section matches
; - super + s: fuzzy-search all open windows and focus the pick
; - super + <key> in a [send.*] section: send keystrokes, e.g. another app's global shortcut

config_dir := EnvGet("LOCALAPPDATA") "\skok"
DirCreate(config_dir)
config_path := config_dir "\config.ini"
if !FileExist(config_path) {
    try FileCopy(A_ScriptDir "\config.example.ini", config_path)
    catch as err {
        MsgBox("Could not create " config_path ":`n" err.Message, "skok", "Iconx")
        ExitApp()
    }
}
errors := []
config := ReadConfig(config_path, errors)
settings := config.Get("settings", Map())

; Standard modifiers become native hotkey prefixes (e.g. !1) so the keyboard hook
; intercepts the combination before apps like VS Code can handle it.
modifier_prefixes := Map("alt", "!", "lalt", "<!", "ralt", ">!"
    , "ctrl", "^", "control", "^", "lctrl", "<^", "lcontrol", "<^", "rctrl", ">^", "rcontrol", ">^"
    , "shift", "+", "lshift", "<+", "rshift", ">+", "win", "#", "lwin", "<#", "rwin", ">#")

super_key := settings.Get("super_key", "CapsLock")
new_instance_modifier := settings.Get("new_instance_modifier", InStr(super_key, "alt") ? "Shift" : "Alt")
new_instance_modifier := modifier_prefixes.Get(StrLower(new_instance_modifier), new_instance_modifier)
show_cycle_titles := BoolSetting(settings, "show_cycle_titles", true, errors)
WindowOutline.enabled := BoolSetting(settings, "highlight_selection", true, errors)
WindowSearch.previews := BoolSetting(settings, "preview_search_selection", true, errors)

try WindowTheme.SetDisplay(settings.Get("overlay_display", "primary"))
catch as err
    errors.Push(err.Message)

try WindowTheme.SetMode(settings.Get("theme", "system"))
catch as err
    errors.Push(err.Message)

super_prefix := modifier_prefixes.Get(StrLower(super_key), "")
super_valid := super_prefix != ""
if !super_valid {
    ; Block the super key's native behavior so it acts purely as a modifier.
    try {
        if (GetKeyName(super_key) = "")
            throw ValueError("Unknown key name.")
        Hotkey("*" super_key, (*) => "")
        super_valid := true
        if (super_key = "capslock")
            SetCapsLockState("AlwaysOff")
    } catch as err {
        errors.Push("Invalid super_key '" super_key "': " err.Message)
    }
}

SetWinDelay(10)
configured_apps := []
unconfigured_cycle := []
cycle_session := false
cycle_selected := 0
InitializeWindowHistory()
DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
OnMessage(DllCall("RegisterWindowMessage", "Str", "SHELLHOOK", "UInt"), OnShellMessage)

used_hotkeys := Map()
if super_valid {
    if (super_prefix = "")
        HotIf(IsSuperPressed)

    ; [setting, default key, action]
    setting_hotkeys := [["previous_window_hotkey", "Space", SwitchToPreviousWindow]
        , ["cycle_app_windows_hotkey", "j", CycleCurrentApp.Bind(1)]
        , ["reverse_cycle_app_windows_hotkey", "k", CycleCurrentApp.Bind(-1)]
        , ["cycle_unconfigured_hotkey", "l", CycleUnconfigured.Bind(1)]
        , ["reverse_cycle_unconfigured_hotkey", "h", CycleUnconfigured.Bind(-1)]
        , ["close_window_hotkey", "+Backspace", CloseActiveWindow]
        , ["search_windows_hotkey", "s", SearchWindows]]
    for _, h in setting_hotkeys
        RegisterHotkey(settings.Get(h[1], h[2]), h[3], h[1], used_hotkeys, errors)

    for section, keys in config {
        if !RegExMatch(section, "i)^app\.")
            continue
        app_hotkey := keys.Get("hotkey", "")
        win_title := keys.Get("match", "")
        run_cmd := keys.Get("run", "")
        new_instance_run := keys.Get("new_instance_run", "") || run_cmd
        run_dir := keys.Get("run_dir", "")
        if (app_hotkey = "" || win_title = "" || run_cmd = "") {
            errors.Push("[" section "] requires hotkey, match and run.")
            continue
        }
        configured_apps.Push({name: SubStr(section, 5), match: win_title})
        RegisterHotkey(app_hotkey, FocusOrRun.Bind(win_title, run_cmd, run_dir), section, used_hotkeys, errors)
        RegisterHotkey(new_instance_modifier app_hotkey, LaunchApp.Bind(new_instance_run, run_dir), section " new instance", used_hotkeys, errors)
    }

    for section, keys in config {
        if !RegExMatch(section, "i)^send\.")
            continue
        send_hotkey := keys.Get("hotkey", "")
        send_keys := keys.Get("keys", "")
        if (send_hotkey = "" || send_keys = "") {
            errors.Push("[" section "] requires hotkey and keys.")
            continue
        }
        RegisterHotkey(send_hotkey, SendKeys.Bind(send_keys), section, used_hotkeys, errors)
    }

    HotIf()
}

if errors.Length {
    msg := "Config problems in " config_path ":`n`n"
    for _, err in errors
        msg .= "- " err "`n"
    MsgBox(msg, "skok", "Icon!")
}

A_TrayMenu.Add()
A_TrayMenu.Add("Edit config", (*) => Run('notepad.exe "' config_path '"'))

; Reads an INI file as UTF-8 (or UTF-16 with BOM), keeping quotes in values.
ReadConfig(path, errors) {
    sections := CaselessMap()
    keys := 0
    Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if RegExMatch(line, "^\[(.*)\]\s*(;.*)?$", &m) {
            name := Trim(m[1])
            if !sections.Has(name)
                sections[name] := CaselessMap()
            keys := sections[name]
        } else if (keys && (eq := InStr(line, "="))) {
            keys[Trim(SubStr(line, 1, eq - 1))] := Trim(SubStr(line, eq + 1))
        } else {
            errors.Push("Line " A_Index " is not a [section] or key=value: " line)
            ; Keep keys under a bad header out of the previous section.
            if (SubStr(line, 1, 1) = "[")
                keys := Map()
        }
    }
    return sections
}

CaselessMap() {
    m := Map()
    m.CaseSense := "Off"
    return m
}

BoolSetting(settings, name, default, errors) {
    if !settings.Has(name)
        return default
    value := settings[name]
    if RegExMatch(value, "i)^(1|true|yes|on)$")
        return true
    if RegExMatch(value, "i)^(0|false|no|off)$")
        return false
    errors.Push("Invalid " name " '" value "': use 1/0, true/false, yes/no or on/off.")
    return default
}

RegisterHotkey(key, callback, owner, used_hotkeys, errors) {
    key := "$" super_prefix key
    id := HotkeyId(key, &mods, &name)
    if (id = "") {
        errors.Push("Hotkey '" key "' in " owner " repeats a modifier.")
        return
    }
    if (InStr(mods, "#") && name = "l") {
        errors.Push("Hotkey '" key "' in " owner " is Win+L, which Windows reserves for locking the PC.")
        return
    }
    if used_hotkeys.Has(id) {
        errors.Push("Hotkey '" key "' in " owner " already used by " used_hotkeys[id] ".")
        return
    }
    try {
        Hotkey(key, callback)
        used_hotkeys[id] := owner
    } catch as err {
        errors.Push("Invalid hotkey '" key "' in " owner ": " err.Message)
    }
}

; Sorted modifiers plus the normalized key name (Return -> enter), or "" if a modifier repeats.
HotkeyId(key, &mods := "", &name := "") {
    mods := ""
    sorted := ""
    pos := 1
    while RegExMatch(key, "\G[<>]?([#!^+*~$])", &m, pos) && pos + m.Len <= StrLen(key) {
        if InStr(mods, m[1])
            return ""
        mods .= m[1]
        sorted .= m[0] "`n"
        pos += m.Len
    }
    name := SubStr(key, pos)
    name := StrLower(GetKeyName(Format("vk{:x}sc{:x}", GetKeyVK(name), GetKeySC(name))) || name)
    return Sort(sorted) name
}

IsSuperPressed(*) {
    if (super_key = "win")
        return GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    return GetKeyState(super_key, "P")
}

IndexOf(items, value) {
    for i, item in items {
        if (item = value)
            return i
    }
    return 0
}

WrapIndex(index, step, count) => Mod(index - 1 + step + count, count) + 1

InitializeWindowHistory() {
    global current_window, previous_window
    current_window := GetActiveWindow()
    previous_window := 0

    hwnds := GetCycleableWindows("")
    if (index := IndexOf(hwnds, current_window)) {
        if (hwnds.Length > 1)
            previous_window := hwnds[WrapIndex(index, 1, hwnds.Length)]
    } else if hwnds.Length {
        previous_window := hwnds[1]
    }
}

OnShellMessage(wParam, lParam, *) {
    ; Notifications can arrive late; only track the window still active.
    if ((wParam = 4 || wParam = 0x8004) && CycleableRoot(lParam) = GetActiveWindow())  ; HSHELL_WINDOWACTIVATED, HSHELL_RUDEAPPACTIVATED
        TrackActiveWindow(lParam)
}

TrackActiveWindow(hwnd) {
    global current_window, previous_window
    hwnd := CycleableRoot(hwnd)
    if (!hwnd || hwnd = current_window)
        return
    previous_window := current_window
    current_window := hwnd
}

; The window itself, or its owner for a dialog; 0 if neither can be cycled.
CycleableRoot(hwnd) {
    if IsCycleableWindow(hwnd)
        return hwnd
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 3, "Ptr")  ; GA_ROOTOWNER
    return (root && root != hwnd && IsCycleableWindow(root)) ? root : 0
}

GetActiveWindow() {
    try return CycleableRoot(WinGetID("A"))
    return 0
}

; Account for an activation the shell hook has not delivered yet.
SyncActiveWindow() {
    TrackActiveWindow(active := GetActiveWindow())
    return active
}

; While cycling, the previewed selection stands in for the active window.
CycleSelection() {
    active := SyncActiveWindow()
    return cycle_session && cycle_selected ? cycle_selected : active
}

SwitchToPreviousWindow(*) {
    StopCycleSession()
    active := SyncActiveWindow()

    target := previous_window
    if (!target || target = active || !IsCycleableWindow(target)) {
        ; The previous window is gone; fall back to the most recently used other window.
        target := 0
        for _, hwnd in GetCycleableWindows("") {
            if (hwnd != active) {
                target := hwnd
                break
            }
        }
    }
    ; History is updated by the shell hook, so a failed activation leaves it intact.
    if target
        ActivateWindow(target)
}

FocusOrRun(win_title, run_cmd, run_dir, *) {
    hwnds := GetCycleableWindows(win_title)
    if !hwnds.Length {
        LaunchApp(run_cmd, run_dir)
        return
    }
    current := CycleSelection()
    if IndexOf(hwnds, current) {
        BeginCycleSession()
        SelectNextWindow(SortNumeric(hwnds), current, 1)
        return
    }
    ; WinGetList returns windows in z-order, so the first is the most recently used.
    StopCycleSession()
    ActivateWindow(hwnds[1])
}

LaunchApp(run_cmd, run_dir, *) {
    StopCycleSession()
    try Run(run_cmd, run_dir)
    catch as err {
        MsgBox("Failed to launch: " run_cmd "`n" err.Message, "skok", "Iconx")
    }
}

SendKeys(keys, *) {
    StopCycleSession()
    Send(keys)
}

CycleCurrentApp(direction, *) {
    if !(current := CycleSelection())
        return
    try exe := WinGetProcessName(current)
    catch
        return

    hwnds := GetCycleableWindows("ahk_exe " exe)
    if (hwnds.Length < 2)
        return
    BeginCycleSession()
    SelectNextWindow(SortNumeric(hwnds), current, direction)
}

; Cycling previews windows until super is released; only the final selection is activated,
; so history and the Windows Alt+Tab order skip the windows passed through.
BeginCycleSession() {
    global cycle_session, cycle_selected
    if cycle_session
        return
    cycle_session := true
    cycle_selected := 0
    CycleStrip.Begin()
    SetTimer(EndCycleSession, 30)
}

EndCycleSession() {
    if !IsSuperPressed()
        StopCycleSession()
}

; Other hotkeys end the session too, so they act on the selected window.
StopCycleSession() {
    global cycle_session, cycle_selected, unconfigured_cycle
    selected := cycle_session ? cycle_selected : 0
    cycle_session := false
    cycle_selected := 0
    unconfigured_cycle := []
    SetTimer(EndCycleSession, 0)
    ; Activate under the peek so the switch doesn't flash the previous window.
    if (selected && selected != GetActiveWindow() && WinExist(selected))
        ActivateWindow(selected)
    CycleStrip.Reset()
    WindowOutline.Hide()
    WindowPeek.Hide()
}

; The unconfigured-only list is fixed on the first press of a session.
CycleUnconfigured(direction, *) {
    global unconfigured_cycle
    current := CycleSelection()
    if !unconfigured_cycle.Length {
        list := GetUnconfiguredWindows()
        if (!list.Length || (list.Length = 1 && list[1] = current))
            return
        unconfigured_cycle := list
    }
    BeginCycleSession()
    SelectNextWindow(unconfigured_cycle, current, direction)
}

; Cycleable windows no [app.*] match covers, in handle order.
GetUnconfiguredWindows() {
    result := []
    for _, hwnd in SortNumeric(GetCycleableWindows("")) {
        if (ConfiguredAppName(hwnd) = "")
            result.Push(hwnd)
    }
    return result
}

; The name of the first [app.<name>] section whose match covers the window, or "".
ConfiguredAppName(hwnd) {
    for _, app in configured_apps {
        if WinExist(app.match " ahk_id " hwnd)
            return app.name
    }
    return ""
}

; Keep active last for fuzzy-score ties; the picker puts it first when the query is empty.
SearchWindows(*) {
    if WindowSearch.active {
        WindowSearch.Cancel()
        return
    }
    StopCycleSession()
    active := SyncActiveWindow()
    entries := []
    last := 0
    for _, hwnd in GetCycleableWindows("") {
        try entry := {hwnd: hwnd, app: ConfiguredAppName(hwnd), title: WinGetTitle(hwnd)
            , exe: RegExReplace(WinGetProcessName(hwnd), "i)\.exe$"), current: hwnd = active}
        catch
            continue
        if (hwnd = active)
            last := entry
        else
            entries.Push(entry)
    }
    if last
        entries.Push(last)
    ; Cancelling from the taskbar or desktop returns to the last focused window.
    WindowSearch.Show(entries, ActivateWindow, active ? 0 : current_window)
}

IsCloaked(hwnd) {
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
    return cloaked != 0
}

CloseActiveWindow(*) {
    global unconfigured_cycle, cycle_selected
    ; While cycling, close the previewed window; the session continues from the active one.
    target := cycle_session ? cycle_selected : 0
    cycle_selected := 0
    unconfigured_cycle := []
    CycleStrip.Hide()
    WindowOutline.Hide()
    WindowPeek.Hide()
    try {
        if !target {
            target := WinGetID("A")
            ; Closing the desktop or taskbar would open the shutdown dialog.
            if !CycleableRoot(target)
                return
        }
        WinClose(target)
    }
}

; Callers start a session first and pass a stable order (e.g. by handle).
SelectNextWindow(hwnds, current, direction) {
    global cycle_selected
    current_index := IndexOf(hwnds, current)
    if (current_index = 0)
        next_index := direction > 0 ? 1 : hwnds.Length
    else
        next_index := WrapIndex(current_index, direction, hwnds.Length)
    ; The release timer could otherwise end the session between selecting and showing overlays.
    Critical
    cycle_selected := hwnds[next_index]
    if (hwnds.Length < 2)
        return
    if show_cycle_titles
        CycleStrip.Show(hwnds, next_index)
    strip := CycleStrip.window && DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd) ? CycleStrip.window.Hwnd : 0
    if WindowPeek.Show(cycle_selected, strip)
        WindowOutline.Show(WindowPeek.window.Hwnd, strip)
    else
        WindowOutline.Hide()
}

GetCycleableWindows(win_title) {
    result := []
    for _, hwnd in WinGetList(win_title) {
        if IsCycleableWindow(hwnd)
            result.Push(hwnd)
    }
    return result
}

; Approximates the Alt+Tab list: visible, titled, activatable top-level windows.
IsCycleableWindow(hwnd) {
    try {
        style := WinGetStyle(hwnd)
        ex_style := WinGetExStyle(hwnd)
        class_name := WinGetClass(hwnd)
        title := WinGetTitle(hwnd)
    } catch {
        return false
    }
    if !(style & 0x10000000)                         ; WS_VISIBLE
        return false
    if (ex_style & 0x80) || (ex_style & 0x8000000)   ; WS_EX_TOOLWINDOW, WS_EX_NOACTIVATE
        return false
    if (title = "")
        return false
    ; Dialogs belong to their owner; a hidden owner (e.g. Delphi apps) leaves the window top-level.
    owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER
    if (owner && !(ex_style & 0x40000) && DllCall("IsWindowVisible", "Ptr", owner))  ; WS_EX_APPWINDOW
        return false
    if RegExMatch(class_name, "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$")
        return false
    ; Excludes windows on other virtual desktops and suspended UWP apps.
    return !IsCloaked(hwnd)
}

ActivateWindow(hwnd) {
    try {
        if (WinGetMinMax(hwnd) = -1)
            WinRestore(hwnd)
        ; A window disabled by a modal dialog can't take focus; activate the dialog instead.
        if (WinGetStyle(hwnd) & 0x8000000)  ; WS_DISABLED
            hwnd := DllCall("GetLastActivePopup", "Ptr", hwnd, "Ptr")
        ; WinActivate sleeps ~15 ms plus WinDelay; it's only needed if Windows refuses the direct call.
        if !(DllCall("SetForegroundWindow", "Ptr", hwnd) && DllCall("GetForegroundWindow", "Ptr") = hwnd)
            WinActivate(hwnd)
    }
}

SortNumeric(hwnds) {
    ; A Map enumerates integer keys in ascending order.
    by_value := Map()
    for _, hwnd in hwnds
        by_value[hwnd] := true
    sorted := []
    for hwnd in by_value
        sorted.Push(hwnd)
    return sorted
}
