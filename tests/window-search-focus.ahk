#Requires AutoHotkey v2.0
#Include ..\window-search.ahk
#Include lib.ahk
#Include outline.ahk

Focus(hwnd) {
    global visits, change_during_finish
    if change_during_finish {
        change_during_finish := false
        WindowSearch.edit.Value := "third"
        WindowSearch.Update()
    }
    if (WinGetMinMax(hwnd) = -1)
        WinRestore(hwnd)
    WinActivate(hwnd)
    Assert(WinActive(hwnd), "Selected window did not receive focus")
    visits.Push(hwnd)
}

AssertPicker() {
    Assert(WindowSearch.active, "Search was dismissed")
    Assert(WinActive(WindowSearch.window), "Search lost keyboard focus")
    Assert(ControlGetFocus(WindowSearch.window) = WindowSearch.edit.Hwnd, "Search edit lost focus")
}

AssertPeek(hwnd) {
    AssertPicker()
    AssertPeekShown(hwnd, WindowSearch.window.Hwnd)
}

origin := WinExist("A")
windows := []
visits := []
change_during_finish := false
exit_code := 0
fixture_pid := 0
try {
    AddTestWindows(windows, "Search focus test", 3)
    start := windows[1].Hwnd
    second := windows[2].Hwnd
    third := windows[3].Hwnd
    entries := [
        {hwnd: second, app: "Second", exe: "test", title: "Second", current: false},
        {hwnd: third, app: "Third", exe: "test", title: "Third", current: false},
        {hwnd: start, app: "Start", exe: "test", title: "Start", current: true}
    ]
    ; Exercise both policies on every attached monitor (also valid on one monitor).
    primary := MonitorGetPrimary()
    MonitorGetWorkArea(primary, &primary_left, &primary_top)
    WinMove(primary_left + 40, primary_top + 40, , , second)
    Loop MonitorGetCount() {
        monitor := A_Index
        MonitorGetWorkArea(monitor, &left, &top)
        WinMove(left + 40, top + 40, , , start)
        for display in ["primary", "active"] {
            WindowTheme.SetDisplay(display)
            WinActivate(start)
            WindowSearch.Show(entries, Focus)
            AssertPicker()
            expected := display = "primary" ? primary : monitor
            MonitorGetWorkArea(expected, &expected_left, &expected_top, &expected_right, &expected_bottom)
            Assert(WindowTheme.WorkArea(WindowSearch.window.Hwnd, &actual_left, &actual_top, &actual_right, &actual_bottom), "Could not read search monitor")
            Assert(actual_left = expected_left && actual_top = expected_top
                && actual_right = expected_right && actual_bottom = expected_bottom, "Search opened on the wrong display: " display)
            WinGetPos(&picker_x, &picker_y, , , WindowSearch.window)
            WindowSearch.Move(1)
            AssertPeek(second)
            WinGetPos(&peek_x, &peek_y, , , WindowSearch.window)
            Assert(picker_x = peek_x && picker_y = peek_y, "Peek moved search to another display")
            PressEsc(WindowSearch.window)
            Assert(!WindowSearch.active && WinActive(start), "Display policy changed cancellation focus")
            AssertNoPeek("Cancel left the peek")
        }
    }
    WindowTheme.SetDisplay("primary")

    ; Peeks cover the visible frame on every display, also for per-monitor-aware apps on other-DPI displays.
    context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try per_monitor := Gui(, "Search peek per-monitor fixture")
    finally DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
    windows.Push(per_monitor)
    per_monitor.Show("w240 h100")
    mixed := [
        {hwnd: per_monitor.Hwnd, app: "PerMonitor", exe: "test", title: "PerMonitor", current: false},
        {hwnd: second, app: "Second", exe: "test", title: "Second", current: false},
        {hwnd: start, app: "Start", exe: "test", title: "Start", current: true}
    ]
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &left, &top)
        WinMove(left + 60, top + 60, , , per_monitor)
        WinMove(left + 400, top + 60, , , second)
        WinActivate(start)
        WindowSearch.Show(mixed, Focus)
        WindowSearch.Move(1)
        AssertPeek(per_monitor.Hwnd)
        WindowSearch.Move(1)
        AssertPeek(second)
        PressEsc(WindowSearch.window)
    }
    per_monitor.Hide()
    visits := []
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    Assert(!visits.Length, "Opening search re-activated the current window")
    AssertPeek(start)

    ; Navigation peeks without activating, wraps, and does not replace the saved origin on reopening.
    WindowSearch.OnKeyDown(0x28, 0, 0, WindowSearch.edit.Hwnd)
    AssertPeek(second)
    WindowSearch.OnKeyDown(0x28, 0x40000000, 0, WindowSearch.edit.Hwnd)  ; auto-repeated Down
    AssertPeek(third)
    Assert(!visits.Length, "Navigation activated a window")
    WindowSearch.Show(entries, Focus)
    Assert(WindowSearch.origin = start, "Reopening replaced the origin")
    WindowSearch.Move(-1)
    AssertPeek(second)

    SendEvent("thi")
    Assert(WindowSearch.edit.Value = "thi", "Typing did not reach the query: " WindowSearch.edit.Value)
    Assert(SendMessage(0xB0, 0, 0, WindowSearch.edit) = (3 | 3 << 16), "Typing left the query selected")  ; EM_GETSEL
    AssertPeek(third)

    ; Query changes peek the new first match; no matches keep the picker usable.
    WindowSearch.edit.Value := "second"
    WindowSearch.Update()
    AssertPeek(second)
    WindowSearch.edit.Value := "no-such-window"
    WindowSearch.Update()
    WindowSearch.Move(1)
    WindowSearch.Pick(0)
    AssertPicker()
    AssertNoPeek("Empty results kept a peek")
    Assert(!visits.Length, "Searching activated a window")
    PressEsc(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(start), "Esc did not restore the origin")

    ; Passing over windows leaves their Alt+Tab order alone: accepting puts only the pick in front.
    WinActivate(third), WinActivate(second), WinActivate(start)
    hwnds := [start, second, third]
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    WindowSearch.Move(1)
    WindowSearch.Move(-1)
    WindowSearch.Move(1)
    AssertPeek(third)
    WindowSearch.OnKeyDown(0x0D, 0, 0, WindowSearch.edit.Hwnd)
    Assert(!WindowSearch.active && WinActive(third), "Enter did not accept the selection")
    AssertNoPeek("Accept left the peek")
    order := ZOrder(hwnds)
    Assert(order[1] = 3 && order[2] = 1 && order[3] = 2, "Accept reordered skipped windows")
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    PressEsc(WindowSearch.window)
    order := ZOrder(hwnds)
    Assert(order[1] = 1 && order[2] = 3 && order[3] = 2, "Cancel reordered skipped windows")

    ; Minimized windows are peeked without restoring them; accepting restores them.
    WinMinimize(second)
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    AssertPeek(second)
    Assert(WinGetMinMax(second) = -1, "Peek restored a minimized window")
    WindowSearch.OnKeyDown(0x0D, 0, 0, WindowSearch.edit.Hwnd)
    Assert(!WindowSearch.active && WinActive(second) && WinGetMinMax(second) != -1, "Enter did not restore a minimized pick")

    ; Cross-process cancellation must also work through actual keyboard input.
    Run('"' A_AhkPath '" /ErrorStdOut "' A_ScriptDir '\window-search-fixture.ahk"', , , &fixture_pid)
    external_origin := WinWait("Search fixture origin ahk_pid " fixture_pid, , 5)
    external_preview := WinWait("Search fixture preview ahk_pid " fixture_pid, , 5)
    Assert(external_origin && external_preview, "Fixture windows did not open")
    external_entries := [
        {hwnd: external_preview, app: "Preview", exe: "test", title: "Preview", current: false},
        {hwnd: external_origin, app: "Origin", exe: "test", title: "Origin", current: true}
    ]
    WinActivate(external_origin)
    WindowSearch.Show(external_entries, Focus)
    WindowSearch.Move(1)
    AssertPeek(external_preview)
    PressEsc(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(external_origin), "Cross-process Esc did not restore the origin")

    ; Queued query updates must not peek again while restoring the origin.
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    change_during_finish := true
    WindowSearch.Cancel(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(start), "Query update overrode cancellation")
    AssertNoPeek("Query update during cancellation left a peek")

    ; Native GUI close also uses the cancellation path rather than merely hiding.
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    PostMessage(0x0010, 0, 0, , WindowSearch.window)  ; WM_CLOSE
    WinWaitNotActive(WindowSearch.window, , 2)
    Assert(!WindowSearch.active && WinActive(start), "Native close did not restore the origin")

    ; Disabled previews show nothing until a window is accepted.
    WindowSearch.previews := false
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    count := visits.Length
    WindowSearch.Move(1)
    SendEvent("th")
    Assert(visits.Length = count, "Disabled previews activated a window")
    AssertPicker()
    AssertNoPeek("Disabled previews peeked a window")
    WindowSearch.OnKeyDown(0x0D, 0, 0, WindowSearch.edit.Hwnd)
    Assert(!WindowSearch.active && WinActive(third), "Enter without previews did not accept the selection")
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    PressEsc(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(start), "Esc without previews did not restore the origin")
    WindowSearch.previews := true

    ; External focus dismisses without snapping back; closed origins are safe to cancel.
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    WinActivate(third)
    Assert(!WindowSearch.active && WinActive(third), "External focus was not preserved")
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    windows[1].Destroy()
    WindowSearch.Cancel()
    Assert(!WindowSearch.active, "Closed origin prevented cancellation")
    FileAppend("Window search focus tests passed.`n", "*")
} catch as err {
    exit_code := 1
    ReportError(err, "window-search-focus")
} finally {
    WindowSearch.Hide()
    if (fixture_pid && ProcessExist(fixture_pid))
        ProcessClose(fixture_pid)
    for _, window in windows
        try window.Destroy()
    if (origin && WinExist(origin))
        try WinActivate(origin)
}
ExitApp(exit_code)