#Requires AutoHotkey v2.0
#Include lib.ahk

original := WinExist("A")
windows := []
cycle_session := false
cycle_selected := 0
show_cycle_titles := true
super_key := "F24"
vd := VirtualDesktopAccessor(A_ScriptDir "\..\VirtualDesktopAccessor.dll")
desktop_focus := Map()
current_window := 0
previous_window := 0
InitializeDesktopHistory()
home := vd.Current()
away := Mod(home + 1, vd.Count())
exit_code := 0
try {
    Assert(vd.Count() >= 2, "Cross-desktop search test requires at least two virtual desktops")
    AddTestWindows(windows, "Cross-desktop search test", 3)
    origin := windows[1].Hwnd
    remote := windows[2].Hwnd
    minimized := windows[3].Hwnd
    hidden := Gui(, "Cross-desktop search hidden")
    windows.Push(hidden)
    hidden.AddText(, "Not a search result")
    hidden.Show("Hide w240 h100")
    tool := Gui("+ToolWindow", "Cross-desktop search tool")
    windows.Push(tool)
    tool.Show("w240 h100")
    WinMinimize(minimized)
    Assert(vd.MoveWindow(remote, away) >= 0, "Could not move the search fixture to another desktop")
    deadline := A_TickCount + 3000
    while (CloakFlags(remote) != 2 && A_TickCount < deadline)
        Sleep(20)
    AssertEqual(CloakFlags(remote), 2)
    WinActivate(origin)
    SyncActiveWindow()

    ; Enumeration must not depend on the caller's hidden-window setting or leak it.
    for _, detect in [false, true] {
        DetectHiddenWindows(detect)
        SearchWindows()
        AssertEqual(A_DetectHiddenWindows, detect)
        for _, hwnd in [origin, remote, minimized]
            Assert(HasEntry(WindowSearch.entries, hwnd), "Search omitted a visible or minimized desktop window")
        Assert(!HasEntry(WindowSearch.entries, hidden.Hwnd), "Search included a hidden window")
        Assert(!HasEntry(WindowSearch.entries, tool.Hwnd), "Search included a tool window")
        for _, entry in WindowSearch.entries {
            if (entry.hwnd = remote) {
                AssertEqual(entry.desktop, DesktopLabel(away))
                AssertEqual(entry.desktop_number, away)
                Assert(!entry.here, "Other-desktop result was marked as local")
            }
        }
        ; An empty query names each desktop once, in a header above its windows.
        headers := 0
        for i, line in WindowSearch.lines {
            if (i > WindowSearch.capacity)
                break
            if !line.HasOwnProp("header")
                continue
            headers++
            Assert(WindowSearch.headers[i].Visible && !WindowSearch.icons[i].Visible, "Desktop header row also showed a window")
            AssertEqual(WindowSearch.headers[i].Text, WindowSearch.matches[WindowSearch.lines[i + 1].index].desktop)
        }
        Assert(headers >= 2, "Empty search did not group windows by desktop")
        WindowSearch.Cancel()
        AssertEqual(vd.Current(), home)
        Assert(WinActive(origin), "Cancelling search did not restore the origin")
    }
    DetectHiddenWindows(false)
    SearchWindows()
    WindowSearch.edit.Value := "Cross-desktop search test 2"
    WindowSearch.Update()
    AssertEqual(WindowSearch.matches.Length, 1)
    AssertEqual(WindowSearch.matches[1].hwnd, remote)
    ; Ranked results tag each window with its desktop instead of grouping.
    AssertEqual(WindowSearch.lines.Length, 1)
    Assert(WindowSearch.badges[1].Visible && !WindowSearch.headers[1].Visible, "Ranked result had no desktop badge")
    AssertEqual(WindowSearch.badges[1].badge.text, DesktopLabel(away))
    WindowSearch.Pick(1)
    AssertEqual(vd.Current(), away)
    Assert(WinWaitActive(remote, , 3), "Picking a remote window did not focus it")
    Assert(!WindowSearch.active, "Picking a remote window left search open")
    AssertEqual(A_DetectHiddenWindows, false)
    FileAppend("Cross-desktop window search tests passed.`n", "*")
} catch as err {
    exit_code := 1
    ReportError(err, "window-search-desktops")
} finally {
    WindowSearch.Hide()
    for _, window in windows
        try window.Destroy()
    if (vd.Current() != home)
        vd.GoTo(home)
    if (original && WinExist(original))
        try WinActivate(original)
}
ExitApp(exit_code)

HasEntry(entries, hwnd) {
    for _, entry in entries {
        if (entry.hwnd = hwnd)
            return true
    }
    return false
}

; Load production functions without startup or hotkey registration.
#Include ..\skok.ahk
