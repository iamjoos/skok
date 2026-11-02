#Requires AutoHotkey v2.0
; Shared helpers for the test scripts; defines functions only, so it is safe to include anywhere.

Assert(condition, message) {
    if !condition
        throw Error(message)
}

AssertEqual(actual, expected) {
    if (actual != expected)
        throw Error("Expected '" expected "', got '" actual "'.")
}

; stderr can be invalid when the GUI-subsystem runtime has no console; fall back to a temp log.
ReportError(err, name) {
    report := err.Message "`n" err.Stack "`n"
    try FileAppend(report, "**")
    catch
        FileAppend(report, A_Temp "\skok-" name "-error.log")
}

; Pushes as it goes so the caller's cleanup still destroys windows if one fails to open.
AddTestWindows(windows, title, count) {
    Loop count {
        window := Gui(, title " " A_Index)
        window.AddText(, "Window " A_Index)
        window.Show("w240 h100")
        windows.Push(window)
    }
}

; Use a real key: the GUI dialog manager can consume Esc before WM_KEYDOWN.
PressEsc(picker) {
    SendEvent("{Esc}")
    WinWaitNotActive(picker, , 2)
}

; Stands in for VirtualDesktopAccessor so tests never switch the real desktops; windows default to desktop 0.
; Fields can't share a name with a method (Count, Current): AHK keeps both in one namespace.
class FakeDesktops {
    __New(count := 1) {
        this.desktops := count
        this.at := 0
        this.windows := Map()
        this.pinned := Map()
        this.names := Map()
        this.switches := []
    }

    Count() => this.desktops
    Current() => this.at
    Create() => this.desktops++
    WindowDesktop(hwnd) => this.windows.Get(hwnd, 0)
    IsPinned(hwnd) => this.pinned.Has(hwnd)
    Name(number) => this.names.Get(number, "")
    Listen(hwnd, message) => 0
    Restart() => 0

    TogglePin(hwnd) {
        if this.pinned.Has(hwnd)
            this.pinned.Delete(hwnd)
        else
            this.pinned[hwnd] := true
        return this.pinned.Has(hwnd)
    }

    GoTo(number) {
        this.switches.Push(number)
        this.at := number
        return 1
    }

    MoveWindow(hwnd, number) {
        this.windows[hwnd] := number
        return 1
    }

    SetName(number, name) {
        this.names[number] := name
        return 1
    }
}
