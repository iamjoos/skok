#Requires AutoHotkey v2.0
#Include lib.ahk
#Include outline.ahk

original := WinExist("A")
windows := []
cycle_session := false
cycle_selected := 0
unconfigured_cycle := []
configured_apps := []
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
        {hwnd: picked, app: "Picked", exe: "test", title: "Picked", current: false},
        {hwnd: origin, app: "Origin", exe: "test", title: "Origin", current: true}
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
        {hwnd: origin, app: "Origin", exe: "test", title: "Origin", current: false},
        {hwnd: picked, app: "Picked", exe: "test", title: "Picked", current: false}
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
    FocusOrRun("ahk_id " origin, "unused", "")
    Assert(!WindowSearch.active && !cycle_session && WinActive(origin), "Single-window app shortcut did not cancel search to origin")
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    FocusOrRun("ahk_id " picked, "unused", "")
    SyncActiveWindow()
    Assert(!WindowSearch.active && WinActive(picked), "App shortcut did not cancel search and focus target")
    Assert(current_window = picked && previous_window = origin, "App shortcut from search recorded the previewed window")

    WinActivate(origin), SyncActiveWindow()
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    CycleCurrentApp(1)
    SetTimer(EndCycleSession, 0)
    Critical "Off"
    Assert(!WindowSearch.active && !DllCall("IsWindowVisible", "Ptr", WindowSearch.window.Hwnd), "App cycling did not cancel search")
    Assert(cycle_session && WinActive(origin) && cycle_selected != origin, "App cycling from search did not start from origin")
    AssertPeekShown(cycle_selected, CycleStrip.window.Hwnd)
    StopCycleSession()

    WinActivate(origin), SyncActiveWindow()
    WindowSearch.Show(entries, ActivateWindow)
    WindowSearch.Move(1)
    CycleUnconfigured(1)
    SetTimer(EndCycleSession, 0)
    Critical "Off"
    Assert(!WindowSearch.active && !DllCall("IsWindowVisible", "Ptr", WindowSearch.window.Hwnd), "Unconfigured cycling did not cancel search")
    Assert(cycle_session && WinActive(origin) && cycle_selected != origin, "Unconfigured cycling from search did not start from origin")
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