#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_LineFile%\..\window-theme.ahk
#Include %A_LineFile%\..\cycle-strip.ahk
#Include %A_LineFile%\..\window-outline.ahk
#Include %A_LineFile%\..\window-search.ahk
#Include %A_LineFile%\..\virtual-desktops.ahk

; Switch virtual desktops from the keyboard; each desktop keeps its own window layout:
; - super + <key>: switch to that [desktop.*] section's desktop, or cycle its windows if already there
; - super + <move_window_modifier> + <key>: move the active window to that desktop and follow it (default modifier: alt)
; - super + <previous_desktop_hotkey>: toggle to the previous desktop (default: Tab)
; - super + <previous_window_hotkey>: toggle to the previously focused window, on any desktop (default: Space)
; - super + j / k: cycle forward / backward through windows on the current desktop
; - super + <pin_window_hotkey>: pin or unpin the active window on all desktops (default: p)
; - super + <close_window_hotkey>: close the active window (default: shift + Backspace)
; - super + s: fuzzy-search windows on all desktops and focus the pick
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
config_order := []
config := ReadConfig(config_path, errors, config_order)
settings := config.Get("settings", Map())

; Standard modifiers become native hotkey prefixes (e.g. !1) so the keyboard hook
; intercepts the combination before apps like VS Code can handle it.
modifier_prefixes := Map("alt", "!", "lalt", "<!", "ralt", ">!"
    , "ctrl", "^", "control", "^", "lctrl", "<^", "lcontrol", "<^", "rctrl", ">^", "rcontrol", ">^"
    , "shift", "+", "lshift", "<+", "rshift", ">+", "win", "#", "lwin", "<#", "rwin", ">#")

dll_path := settings.Get("virtual_desktop_accessor", "") || "VirtualDesktopAccessor.dll"
; Relative paths are relative to skok.ahk, not the working directory.
if !RegExMatch(dll_path, "^([a-zA-Z]:)?[\\/]")
    dll_path := A_ScriptDir "\" dll_path
try vd := VirtualDesktopAccessor(dll_path)
catch as err {
    MsgBox("skok needs VirtualDesktopAccessor.dll and cannot start:`n`n" err.Message
        . "`n`nDownload it from https://github.com/Ciantic/VirtualDesktopAccessor/releases and put it next to skok.ahk,"
        . " or set virtual_desktop_accessor in " config_path ".", "skok", "Iconx")
    ExitApp()
}

super_key := settings.Get("super_key", "CapsLock")
move_window_modifier := settings.Get("move_window_modifier", InStr(super_key, "alt") ? "Shift" : "Alt")
move_window_modifier := modifier_prefixes.Get(StrLower(move_window_modifier), move_window_modifier)
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
cycle_session := false
cycle_selected := 0
desktop_focus := Map()
InitializeWindowHistory()
InitializeDesktopHistory()
DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
OnMessage(DllCall("RegisterWindowMessage", "Str", "SHELLHOOK", "UInt"), OnShellMessage)
desktop_message := 0x8000 + 0x5D0  ; WM_APP + n; the DLL posts it on every desktop switch
OnMessage(desktop_message, OnDesktopChanged)
vd.Listen(A_ScriptHwnd, desktop_message)
OnMessage(DllCall("RegisterWindowMessage", "Str", "TaskbarCreated", "UInt"), OnExplorerRestarted)

desktop_sections := ParseDesktops(config, config_order, errors)
PrepareDesktops(desktop_sections, errors)

used_hotkeys := Map()
if super_valid {
    if (super_prefix = "")
        HotIf(IsSuperPressed)

    ; [setting, default key, action]
    setting_hotkeys := [["previous_desktop_hotkey", "Tab", SwitchToPreviousDesktop]
        , ["previous_window_hotkey", "Space", SwitchToPreviousWindow]
        , ["cycle_windows_hotkey", "j", CycleWindows.Bind(1)]
        , ["reverse_cycle_windows_hotkey", "k", CycleWindows.Bind(-1)]
        , ["pin_window_hotkey", "p", TogglePinActiveWindow]
        , ["close_window_hotkey", "+Backspace", CloseActiveWindow]
        , ["search_windows_hotkey", "s", SearchWindows]]
    for _, h in setting_hotkeys
        RegisterHotkey(settings.Get(h[1], h[2]), h[3], h[1], used_hotkeys, errors)

    for _, d in desktop_sections {
        RegisterHotkey(d.hotkey, GoToDesktop.Bind(d), d.section, used_hotkeys, errors)
        RegisterHotkey(move_window_modifier d.hotkey, MoveActiveWindow.Bind(d), d.section " move window", used_hotkeys, errors)
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

; Reads an INI file as UTF-8 (or UTF-16 with BOM), keeping quotes in values. Section names are appended to order
; as first seen, since a Map enumerates them sorted.
ReadConfig(path, errors, order := []) {
    sections := CaselessMap()
    keys := 0
    Loop Parse FileRead(path, "UTF-8"), "`n", "`r" {
        line := Trim(A_LoopField)
        if (line = "" || SubStr(line, 1, 1) = ";")
            continue
        if RegExMatch(line, "^\[(.*)\]\s*(;.*)?$", &m) {
            name := Trim(m[1])
            if !sections.Has(name) {
                sections[name] := CaselessMap()
                order.Push(name)
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

; [desktop.<name>] sections in config order; the order sets each desktop's initial position in Task View.
ParseDesktops(config, order, errors) {
    result := []
    names := CaselessMap()
    for _, section in order {
        if !RegExMatch(section, "i)^desktop\.(.*)$", &m)
            continue
        name := Trim(m[1])
        desktop_hotkey := config[section].Get("hotkey", "")
        if (name = "" || desktop_hotkey = "") {
            errors.Push("[" section "] requires a name after desktop. and a hotkey.")
            continue
        }
        if names.Has(name) {
            errors.Push("[" section "] names the same desktop as [" names[name] "].")
            continue
        }
        names[name] := section
        result.Push({section: section, name: name, hotkey: desktop_hotkey, position: result.Length})
    }
    return result
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
    if !hwnd
        return
    ; An active window is on the current desktop, so restoring this desktop focuses it again.
    if ((number := vd.Current()) >= 0)
        desktop_focus[number] := hwnd
    if (hwnd = current_window)
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
    WindowSearch.Cancel()
    active := SyncActiveWindow()
    return cycle_session && cycle_selected ? cycle_selected : active
}

SwitchToPreviousWindow(*) {
    StopCycleSession()
    active := SyncActiveWindow()

    target := previous_window
    if (!target || target = active || WindowDesktop(target) < 0) {
        ; The previous window is gone; fall back to the most recently used other window on this desktop.
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
        FocusWindow(target)
}

InitializeDesktopHistory() {
    global current_desktop, previous_desktop
    current_desktop := vd.Current()
    previous_desktop := -1
}

; The message's desktop numbers can be stale when switches overlap, so read the current desktop instead.
OnDesktopChanged(*) => SyncDesktop()

; Explorer restarts recreate the virtual desktop service.
OnExplorerRestarted(*) {
    vd.Restart()
    vd.Listen(A_ScriptHwnd, desktop_message)
    SyncDesktop()
}

; Only a change of desktop counts; focus changes within a desktop leave the history alone.
TrackDesktop(number) {
    global current_desktop, previous_desktop
    if (number < 0 || number = current_desktop)
        return
    previous_desktop := current_desktop
    current_desktop := number
}

; Account for a switch whose notification has not arrived yet.
SyncDesktop() => TrackDesktop(vd.Current())

SwitchToPreviousDesktop(*) {
    StopCycleSession()
    SyncDesktop()
    if (previous_desktop >= 0 && previous_desktop != current_desktop && previous_desktop < vd.Count())
        SwitchDesktop(previous_desktop)
}

; Gives each section a desktop: one already named after it, wherever it is; else the desktop at the section's
; position unless another section's name is on it; else a new desktop.
PrepareDesktops(sections, errors) {
    names := CaselessMap()
    for _, d in sections
        names[d.name] := true
    for _, d in sections {
        if (FindDesktop(d.name) >= 0)
            continue
        if (d.position < vd.Count() && !names.Has(vd.Name(d.position)))
            vd.SetName(d.position, d.name)
        else if (AddDesktop(d.name) < 0)
            errors.Push("Could not create a virtual desktop for [" d.section "].")
    }
}

; The desktop's position in Task View, or -1 if no desktop has the name.
FindDesktop(name) {
    Loop vd.Count() {
        if (vd.Name(A_Index - 1) = name)
            return A_Index - 1
    }
    return -1
}

; The section's desktop, recreated at the end if it was removed or renamed; -1 if that fails.
ResolveDesktop(d) {
    number := FindDesktop(d.name)
    return number >= 0 ? number : AddDesktop(d.name)
}

AddDesktop(name) {
    count := vd.Count()
    vd.Create()
    if (vd.Count() <= count)
        return -1
    vd.SetName(count, name)
    return count
}

GoToDesktop(d, *) {
    number := ResolveDesktop(d)
    if (number >= 0 && number = vd.Current()) {
        CycleWindows(1)
        return
    }
    StopCycleSession()
    if (number >= 0)
        SwitchDesktop(number)
}

; Switches desktops and focuses target there.
SwitchDesktop(number, target := 0) {
    if !target
        target := DesktopFocusTarget(number, DesktopWindows(number))
    if (number = vd.Current()) {
        ; Already here: only take focus back from the taskbar or the Windows desktop.
        if (target && !GetActiveWindow())
            ActivateWindow(target)
        return
    }
    vd.GoTo(number)
    SyncDesktop()
    if (target && target != GetActiveWindow())
        ActivateWindow(target)
}

; The window last focused on the desktop if it is still there, else its topmost window.
DesktopFocusTarget(number, windows) {
    if desktop_focus.Has(number) {
        remembered := desktop_focus[number]
        if (IndexOf(windows, remembered) || WinExist(remembered) && IsTaskWindow(remembered) && vd.IsPinned(remembered))
            return remembered
    }
    return windows.Length ? windows[1] : 0
}

; Windows on the desktop in z-order (most recently used first), excluding windows pinned to all desktops.
DesktopWindows(number) {
    result := []
    for _, hwnd in WinGetList() {
        if (IsTaskWindow(hwnd) && !(CloakFlags(hwnd) & ~2) && vd.WindowDesktop(hwnd) = number && !vd.IsPinned(hwnd))
            result.Push(hwnd)
    }
    return result
}

; The desktop the window is on: the current one if it is visible here, -1 if it is on none.
WindowDesktop(hwnd) {
    if !(WinExist(hwnd) && IsTaskWindow(hwnd))
        return -1
    cloak := CloakFlags(hwnd)
    if !cloak
        return vd.Current()
    ; Windows on other desktops are cloaked by the shell only; others (e.g. suspended UWP apps) are hidden.
    return cloak = 2 ? vd.WindowDesktop(hwnd) : -1
}

; Focuses a window on any desktop, switching to its desktop first.
FocusWindow(hwnd) {
    number := WindowDesktop(hwnd)
    if (number >= 0 && number != vd.Current())
        SwitchDesktop(number, hwnd)
    else
        ActivateWindow(hwnd)
}

; Moves the active window to the desktop and follows it there.
MoveActiveWindow(d, *) {
    StopCycleSession()
    if (!(hwnd := SyncActiveWindow()) || (number := ResolveDesktop(d)) < 0)
        return
    ; A pinned window is already on every desktop.
    if (!vd.IsPinned(hwnd) && vd.WindowDesktop(hwnd) != number && vd.MoveWindow(hwnd, number) < 0)
        return
    desktop_focus[number] := hwnd
    SwitchDesktop(number, hwnd)
}

TogglePinActiveWindow(*) {
    StopCycleSession()
    if (hwnd := SyncActiveWindow())
        ShowNotice(vd.TogglePin(hwnd) ? "Pinned to all desktops" : "Unpinned", hwnd)
}

; Pinning has no visible effect, so confirm it briefly over the window.
ShowNotice(text, hwnd) {
    CoordMode("ToolTip", "Screen")
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        ToolTip(text, x + w // 2, y + h // 2)
    } catch {
        ToolTip(text)
    }
    SetTimer(HideNotice, -1000)
}

HideNotice() => ToolTip()

SendKeys(keys, *) {
    StopCycleSession()
    Send(keys)
}

; Windows on the current desktop in handle order, for a stable sequence.
CycleWindows(direction, *) {
    current := CycleSelection()
    hwnds := SortNumeric(GetCycleableWindows(""))
    if (!hwnds.Length || hwnds.Length = 1 && hwnds[1] = current)
        return
    BeginCycleSession()
    SelectNextWindow(hwnds, current, direction)
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
    global cycle_session, cycle_selected
    WindowSearch.Cancel()
    selected := cycle_session ? cycle_selected : 0
    cycle_session := false
    cycle_selected := 0
    SetTimer(EndCycleSession, 0)
    ; Activate under the peek so the switch doesn't flash the previous window.
    if (selected && selected != GetActiveWindow() && WinExist(selected))
        ActivateWindow(selected)
    CycleStrip.Reset()
    WindowOutline.Hide()
    WindowPeek.Hide()
}

; Lists windows on all desktops; keep active last for fuzzy-score ties (the picker puts it first when the query is empty).
SearchWindows(*) {
    if WindowSearch.active {
        WindowSearch.Cancel()
        return
    }
    StopCycleSession()
    active := SyncActiveWindow()
    here := vd.Current()
    labels := Map()
    entries := []
    last := 0
    ; AHK treats shell-cloaked windows on other desktops as hidden during enumeration.
    detect := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try hwnds := WinGetList()
    finally DetectHiddenWindows(detect)
    for _, hwnd in hwnds {
        if ((number := WindowDesktop(hwnd)) < 0)
            continue
        if !labels.Has(number)
            labels[number] := DesktopLabel(number)
        try entry := {hwnd: hwnd, desktop: labels[number], desktop_number: number, here: number = here, title: WinGetTitle(hwnd)
            , exe: WinGetProcessName(hwnd), current: hwnd = active}
        catch
            continue
        if (hwnd = active)
            last := entry
        else
            entries.Push(entry)
    }
    if last
        entries.Push(last)
    ; Cancelling from the taskbar or desktop returns to the last focused window, unless that is on another desktop.
    origin := !active && WindowDesktop(current_window) = here ? current_window : 0
    WindowSearch.Show(entries, FocusWindow, origin)
}

DesktopLabel(number) {
    name := vd.Name(number)
    return name != "" ? (number + 1) ": " name : "Desktop " (number + 1)
}

IsCloaked(hwnd) => CloakFlags(hwnd) != 0

; DWM_CLOAKED_APP (1), DWM_CLOAKED_SHELL (2), DWM_CLOAKED_INHERITED (4).
CloakFlags(hwnd) {
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &cloaked, "UInt", 4)
    return cloaked
}

CloseActiveWindow(*) {
    global cycle_selected
    WindowSearch.Cancel()
    ; While cycling, close the previewed window; the session continues from the active one.
    target := cycle_session ? cycle_selected : 0
    cycle_selected := 0
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

; Windows on the current desktop that approximate the Alt+Tab list.
IsCycleableWindow(hwnd) => IsTaskWindow(hwnd) && !IsCloaked(hwnd)

; Visible, titled, activatable top-level windows on any desktop.
IsTaskWindow(hwnd) {
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
    return true
}

ActivateWindow(hwnd) {
    try {
        if (WinGetMinMax(hwnd) = -1)
            WinRestore(hwnd)
        ; A window disabled by a modal dialog can't take focus; activate the dialog instead.
        if (WinGetStyle(hwnd) & 0x8000000)  ; WS_DISABLED
            hwnd := DllCall("GetLastActivePopup", "Ptr", hwnd, "Ptr")
        ; WinActivate sleeps ~15 ms plus WinDelay; it's only needed if Windows refuses the direct call.
        if (DllCall("SetForegroundWindow", "Ptr", hwnd) && DllCall("GetForegroundWindow", "Ptr") = hwnd)
            return
        WinActivate(hwnd)
        ; A refused SetForegroundWindow flashes the taskbar button; the window is now active, so that highlight is stale.
        if (DllCall("GetForegroundWindow", "Ptr") = hwnd)
            StopFlashing(hwnd)
    }
}

StopFlashing(hwnd) {
    info := Buffer(A_PtrSize = 8 ? 32 : 20, 0)  ; FLASHWINFO
    NumPut("UInt", info.Size, info, 0)
    NumPut("Ptr", hwnd, info, A_PtrSize)
    NumPut("UInt", 0, info, A_PtrSize * 2)  ; FLASHW_STOP
    DllCall("FlashWindowEx", "Ptr", info)
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
