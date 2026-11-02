#Requires AutoHotkey v2.0
#Include lib.ahk

; Desktop history, name lookup, moves and pinning, against a fake desktop service.
original := WinExist("A")
windows := []
cycle_session := false
cycle_selected := 0
show_cycle_titles := true
super_key := "F24"
super_prefix := ""
vd := FakeDesktops(3)
desktop_focus := Map()
config_file := A_Temp "\skok-desktops-test.ini"
exit_code := 0
try {
    AddTestWindows(windows, "Desktop test", 3)
    a := windows[1].Hwnd, b := windows[2].Hwnd, c := windows[3].Hwnd
    WinActivate(c), WinActivate(b), WinActivate(a)
    InitializeWindowHistory()
    InitializeDesktopHistory()
    AssertEqual(current_desktop, 0)
    AssertEqual(previous_desktop, -1)

    ; Switch notifications drive the history from the actual desktop; stale or repeated ones change nothing.
    vd.at := 2
    OnDesktopChanged(0, 2)
    Assert(current_desktop = 2 && previous_desktop = 0, "Switch notification did not record the previous desktop")
    OnDesktopChanged(0, 1)
    Assert(current_desktop = 2 && previous_desktop = 0, "Stale notification changed the history")
    WinActivate(b), SyncActiveWindow()
    WinActivate(a), SyncActiveWindow()
    Assert(current_desktop = 2 && previous_desktop = 0, "Focus changes within a desktop changed the desktop history")
    AssertEqual(desktop_focus[2], a)

    ; Going back restores the window last focused on that desktop, then toggles.
    vd.MoveWindow(a, 2), vd.MoveWindow(b, 2)
    desktop_focus[0] := c
    SwitchToPreviousDesktop()
    Assert(vd.at = 0 && current_desktop = 0 && previous_desktop = 2, "Previous desktop did not switch back")
    Assert(WinActive(c), "Previous desktop did not focus its last window")
    SyncActiveWindow()
    SwitchToPreviousDesktop()
    Assert(vd.at = 2 && previous_desktop = 0 && WinActive(a), "Previous desktop did not toggle")
    ; A switch made outside skok (Win+Ctrl+Arrow) is picked up even before its notification arrives.
    vd.at := 1
    SwitchToPreviousDesktop()
    Assert(vd.at = 2 && previous_desktop = 1, "External switch was not tracked")
    ; A removed previous desktop is skipped.
    previous_desktop := 5
    switches := vd.switches.Length
    SwitchToPreviousDesktop()
    AssertEqual(vd.switches.Length, switches)

    ; A remembered window that moved away no longer wins; the desktop's topmost window does.
    vd.at := 0, TrackDesktop(0)
    desktop_focus[2] := c
    WinActivate(b)
    AssertEqual(DesktopFocusTarget(2, DesktopWindows(2)), b)

    ; Shortcuts find desktops by name, wherever they are now.
    vd.windows.Clear()
    vd.names := Map(0, "web", 1, "code", 2, "chat")
    WinActivate(a), SyncActiveWindow()
    MoveActiveWindow({name: "chat"})
    Assert(vd.WindowDesktop(a) = 2 && vd.at = 2, "Moving did not follow the window to its desktop")
    Assert(WinActive(a) && desktop_focus[2] = a, "Moved window lost focus")
    desktop_focus[0] := c
    GoToDesktop({name: "web"})
    Assert(vd.at = 0 && WinActive(c), "Desktop shortcut did not switch by name")
    vd.names := Map(0, "chat", 1, "code", 2, "web")
    GoToDesktop({name: "web"})
    Assert(vd.at = 2, "Desktop shortcut did not follow a reordered desktop")
    Assert(!cycle_session, "Switching desktops started cycling")

    ; Repeating the current desktop's shortcut previews a stable sequence, including wraparound.
    WinActivate(a), SyncActiveWindow()
    candidates := SortNumeric(GetCycleableWindows(""))
    selected_index := IndexOf(candidates, a)
    switches := vd.switches.Length
    from_desktop := previous_desktop
    Loop candidates.Length + 1 {
        GoToDesktop({name: "web"})
        SetTimer(EndCycleSession, 0)
        Critical "Off"
        selected_index := WrapIndex(selected_index, 1, candidates.Length)
        Assert(cycle_session && cycle_selected = candidates[selected_index], "Desktop shortcut did not advance or wrap")
        Assert(WinActive(a), "Desktop cycling focused a preview")
    }
    AssertEqual(vd.switches.Length, switches)
    AssertEqual(previous_desktop, from_desktop)
    selected := cycle_selected
    EndCycleSession()
    Assert(!cycle_session && WinActive(selected), "Release did not focus the desktop cycle selection")
    SyncActiveWindow()
    Assert(current_window = selected && previous_window = a, "Desktop cycling did not count as one window visit")

    ; A new press after releasing super continues from the focused window.
    GoToDesktop({name: "web"})
    SetTimer(EndCycleSession, 0)
    Critical "Off"
    selected_index := WrapIndex(selected_index, 1, candidates.Length)
    AssertEqual(cycle_selected, candidates[selected_index])
    EndCycleSession()
    Assert(WinActive(candidates[selected_index]), "A separate desktop shortcut press did not advance")

    ; A pinned window follows without being moved.
    WinActivate(b), SyncActiveWindow()
    TogglePinActiveWindow()
    Assert(vd.IsPinned(b), "Pin shortcut did not pin")
    moves := vd.windows.Count
    MoveActiveWindow({name: "code"})
    Assert(vd.windows.Count = moves && vd.at = 1 && WinActive(b), "Pinned window was moved or did not follow")
    TogglePinActiveWindow()
    Assert(!vd.IsPinned(b), "Pin shortcut did not unpin")

    ; A removed desktop is recreated and named on demand.
    vd.names.Delete(1)
    count := vd.desktops
    GoToDesktop({name: "code"})
    Assert(vd.desktops = count + 1 && vd.at = count && vd.Name(count) = "code", "Removed desktop was not recreated")

    ; Sections keep config order, which sets each desktop's initial position.
    FileOpen(config_file, "w", "UTF-8-RAW").Write("[settings]`nsuper_key=F24`n[desktop.web]`nhotkey=1`n[desktop.code]`nhotkey=2`n"
        . "[desktop.chat]`nhotkey=3`n[desktop.nokey]`n[desktop. web ]`nhotkey=4`n")
    errors := []
    order := []
    config := ReadConfig(config_file, errors, order)
    sections := ParseDesktops(config, order, errors)
    AssertEqual(sections.Length, 3)
    Assert(sections[1].name = "web" && sections[2].name = "code" && sections[3].name = "chat", "Sections lost config order")
    Assert(sections[1].position = 0 && sections[3].position = 2 && sections[3].hotkey = "3", "Wrong section positions")
    AssertEqual(errors.Length, 2)

    ; Fresh setup names existing desktops in order and creates the rest.
    vd := FakeDesktops(1)
    errors := []
    PrepareDesktops(sections, errors)
    Assert(!errors.Length && vd.desktops = 3, "Missing desktops were not created")
    Assert(vd.Name(0) = "web" && vd.Name(1) = "code" && vd.Name(2) = "chat", "Desktop names were not applied in order")
    ; Reordered desktops keep their places; a desktop named outside the config is taken over.
    vd := FakeDesktops(3)
    vd.names := Map(0, "chat", 1, "Personal", 2, "web")
    PrepareDesktops(sections, errors)
    Assert(vd.desktops = 3 && vd.Name(0) = "chat" && vd.Name(1) = "code" && vd.Name(2) = "web", "Reordered desktops were renamed")
    ; A position holding another section's desktop is left alone; the section gets a new desktop.
    vd := FakeDesktops(2)
    vd.names := Map(0, "code", 1, "chat")
    PrepareDesktops(sections, errors)
    Assert(vd.desktops = 3 && vd.Name(0) = "code" && vd.Name(2) = "web", "Claimed desktop was renamed")

    FileAppend("Desktop tests passed.`n", "*")
} catch as err {
    exit_code := 1
    ReportError(err, "desktops")
} finally {
    StopCycleSession()
    ToolTip()
    try FileDelete(config_file)
    for _, window in windows
        try window.Destroy()
    if (original && WinExist(original))
        try WinActivate(original)
}
ExitApp(exit_code)

; Load production functions without startup or hotkey registration.
#Include ..\skok.ahk
