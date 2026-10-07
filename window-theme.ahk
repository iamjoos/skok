#Requires AutoHotkey v2.0

; Shared visual style and layout helpers for the cycle strip and window-search picker.
class WindowTheme {
    static mode := "system"
    static display := "primary"
    ; Colors are set by Refresh().
    static background := ""
    static selected_background := ""
    static panel_background := ""
    static text := ""
    static selected_text := ""
    static configured_text := ""
    static unconfigured_text := ""
    static font_face := "Segoe UI"
    static row_font_size := 10
    static search_font_size := 12

    static SetMode(mode) {
        if !RegExMatch(mode, "i)^(system|light|dark)$")
            throw ValueError("Invalid theme '" mode "': use system, light or dark.")
        this.mode := StrLower(mode)
    }

    static SetDisplay(display) {
        if !RegExMatch(display, "i)^(primary|active)$")
            throw ValueError("Invalid overlay_display '" display "': use primary or active.")
        this.display := StrLower(display)
    }

    ; Resolve the chosen theme and read the DWM accent each time a picker is shown.
    static Refresh() {
        light := this.mode = "system"
            ? RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) != 0
            : this.mode = "light"
        ; AccentColor is 0xAABBGGRR like a COLORREF; DwmGetColorizationColor would be 0xAARRGGBB.
        accent := RegRead("HKCU\Software\Microsoft\Windows\DWM", "AccentColor", "")
        if (accent = "")
            accent := DllCall("GetSysColor", "Int", 13, "UInt")  ; COLOR_HIGHLIGHT
        red := accent & 0xFF, green := (accent >> 8) & 0xFF, blue := (accent >> 16) & 0xFF
        this.selected_background := Format("{:02X}{:02X}{:02X}", red, green, blue)
        brightness := red * 299 + green * 587 + blue * 114
        this.selected_text := brightness >= 128000 ? "000000" : "FFFFFF"

        if light {
            this.background := "F3F3F3"
            this.panel_background := "FFFFFF"
            this.text := "1A1A1A"
            this.configured_text := this.selected_background
            this.unconfigured_text := "6A6A6A"
        } else {
            this.background := "202020"
            this.panel_background := "2D2D30"
            this.text := "F0F0F0"
            this.configured_text := Format("{:02X}{:02X}{:02X}", Min(255, red + 70), Min(255, green + 70), Min(255, blue + 70))
            this.unconfigured_text := "A0A0A0"
        }
        return this.background ":" this.selected_background ":" this.panel_background ":" this.text
            . ":" this.selected_text ":" this.configured_text ":" this.unconfigured_text
    }

    ; Layout is in physical pixels (-DPIScale) to match monitor work areas, but fonts still scale with DPI.
    static Scale(n) => Round(n * A_ScreenDPI / 96)

    static row_pitch => this.Scale(32)

    ; Popup width capped by the work area, leaving a margin on both sides.
    static PopupWidth(max_width, left, right) => Min(this.Scale(max_width), right - left - this.Scale(32))

    ; Tool windows are not cycleable, so showing a popup leaves the window history alone.
    static NewPopup(title, options, font_size) {
        popup := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale " options, title)
        this.Frame(popup.Hwnd)
        popup.BackColor := this.background
        popup.SetFont("s" font_size " c" this.text, this.font_face)
        return popup
    }

    ; Window position options: centered horizontally, just below the top of the work area.
    static Placement(left, top, right, width) => "x" (left + Floor((right - left - width) / 2)) " y" (top + this.Scale(16)) " w" width

    ; Row cells use SS_NOPREFIX | SS_CENTERIMAGE to vertically center the single line in its highlight.
    static AddNumberCell(gui, y) => gui.AddText("x" this.Scale(8) " y" y " w" this.Scale(40) " h" this.Scale(28) " +0x281 +Background" this.background, "")

    static AddTextCell(gui, x, y, w) => gui.AddText("x" x " y" y " w" w " h" this.Scale(28) " +0x4280 +Background" this.background, "")

    ; Static controls repaint on every WM_SETTEXT, even when the text is unchanged.
    static SetText(cell, text) {
        if (cell.Text !== String(text))
            cell.Text := text
    }

    static StyleCell(cell, selected, color := "") {
        cell.Opt("+Background" (selected ? this.selected_background : this.background))
        cell.SetFont("norm c" (selected ? this.selected_text : (color || this.text)))
    }

    ; Rounded corners and an accent border on Windows 11; earlier versions ignore both attributes.
    static Frame(hwnd) {
        corner := 2  ; DWMWCP_ROUND
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Int*", &corner, "UInt", 4)  ; DWMWA_WINDOW_CORNER_PREFERENCE
        rgb := Integer("0x" this.selected_background)
        colorref := (rgb & 0xFF) << 16 | rgb & 0xFF00 | rgb >> 16
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", &colorref, "UInt", 4)  ; DWMWA_BORDER_COLOR
    }

    ; Shared popup policy; callers resolve once when search/cycling begins.
    static OverlayWorkArea(hwnd, &left, &top, &right, &bottom) {
        if (this.display = "active" && this.WorkArea(hwnd, &left, &top, &right, &bottom))
            return
        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
    }

    ; Work area of the monitor nearest the window; false if it can't be read.
    static WorkArea(hwnd, &left, &top, &right, &bottom) {
        monitor := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")  ; MONITOR_DEFAULTTONEAREST
        info := Buffer(40, 0)
        NumPut("UInt", 40, info)
        if !DllCall("GetMonitorInfo", "Ptr", monitor, "Ptr", info)
            return false
        left := NumGet(info, 20, "Int"), top := NumGet(info, 24, "Int")
        right := NumGet(info, 28, "Int"), bottom := NumGet(info, 32, "Int")
        return true
    }
}