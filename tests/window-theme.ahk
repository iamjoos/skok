#Requires AutoHotkey v2.0
#Include ..\window-theme.ahk
#Include lib.ahk

try {
    AssertEqual(WindowTheme.display, "primary")
    WindowTheme.SetDisplay("ACTIVE")
    AssertEqual(WindowTheme.display, "active")
    WindowTheme.SetDisplay("Primary")
    AssertEqual(WindowTheme.display, "primary")
    for display in ["", "secondary", "primary; comment"] {
        rejected := false
        try WindowTheme.SetDisplay(display)
        catch ValueError {
            rejected := true
        }
        Assert(rejected, "Invalid overlay display was accepted: '" display "'.")
        AssertEqual(WindowTheme.display, "primary")
    }

    AssertEqual(WindowTheme.mode, "system")
    WindowTheme.SetMode("LIGHT")
    AssertEqual(WindowTheme.mode, "light")
    light_signature := WindowTheme.Refresh()
    AssertEqual(WindowTheme.background, "F3F3F3")
    AssertEqual(WindowTheme.panel_background, "FFFFFF")
    AssertEqual(WindowTheme.text, "1A1A1A")
    AssertEqual(WindowTheme.unconfigured_text, "6A6A6A")
    accent := WindowTheme.selected_background
    selected_text := WindowTheme.selected_text
    AssertEqual(WindowTheme.configured_text, accent)

    WindowTheme.SetMode("Dark")
    AssertEqual(WindowTheme.mode, "dark")
    dark_signature := WindowTheme.Refresh()
    AssertEqual(WindowTheme.background, "202020")
    AssertEqual(WindowTheme.panel_background, "2D2D30")
    AssertEqual(WindowTheme.text, "F0F0F0")
    AssertEqual(WindowTheme.unconfigured_text, "A0A0A0")
    AssertEqual(WindowTheme.selected_background, accent)
    AssertEqual(WindowTheme.selected_text, selected_text)
    if (light_signature = dark_signature)
        throw Error("Theme changes must change the rebuild signature.")

    WindowTheme.SetMode("System")
    AssertEqual(WindowTheme.mode, "system")
    system_light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) != 0
    AssertEqual(WindowTheme.Refresh(), system_light ? light_signature : dark_signature)

    for mode in ["", "auto", "light; comment"] {
        rejected := false
        try WindowTheme.SetMode(mode)
        catch ValueError {
            rejected := true
        }
        if !rejected
            throw Error("Invalid theme was accepted: '" mode "'.")
        AssertEqual(WindowTheme.mode, "system")
    }
    FileAppend("Window theme tests passed.`n", "*")
    ExitApp(0)
} catch as err {
    ReportError(err, "window-theme")
    ExitApp(1)
}