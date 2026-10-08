#Requires AutoHotkey v2.0
#Include lib.ahk
#Include outline.ahk

AssertHidden() {
    Assert(!CycleStrip.work_area, "Cycle placement survived session end")
    if CycleStrip.window
        Assert(!DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd), "Strip survived session end")
    AssertNoPeek("Peek survived session end")
}

; Cycling peeks the selection without taking focus from the active window.
AssertCyclePeek(hwnd, active, outlined := true) {
    Assert(WinActive(active), "Cycling changed focus")
    strip := CycleStrip.window && DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd) ? CycleStrip.window.Hwnd : 0
    AssertPeekShown(hwnd, strip, outlined)
    Assert(!IsCycleableWindow(WindowPeek.window.Hwnd), "Peek entered cycle candidates")
    for _, bar in WindowOutline.bars
        Assert(!IsCycleableWindow(bar.Hwnd), "Outline entered cycle candidates")
}

original := WinExist("A")
CoordMode("Mouse", "Screen")
MouseGetPos(&mouse_x, &mouse_y)
windows := []
cycle_session := false
cycle_selected := 0
unconfigured_cycle := []
current_window := 0
previous_window := 0
show_cycle_titles := true
super_key := "F24"
super_prefix := ""
exit_code := 0
try {
    AddTestWindows(windows, "Cycle overlay test", 2)
    origin := windows[1].Hwnd
    target := windows[2].Hwnd
    hwnds := [origin, target]
    primary := MonitorGetPrimary()
    MonitorGetWorkArea(primary, &primary_left, &primary_top, &primary_right, &primary_bottom)
    WinMove(primary_left + 60, primary_top + 80, , , target)
    Loop MonitorGetCount() {
        monitor := A_Index
        MonitorGetWorkArea(monitor, &left, &top)
        for display in ["primary", "active"] {
            WindowTheme.SetDisplay(display)
            WinMove(left + 40, top + 40, , , origin)
            WinActivate(origin)
            BeginCycleSession()
            SetTimer(EndCycleSession, 0)
            SelectNextWindow(hwnds, origin, 1)
            Critical "Off"
            AssertCyclePeek(target, origin)
            expected := display = "primary" ? primary : monitor
            MonitorGetWorkArea(expected, &expected_left, &expected_top, &expected_right, &expected_bottom)
            area := CycleStrip.work_area
            Assert(area.left = expected_left && area.top = expected_top
                && area.right = expected_right && area.bottom = expected_bottom, "Cycle captured the wrong display")
            Assert(WindowTheme.WorkArea(CycleStrip.window.Hwnd, &strip_left, &strip_top, &strip_right, &strip_bottom), "Could not read strip monitor")
            Assert(strip_left = expected_left && strip_top = expected_top
                && strip_right = expected_right && strip_bottom = expected_bottom, "Strip opened on the wrong display")
            WinGetPos(&strip_x, &strip_y, , , CycleStrip.window)
            ; The origin can move to a different monitor without moving the anchored strip.
            WinMove(primary_left + 40, primary_top + 40, , , origin)
            SelectNextWindow(hwnds, target, -1)
            Critical "Off"
            AssertCyclePeek(origin, origin)
            WinGetPos(&next_x, &next_y, , , CycleStrip.window)
            Assert(strip_x = next_x && strip_y = next_y, "Strip moved during cycling")
            EndCycleSession()  ; F24 is not held: simulate releasing the modifier.
            AssertHidden()
            Assert(WinActive(origin), "Release left the reselected origin")
        }
    }

    ; Releasing activates only the final selection; windows passed through keep their Alt+Tab order.
    AddTestWindows(windows, "Cycle order test", 3)
    trio := [windows[-3].Hwnd, windows[-2].Hwnd, windows[-1].Hwnd]
    WinActivate(trio[3]), WinActivate(trio[2]), WinActivate(trio[1])
    current_window := trio[1]
    previous_window := trio[2]
    sorted := SortNumeric(trio)
    BeginCycleSession()
    SetTimer(EndCycleSession, 0)
    selection := trio[1]
    Loop 2 {
        SelectNextWindow(sorted, selection, 1)
        Critical "Off"
        selection := cycle_selected
        AssertCyclePeek(selection, trio[1])
    }
    EndCycleSession()
    AssertHidden()
    Assert(WinActive(selection), "Release did not activate the selection")
    order := ZOrder(trio)
    Assert(trio[order[1]] = selection && trio[order[2]] = trio[1], "Cycling reordered the windows passed through")
    SyncActiveWindow()
    Assert(current_window = selection && previous_window = trio[1], "Cycling was not one visit from the origin")

    ; Other hotkeys first activate the selection: super + Space mid-cycle returns to where cycling began.
    BeginCycleSession()
    SetTimer(EndCycleSession, 0)
    SelectNextWindow(sorted, selection, 1)
    Critical "Off"
    Assert(cycle_selected != selection, "Cycling did not move")
    SwitchToPreviousWindow()
    AssertHidden()
    Assert(WinActive(selection), "super + Space during cycling did not return to the origin")

    ; Closing while cycling closes the previewed window, not the focused one.
    BeginCycleSession()
    SetTimer(EndCycleSession, 0)
    SelectNextWindow(sorted, selection, 1)
    Critical "Off"
    closed := cycle_selected
    CloseActiveWindow()
    AssertNoPeek("Close left the peek")
    Assert(WinWaitClose(closed, , 2), "Close did not close the previewed window")
    Assert(WinActive(selection), "Close affected the focused window")
    StopCycleSession()
    Assert(WinActive(selection), "Release after close switched windows")

    ; Refresh follows a resized or maximized window, never changing its geometry.
    WinActivate(target)
    WindowOutline.Show(target)
    WinMove(primary_left + 90, primary_top + 90, 360, 200, target)
    WindowOutline.Refresh()
    AssertOutline(target)
    WinMaximize(target)
    WindowOutline.Refresh()
    AssertOutline(target)
    WinRestore(target)
    WindowOutline.Refresh()
    AssertOutline(target)
    WinMinimize(target)
    WindowOutline.Refresh()
    AssertNoOutline("Minimized target kept the outline")
    WinRestore(target)

    ; Per-monitor-aware apps (Edge, Teams) have unscaled bounds on displays whose DPI differs from the system's.
    context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try per_monitor := Gui(, "Cycle outline per-monitor fixture")
    finally DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
    windows.Push(per_monitor)
    per_monitor.Show("w240 h100")
    pair := SortNumeric([origin, per_monitor.Hwnd])
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &left, &top)
        WinMove(left + 40, top + 40, , , per_monitor)
        WinActivate(origin)
        BeginCycleSession()
        SetTimer(EndCycleSession, 0)
        SelectNextWindow(pair, origin, 1)
        Critical "Off"
        AssertCyclePeek(per_monitor.Hwnd, origin)
        StopCycleSession()
        Assert(WinActive(per_monitor), "Release did not activate the per-monitor window")
    }
    per_monitor.Hide()

    ; A real click on a border bar must reach the underlying application control.
    clicks := []
    click_window := Gui("-Caption", "Cycle outline click fixture")
    windows.Push(click_window)
    click_control := click_window.AddText("x0 y0 w240 h100", "Click-through fixture")
    click_control.OnEvent("Click", (*) => clicks.Push(true))
    click_window.Show("x" (primary_left + 120) " y" (primary_top + 120) " w240 h100")
    WinActivate(click_window)
    WindowOutline.Show(click_window.Hwnd)
    AssertOutline(click_window.Hwnd)
    WinGetPos(&bar_x, &bar_y, , &bar_height, WindowOutline.bars[3])
    Click(bar_x + 1, bar_y + Floor(bar_height / 2))
    Sleep(50)  ; Let the GUI dispatch the fixture's click event.
    Assert(clicks.Length = 1, "Outline intercepted a click instead of passing it through")
    Assert(WinActive(click_window), "Click-through outline changed focus")
    WindowOutline.Hide()
    ; So does a click on the peek.
    WindowPeek.Show(click_window.Hwnd)
    AssertPeekShown(click_window.Hwnd, 0, false)
    WinGetPos(&click_x, &click_y, &click_w, &click_h, click_window)
    Click(click_x + click_w // 2, click_y + click_h // 2)
    Sleep(50)
    Assert(clicks.Length = 2, "Peek intercepted a click instead of passing it through")
    Assert(WinActive(click_window), "Click-through peek changed focus")
    WindowPeek.Hide()
    click_window.Hide()

    ; The highlight is independent of strip visibility, and disabling it leaves the peek alone.
    show_cycle_titles := false
    WinActivate(origin)
    BeginCycleSession()
    SetTimer(EndCycleSession, 0)
    SelectNextWindow(hwnds, origin, 1)
    Critical "Off"
    AssertCyclePeek(target, origin)
    Assert(!DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd), "Disabled strip was shown")
    WindowOutline.enabled := false
    SelectNextWindow(hwnds, target, 1)
    Critical "Off"
    AssertCyclePeek(origin, origin, false)
    StopCycleSession()
    AssertHidden()
    WindowOutline.enabled := true
    show_cycle_titles := true

    ; Closing the origin cannot move the strip; closing the selection clears its views.
    WindowTheme.SetDisplay("active")
    WinActivate(origin)
    BeginCycleSession()
    SetTimer(EndCycleSession, 0)
    SelectNextWindow(hwnds, origin, 1)
    Critical "Off"
    windows[1].Destroy()
    CycleStrip.Show(hwnds, 2)
    Assert(WindowTheme.WorkArea(CycleStrip.window.Hwnd, &strip_left, &strip_top, &strip_right, &strip_bottom)
        && strip_left = primary_left && strip_top = primary_top
        && strip_right = primary_right && strip_bottom = primary_bottom, "Closed origin moved the strip")
    CloseActiveWindow()
    AssertNoPeek("Close left the peek")
    WindowOutline.Refresh()
    AssertNoOutline("Close resurrected the outline")
    StopCycleSession()
    StopCycleSession()
    AssertHidden()
    FileAppend("Cycle overlay tests passed.`n", "*")
} catch as err {
    exit_code := 1
    ReportError(err, "cycle-strip")
} finally {
    StopCycleSession()
    for _, window in windows
        try window.Destroy()
    MouseMove(mouse_x, mouse_y, 0)
    if (original && WinExist(original))
        try WinActivate(original)
}
ExitApp(exit_code)

; Load production functions without startup or hotkey registration.
#Include ..\skok.ahk