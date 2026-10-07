#Requires AutoHotkey v2.0
#Include ..\window-search.ahk
#Include lib.ahk
#Include outline.ahk

Focus(hwnd) {
    global visits, cancel_during_preview, change_during_finish, move_during_preview
    if cancel_during_preview {
        cancel_during_preview := false
        ; The preview still activates its target after the cancellation request.
        WindowSearch.Cancel(WindowSearch.window)
    }
    if move_during_preview {
        move_during_preview := false
        WindowSearch.Move(1)
    }
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
    Assert(WindowSearch.active, "Preview dismissed search")
    Assert(WinActive(WindowSearch.window), "Search did not regain keyboard focus")
    Assert(ControlGetFocus(WindowSearch.window) = WindowSearch.edit.Hwnd, "Search edit lost focus")
}

origin := WinExist("A")
windows := []
visits := []
cancel_during_preview := false
change_during_finish := false
move_during_preview := false
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
            AssertPicker()
            AssertOutline(second, WindowSearch.window.Hwnd)
            WinGetPos(&preview_x, &preview_y, , , WindowSearch.window)
            Assert(picker_x = preview_x && picker_y = preview_y, "Preview moved search to another display")
            PressEsc(WindowSearch.window)
            Assert(!WindowSearch.active && WinActive(start), "Display policy changed cancellation focus")
            AssertNoOutline("Cancel left the outline")
        }
    }
    WindowTheme.SetDisplay("primary")
    visits := []
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    Assert(!visits.Length, "Opening search re-activated the current window")
    AssertPicker()
    AssertOutline(start, WindowSearch.window.Hwnd)

    ; Navigation previews, wraps, and does not replace the saved origin on reopening.
    WindowSearch.OnKeyDown(0x28, 0, 0, WindowSearch.edit.Hwnd)
    Assert(visits[-1] = second, "Down did not preview the next window")
    AssertPicker()
    AssertOutline(second, WindowSearch.window.Hwnd)
    WindowSearch.Show(entries, Focus)
    Assert(WindowSearch.origin = start, "Reopening replaced the origin")
    WindowSearch.Move(-1)
    WindowSearch.Move(-1)
    Assert(visits[-1] = third, "Up did not wrap to the last window")
    AssertPicker()

    ; Regaining focus after a preview must not select the query for the next key to replace.
    SendEvent("sec")
    Assert(WindowSearch.edit.Value = "sec", "Typing across previews replaced the query: " WindowSearch.edit.Value)
    Assert(visits[-1] = second, "Typing did not preview its first match")
    Assert(SendMessage(0xB0, 0, 0, WindowSearch.edit) = (3 | 3 << 16), "Preview left the query selected")  ; EM_GETSEL
    AssertPicker()

    ; Query changes preview the new first match; no matches keep the picker usable.
    WindowSearch.edit.Value := "second"
    WindowSearch.Update()
    Assert(visits[-1] = second, "Filtering did not preview its first match")
    AssertPicker()
    count := visits.Length
    WindowSearch.Update()
    Assert(visits.Length = count, "Unchanged selection was activated again")
    WindowSearch.edit.Value := "no-such-window"
    WindowSearch.Update()
    WindowSearch.Move(1)
    WindowSearch.Pick(0)
    Assert(visits.Length = count, "Empty results activated a window")
    AssertPicker()
    AssertNoOutline("Empty results kept an outline")
    PressEsc(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(start), "Esc did not restore the origin")

    ; Accept keeps the preview, including restored minimized windows.
    WinMinimize(second)
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    Assert(WinGetMinMax(second) != -1, "Preview did not restore a minimized window")
    AssertPicker()
    WindowSearch.OnKeyDown(0x0D, 0, 0, WindowSearch.edit.Hwnd)
    Assert(!WindowSearch.active && WinActive(second), "Enter did not accept the selection")

    ; A selection change during a preview runs afterwards instead of overlapping it.
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    move_during_preview := true
    WindowSearch.Move(1)
    Assert(visits[-2] = second && visits[-1] = third, "Selection change during a preview was not previewed last")
    AssertPicker()
    PressEsc(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(start), "Esc after overlapping previews did not restore the origin")

    ; Held keys move at once but preview only after the repeat stops; Esc drops a pending preview.
    WindowSearch.Show(entries, Focus)
    count := visits.Length
    Loop 2
        WindowSearch.OnKeyDown(0x28, 0x40000000, 0, WindowSearch.edit.Hwnd)  ; repeated Down
    Assert(WindowSearch.selected = 3 && visits.Length = count, "Held key previewed every repeat")
    Sleep(300)
    Assert(visits.Length = count + 1 && visits[-1] = third, "Held key did not preview after the repeat")
    AssertPicker()
    AssertOutline(third, WindowSearch.window.Hwnd)
    WindowSearch.OnKeyDown(0x26, 0x40000000, 0, WindowSearch.edit.Hwnd)  ; repeated Up
    AssertNoOutline("Held key left the outline on the previous preview")
    PressEsc(WindowSearch.window)
    Sleep(300)
    Assert(!WindowSearch.active && WinActive(start) && visits[-1] = start, "Pending preview ran after cancel")

    ; Cross-process previews must also cancel through actual keyboard input.
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
    AssertPicker()
    PressEsc(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(external_origin), "Cross-process Esc did not restore the origin")

    ; A cancellation requested inside activation must win over its continuation.
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    cancel_during_preview := true
    WindowSearch.Move(1)
    Assert(!WindowSearch.active && WinActive(start), "In-flight preview overrode cancellation")

    ; Queued query updates must not start another preview while restoring the origin.
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    change_during_finish := true
    WindowSearch.Cancel(WindowSearch.window)
    Assert(!WindowSearch.active && WinActive(start), "Query update overrode cancellation")

    ; Native GUI close also uses the cancellation path rather than merely hiding.
    WindowSearch.Show(entries, Focus)
    WindowSearch.Move(1)
    PostMessage(0x0010, 0, 0, , WindowSearch.window)  ; WM_CLOSE
    WinWaitNotActive(WindowSearch.window, , 2)
    Assert(!WindowSearch.active && WinActive(start), "Native close did not restore the origin")

    ; Disabled previews keep the picker in front until a window is accepted.
    WindowSearch.previews := false
    WinActivate(start)
    WindowSearch.Show(entries, Focus)
    count := visits.Length
    WindowSearch.Move(1)
    SendEvent("th")
    Assert(visits.Length = count, "Disabled previews activated a window")
    AssertPicker()
    AssertNoOutline("Disabled previews outlined a background window")
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