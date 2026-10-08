#Requires AutoHotkey v2.0
#Include lib.ahk

original := WinExist("A")
windows := []
cycle_session := false
current_window := 0
previous_window := 0
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
    FileAppend("Window search history tests passed.`n", "*")
} catch as err {
    exit_code := 1
    ReportError(err, "window-search-history")
} finally {
    WindowSearch.Hide()
    for _, window in windows
        try window.Destroy()
    if (original && WinExist(original))
        try WinActivate(original)
}
ExitApp(exit_code)

; Load production functions without running startup or registering any hotkeys.
#Include ..\skok.ahk