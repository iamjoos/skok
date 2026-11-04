#Requires AutoHotkey v2.0
#Include lib.ahk
#Include outline.ahk

original := WinExist("A")
windows := []
cycle_session := false
cycle_selected := 0
vd := FakeDesktops()
desktop_focus := Map()
current_desktop := 0
previous_desktop := -1
current_window := 0
previous_window := 0
show_cycle_titles := true
super_key := "F24"
exit_code := 0
try {
    AddTestWindows(windows, "Search history test", 3)
    origin := windows[1].Hwnd
    prior := windows[2].Hwnd
    picked := windows[3].Hwnd
    entries := [
        {hwnd: picked, desktop: "Picked", here: true, exe: "test", title: "Picked", current: false},
        {hwnd: origin, desktop: "Origin", here: true, exe: "test", title: "Origin", current: true}
    ]
    ; SyncActiveWindow stands in for the shell hook, which the tests don't register.
    WinActivate(origin)
    current_window := origin
    previous_window := prior
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    SyncActiveWindow()
    Assert(current_window = origin && previous_window = prior, "Peek changed history")
    PressEsc(WindowSearch.window)
    SyncActiveWindow()
    Assert(current_window = origin && previous_window = prior, "Cancel changed history")

    ; The shortcut cancels through the same path as Esc, even after filtering to another window.
    SearchWindows()
    Assert(WindowSearch.active && WinActive(WindowSearch.window), "Shortcut did not open search")
    AssertEqual(WindowSearch.origin, origin)
    WindowSearch.edit.Value := "Search history test 3"
    WindowSearch.Update()
    AssertEqual(WindowSearch.matches.Length, 1)
    AssertPeekShown(picked, WindowSearch.window.Hwnd)
    SearchWindows()
    SyncActiveWindow()
    Assert(!WindowSearch.active, "Repeated shortcut did not cancel search")
    Assert(!DllCall("IsWindowVisible", "Ptr", WindowSearch.window.Hwnd), "Cancelled picker is visible")
    Assert(WinActive(origin), "Repeated shortcut did not restore the origin")
    AssertNoPeek("Repeated shortcut left preview or outline visible")
    Assert(current_window = origin && previous_window = prior, "Repeated shortcut changed history")
    SearchWindows()
    Assert(WindowSearch.active && WinActive(WindowSearch.window), "Shortcut did not reopen search")
    AssertEqual(WindowSearch.edit.Value, "")
    WindowSearch.edit.Value := "no matching search history window"
    WindowSearch.Update()
    AssertEqual(WindowSearch.matches.Length, 0)
    SearchWindows()
    Assert(!WindowSearch.active && WinActive(origin), "Repeated shortcut did not cancel an empty search")

    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    WindowSearch.Pick(WindowSearch.selected)
    SyncActiveWindow()
    Assert(current_window = picked && previous_window = origin, "Accept did not record one visit from the origin")

    ; Clicking away commits the external focus, not the peeked window.
    WinActivate(origin)
    SyncActiveWindow()
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    WinActivate(prior)
    SyncActiveWindow()
    Assert(!WindowSearch.active, "External focus did not dismiss search")
    Assert(current_window = prior && previous_window = origin, "External dismissal recorded the peeked window")

    ; Cancelling from a non-cycleable window (like the taskbar) returns to the last focused window.
    tool := Gui("+ToolWindow", "Search history tool window")
    windows.Push(tool)
    tool.Show("w240 h100")
    WinActivate(origin)
    current_window := origin
    previous_window := prior
    WinActivate(tool)
    tool_entries := [
        {hwnd: origin, desktop: "Origin", here: true, exe: "test", title: "Origin", current: false},
        {hwnd: picked, desktop: "Picked", here: true, exe: "test", title: "Picked", current: false}
    ]
    WindowSearch.Show(tool_entries, ActivateWindow, current_window)
    WindowSearch.Move(1)
    PressEsc(WindowSearch.window)
    SyncActiveWindow()
    Assert(WinActive(origin), "Cancel did not return to the last focused window")
    Assert(current_window = origin && previous_window = prior, "Cancel from a non-cycleable origin changed history")
    WinActivate(tool)
    SearchWindows()
    AssertEqual(WindowSearch.origin, origin)
    SearchWindows()
    SyncActiveWindow()
    Assert(!WindowSearch.active && WinActive(origin), "Repeated shortcut did not restore the last focused window")
    Assert(current_window = origin && previous_window = prior, "Repeated shortcut from a non-cycleable origin changed history")

    ; Other skok shortcuts cancel search first, restoring the origin before running.
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    SwitchToPreviousWindow()
    SyncActiveWindow()
    Assert(!WindowSearch.active && WinActive(prior), "Previous-window shortcut did not cancel search and switch")
    Assert(current_window = prior && previous_window = origin, "Previous-window shortcut from search corrupted history")

    WinActivate(origin)
    current_window := origin
    previous_window := prior
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    vd.names[0] := "here"
    AssertEqual(DesktopLabel(0), "1: here")
    AssertEqual(DesktopLabel(1), "Desktop 2")
    GoToDesktop({name: "here"})
    Assert(!WindowSearch.active && !cycle_session && WinActive(origin), "Current-desktop shortcut did not cancel search to origin")
    ; picked lives on desktop 2 of the fake, so switching there focuses it.
    vd.desktops := 2
    vd.names[1] := "there"
    vd.MoveWindow(picked, 1)
    desktop_focus[1] := picked
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    GoToDesktop({name: "there"})
    SyncActiveWindow()
    Assert(!WindowSearch.active && WinActive(picked) && vd.at = 1, "Desktop shortcut did not cancel search and focus the desktop's window")
    Assert(current_window = picked && previous_window = origin, "Desktop shortcut from search recorded the previewed window")
    vd.at := 0
    vd.windows.Clear()

    WinActivate(origin), SyncActiveWindow()
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    CycleWindows(1)
    SetTimer(EndCycleSession, 0)
    Critical "Off"
    Assert(!WindowSearch.active && !DllCall("IsWindowVisible", "Ptr", WindowSearch.window.Hwnd), "Cycling did not cancel search")
    Assert(cycle_session && WinActive(origin) && cycle_selected != origin, "Cycling from search did not start from origin")
    AssertPeekShown(cycle_selected, CycleStrip.window.Hwnd)
    ; Cycling covers every window on the desktop; don't focus one the test didn't create.
    cycle_selected := 0
    StopCycleSession()

    AddTestWindows(windows, "Search history disposable", 1)
    disposable := windows[-1].Hwnd
    WinActivate(disposable), SyncActiveWindow()
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    CloseActiveWindow()
    Assert(!WindowSearch.active, "Close shortcut did not cancel search")
    Assert(WinWaitClose(disposable, , 2), "Close shortcut from search did not close the origin window")
    Assert(WinExist(picked) && WinExist(origin), "Close shortcut from search closed a search entry")

    FileAppend("Window search history tests passed.`n", "*")
} catch as err {
    exit_code := 1
    ReportError(err, "window-search-history")
} finally {
    StopCycleSession()
    WindowSearch.Hide()
    for _, window in windows
        try window.Destroy()
    if (original && WinExist(original))
        try WinActivate(original)
}
ExitApp(exit_code)

; Load production functions without running startup or registering any hotkeys.
#Include ..\skok.ahk