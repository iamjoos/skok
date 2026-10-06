#Requires AutoHotkey v2.0

Assert(condition, message) {
    if !condition
        throw Error(message)
}

original := WinExist("A")
windows := []
cycle_session := false
current_window := 0
previous_window := 0
search_origin := 0
search_origin_previous := 0
search_current := 0
exit_code := 0
try {
    Loop 3 {
        window := Gui(, "Search history test " A_Index)
        window.Show("w240 h100")
        windows.Push(window)
    }
    origin := windows[1].Hwnd
    prior := windows[2].Hwnd
    preview := windows[3].Hwnd
    entries := [
        {hwnd: preview, app: "Preview", exe: "test", title: "Preview", current: false},
        {hwnd: origin, app: "Origin", exe: "test", title: "Origin", current: true}
    ]
    WinActivate(origin)
    current_window := origin
    previous_window := prior
    search_origin := origin
    search_origin_previous := prior
    search_current := origin
    WindowSearch.Show(entries, ActivateSearchWindow, EndSearchSession)
    WindowSearch.Move(1)
    Assert(current_window = preview && previous_window = origin, "Preview history lost the origin")
    SendEvent("{Esc}")
    WinWaitNotActive(WindowSearch.window, , 2)
    Assert(current_window = origin && previous_window = prior, "Cancel did not restore history")
    ; A queued preview event must not resurrect a cancelled visit.
    OnShellMessage(4, preview)
    OnShellMessage(0x8004, origin)
    Assert(current_window = origin && previous_window = prior, "Delayed preview corrupted cancel history")

    WindowSearch.Show(entries, ActivateSearchWindow, EndSearchSession)
    WindowSearch.Move(1)
    WindowSearch.Pick(WindowSearch.selected)
    OnShellMessage(4, origin)
    OnShellMessage(0x8004, preview)
    Assert(current_window = preview && previous_window = origin, "Accept did not retain origin history")

    ; Clicking away commits the external focus, not the last preview, as one visit.
    WinActivate(origin)
    current_window := origin
    previous_window := prior
    WindowSearch.Show(entries, ActivateSearchWindow, EndSearchSession)
    WindowSearch.Move(1)
    WinActivate(prior)
    Assert(!WindowSearch.active, "External focus did not dismiss search")
    Assert(current_window = prior && previous_window = origin, "External dismissal retained a preview in history")

    ; Cancelling from a non-cycleable window (like the taskbar) returns to the last focused window without previews in history.
    tool := Gui("+ToolWindow", "Search history tool window")
    windows.Push(tool)
    tool.Show("w240 h100")
    WinActivate(tool)
    current_window := origin
    previous_window := prior
    search_origin := 0
    search_origin_previous := prior
    search_current := origin
    tool_entries := [
        {hwnd: origin, app: "Origin", exe: "test", title: "Origin", current: false},
        {hwnd: preview, app: "Preview", exe: "test", title: "Preview", current: false}
    ]
    WindowSearch.Show(tool_entries, ActivateSearchWindow, EndSearchSession, search_current)
    WindowSearch.Move(1)
    Assert(current_window = preview, "Preview from a non-cycleable origin was not tracked")
    SendEvent("{Esc}")
    WinWaitNotActive(WindowSearch.window, , 2)
    Assert(WinActive(origin), "Cancel did not return to the last focused window")
    Assert(current_window = origin && previous_window = prior, "Cancel from a non-cycleable origin changed history")
    FileAppend("Window search history tests passed.`n", "*")
} catch as err {
    exit_code := 1
    report := err.Message "`n" err.Stack "`n"
    try FileAppend(report, "**")
    catch
        FileAppend(report, A_Temp "\skok-window-search-history-error.log")
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