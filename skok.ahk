#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\window-theme.ahk
#Include %A_ScriptDir%\cycle-strip.ahk
#Include %A_ScriptDir%\window-search.ahk

; Jump between windows from the keyboard (never moves or resizes them):
; - super + <key>: focus an app's most recently used window, otherwise launch it
; - super + <previous_window_hotkey>: toggle to the previously focused window (default: Tab)
; - super + <new_instance_modifier> + <key>: launch a new instance of the app (default modifier: shift)
; - super + <close_window_hotkey>: close the active window (default: Backspace)
; - repeated super + <app key>: cycle through that app's windows
; - super + j / k: cycle forward / backward through the current app's windows
; - super + l / h: cycle forward / backward through windows no [app.*] section matches
; - super + /: fuzzy-search all open windows and focus the pick

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
new_instance_modifier := settings.Get("new_instance_modifier", "Shift")
new_instance_modifier := modifier_prefixes.Get(StrLower(new_instance_modifier), new_instance_modifier)
show_cycle_titles := settings.Get("show_cycle_titles", "1")
if RegExMatch(show_cycle_titles, "i)^(1|true|yes|on)$")
    show_cycle_titles := true
else if RegExMatch(show_cycle_titles, "i)^(0|false|no|off)$")
    show_cycle_titles := false
else {
    errors.Push("Invalid show_cycle_titles '" show_cycle_titles "': use 1/0, true/false, yes/no or on/off.")
    show_cycle_titles := true
}

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
        if (StrLower(super_key) = "capslock")
            SetCapsLockState("AlwaysOff")
    } catch as err {
        errors.Push("Invalid super_key '" super_key "': " err.Message)
    }
}

SetWinDelay(10)
configured_apps := []
unconfigured_cycle := []
cycle_session := false
cycle_origin := 0
cycle_origin_previous := 0
InitializeWindowHistory()
DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
OnMessage(DllCall("RegisterWindowMessage", "Str", "SHELLHOOK", "UInt"), OnShellMessage)

used_hotkeys := Map()
if super_valid {
    if (super_prefix = "")
        HotIf(IsSuperPressed)

    ; [setting, default key, action]
    setting_hotkeys := [["previous_window_hotkey", "Tab", SwitchToPreviousWindow]
        , ["cycle_app_windows_hotkey", "j", CycleCurrentApp.Bind(1)]
        , ["reverse_cycle_app_windows_hotkey", "k", CycleCurrentApp.Bind(-1)]
        , ["cycle_unconfigured_hotkey", "l", CycleUnconfigured.Bind(1)]
        , ["reverse_cycle_unconfigured_hotkey", "h", CycleUnconfigured.Bind(-1)]
        , ["close_window_hotkey", "Backspace", CloseActiveWindow]
        , ["search_windows_hotkey", "/", SearchWindows]]
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
    sections := Map()
    sections.CaseSense := "Off"
    keys := 0
    Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if RegExMatch(line, "^\[(.*)\]\s*(;.*)?$", &m) {
            name := Trim(m[1])
            if !sections.Has(name) {
                sections[name] := Map()
                sections[name].CaseSense := "Off"
            }
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
    if (StrLower(super_key) = "win")
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

InitializeWindowHistory() {
    global current_window, previous_window
    current_window := GetActiveWindow()
    previous_window := 0

    hwnds := GetCycleableWindows("")
    if (index := IndexOf(hwnds, current_window)) {
        if (hwnds.Length > 1)
            previous_window := hwnds[Mod(index, hwnds.Length) + 1]
    } else if hwnds.Length {
        previous_window := hwnds[1]
    }
}

OnShellMessage(wParam, lParam, *) {
    if (wParam = 4 || wParam = 0x8004)  ; HSHELL_WINDOWACTIVATED, HSHELL_RUDEAPPACTIVATED
        TrackActiveWindow(lParam)
}

TrackActiveWindow(hwnd) {
    global current_window, previous_window
    hwnd := CycleableRoot(hwnd)
    if (!hwnd || hwnd = current_window)
        return
    ; Windows passed through while cycling are not picks; history is as if cycling started from the origin.
    if cycle_session {
        if (hwnd = cycle_origin)
            previous_window := cycle_origin_previous
        else
            previous_window := cycle_origin
    } else {
        previous_window := current_window
    }
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

SwitchToPreviousWindow(*) {
    active := GetActiveWindow()
    ; Account for an activation the shell hook has not delivered yet.
    TrackActiveWindow(active)
    StopCycleSession()

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
    active := GetActiveWindow()
    if IndexOf(hwnds, active) {
        BeginCycleSession(active)
        ActivateNextWindow(SortNumeric(hwnds), active, 1)
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

CycleCurrentApp(direction, *) {
    if !(active := GetActiveWindow())
        return
    try exe := WinGetProcessName(active)
    catch
        return

    hwnds := GetCycleableWindows("ahk_exe " exe)
    if (hwnds.Length < 2)
        return
    BeginCycleSession(active)
    ActivateNextWindow(SortNumeric(hwnds), active, direction)
}

; Cycling stays one session until super is released, so the previous window is where it started.
BeginCycleSession(active) {
    global cycle_session, cycle_origin, cycle_origin_previous
    if cycle_session
        return
    ; Account for an activation the shell hook has not delivered yet.
    TrackActiveWindow(active)
    cycle_session := true
    cycle_origin := active
    cycle_origin_previous := previous_window
    SetTimer(EndCycleSession, 30)
}

EndCycleSession() {
    if !IsSuperPressed()
        StopCycleSession()
}

StopCycleSession() {
    global cycle_session, cycle_origin, unconfigured_cycle
    cycle_session := false
    cycle_origin := 0
    unconfigured_cycle := []
    SetTimer(EndCycleSession, 0)
    CycleStrip.Hide()
}

; The unconfigured-only list is fixed on the first press of a session.
CycleUnconfigured(direction, *) {
    global unconfigured_cycle
    active := GetActiveWindow()
    if !unconfigured_cycle.Length {
        list := GetUnconfiguredWindows()
        if (!list.Length || (list.Length = 1 && list[1] = active))
            return
        ; A session without an origin would leave super + Tab nothing to return to.
        if (!active && !cycle_session) {
            ActivateNextWindow(list, active, direction)
            return
        }
        unconfigured_cycle := list
    }
    BeginCycleSession(active)
    ActivateNextWindow(unconfigured_cycle, active, direction)
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
    StopCycleSession()
    active := GetActiveWindow()
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
    WindowSearch.Show(entries, ActivateWindow)
}

IsCloaked(hwnd) {
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
    return cloaked != 0
}

CloseActiveWindow(*) {
    global unconfigured_cycle
    ; Keep the session so history still points at its origin, but drop views of the closed window.
    unconfigured_cycle := []
    CycleStrip.Hide()
    ; Closing the desktop or taskbar would open the shutdown dialog.
    try {
        active := WinGetID("A")
        if CycleableRoot(active)
            WinClose(active)
    }
}

; Callers pass a stable order (e.g. by handle); z-order would just flip between the top two.
ActivateNextWindow(hwnds, active, direction) {
    current_index := IndexOf(hwnds, active)
    if (current_index = 0)
        next_index := direction > 0 ? 1 : hwnds.Length
    else
        next_index := Mod(current_index - 1 + direction + hwnds.Length, hwnds.Length) + 1
    ActivateWindow(hwnds[next_index])
    ; The release timer could otherwise end the session between this check and showing the strip.
    Critical
    if (cycle_session && show_cycle_titles)
        CycleStrip.Show(hwnds, IndexOf(hwnds, GetActiveWindow()))
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
