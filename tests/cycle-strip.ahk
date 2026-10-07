#Requires AutoHotkey v2.0
#Include lib.ahk
#Include outline.ahk

AssertHidden() {
    Assert(!CycleStrip.work_area, "Cycle placement survived session end")
    if CycleStrip.window
        Assert(!DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd), "Strip survived session end")
    AssertNoOutline("Outline survived session end")
}

AssertCycleOutline(hwnd) {
    Assert(WinActive(hwnd), "Cycle overlays stole focus")
    strip := CycleStrip.window && DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd) ? CycleStrip.window.Hwnd : 0
    AssertOutline(hwnd, strip)
    for _, bar in WindowOutline.bars
        Assert(!IsCycleableWindow(bar.Hwnd), "Outline entered cycle candidates")
}

original := WinExist("A")
CoordMode("Mouse", "Screen")
MouseGetPos(&mouse_x, &mouse_y)
windows := []
cycle_session := false
cycle_origin := 0
cycle_origin_previous := 0
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
            BeginCycleSession(origin)
            SetTimer(EndCycleSession, 0)
            ActivateNextWindow(hwnds, origin, 1)
            Critical "Off"
            AssertCycleOutline(target)
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
            ActivateNextWindow(hwnds, target, -1)
            Critical "Off"
            AssertCycleOutline(origin)
            WinGetPos(&next_x, &next_y, , , CycleStrip.window)
            Assert(strip_x = next_x && strip_y = next_y, "Strip moved during cycling")
            EndCycleSession()  ; F24 is not held: simulate releasing the modifier.
            AssertHidden()
        }
    }

    ; Timer refresh follows a resized or maximized window, never changing its geometry.
    WinActivate(target)
    WindowOutline.Show(target)
    WinMove(primary_left + 90, primary_top + 90, 360, 200, target)
    WindowOutline.Refresh()
    AssertCycleOutline(target)
    WinMaximize(target)
    WindowOutline.Refresh()
    AssertCycleOutline(target)
    WinRestore(target)
    WindowOutline.Refresh()
    AssertCycleOutline(target)
    WinActivate(origin)
    WindowOutline.Refresh()
    AssertNoOutline("External focus left a stale outline")

    ; Per-monitor-aware apps (Edge, Teams) have unscaled bounds on displays whose DPI differs from the system's.
    context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try per_monitor := Gui(, "Cycle outline per-monitor fixture")
    finally DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
    windows.Push(per_monitor)
    per_monitor.Show("w240 h100")
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &left, &top)
        WinMove(left + 40, top + 40, , , per_monitor)
        WinActivate(per_monitor)
        WindowOutline.Show(per_monitor.Hwnd)
        AssertCycleOutline(per_monitor.Hwnd)
    }
    WindowOutline.Hide()
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
    AssertCycleOutline(click_window.Hwnd)
    WinGetPos(&bar_x, &bar_y, , &bar_height, WindowOutline.bars[3])
    Click(bar_x + 1, bar_y + Floor(bar_height / 2))
    Sleep(50)  ; Let the GUI dispatch the fixture's click event.
    Assert(clicks.Length = 1, "Outline intercepted a click instead of passing it through")
    Assert(WinActive(click_window), "Click-through outline changed focus")
    WindowOutline.Hide()
    click_window.Hide()

    ; The highlight is independent of strip visibility, and disabling it hides all bars.
    show_cycle_titles := false
    WinActivate(origin)
    BeginCycleSession(origin)
    SetTimer(EndCycleSession, 0)
    ActivateNextWindow(hwnds, origin, 1)
    Critical "Off"
    AssertCycleOutline(target)
    Assert(!DllCall("IsWindowVisible", "Ptr", CycleStrip.window.Hwnd), "Disabled strip was shown")
    WindowOutline.enabled := false
    WindowOutline.Show(target)
    AssertNoOutline("Disabled highlight was shown")
    StopCycleSession()
    AssertHidden()
    WindowOutline.enabled := true
    show_cycle_titles := true

    ; Closing the origin cannot move the strip; closing the target clears tracking.
    WindowTheme.SetDisplay("active")
    WinActivate(origin)
    BeginCycleSession(origin)
    SetTimer(EndCycleSession, 0)
    ActivateNextWindow(hwnds, origin, 1)
    Critical "Off"
    windows[1].Destroy()
    CycleStrip.Show(hwnds, 2)
    Assert(WindowTheme.WorkArea(CycleStrip.window.Hwnd, &strip_left, &strip_top, &strip_right, &strip_bottom)
        && strip_left = primary_left && strip_top = primary_top
        && strip_right = primary_right && strip_bottom = primary_bottom, "Closed origin moved the strip")
    CloseActiveWindow()
    AssertNoOutline("Close left the outline")
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