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
