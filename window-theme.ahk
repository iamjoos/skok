#Requires AutoHotkey v2.0

; Shared visual style and layout helpers for the cycle strip and window-search picker.
class WindowTheme {
    static mode := "system"
    static display := "primary"
    ; Colors are set by Refresh().
    static background := ""
    static selected_background := ""
    static row_selected_background := ""
    static panel_background := ""
    static text := ""
    static selected_text := ""
    static row_selected_text := ""
    static accent_text := ""
    static muted_text := ""
    static divider := ""
    static badge_background := ""
    static font_face := "Segoe UI"
    static small_font_size := 9
    static row_font_size := 10
    static search_font_size := 12
    static icons := Map()
    static badges := Map()
    static badge_font := 0

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
            this.accent_text := this.selected_background
            this.muted_text := "6A6A6A"
            this.divider := "D6D6D6"
            this.badge_background := "E5E5E5"
            this.row_selected_background := Format("{:02X}{:02X}{:02X}", Round(243 * 0.72 + red * 0.28), Round(243 * 0.72 + green * 0.28), Round(243 * 0.72 + blue * 0.28))
            this.row_selected_text := "1A1A1A"
        } else {
            this.background := "202020"
            this.panel_background := "2D2D30"
            this.text := "F0F0F0"
            this.accent_text := Format("{:02X}{:02X}{:02X}", Min(255, red + 70), Min(255, green + 70), Min(255, blue + 70))
            this.muted_text := "A0A0A0"
            this.divider := "3C3C3C"
            this.badge_background := "383838"
            this.row_selected_background := Format("{:02X}{:02X}{:02X}", Round(32 * 0.65 + red * 0.35), Round(32 * 0.65 + green * 0.35), Round(32 * 0.65 + blue * 0.35))
            this.row_selected_text := "FFFFFF"
        }
        return this.background ":" this.selected_background ":" this.row_selected_background ":" this.panel_background ":" this.text
            . ":" this.selected_text ":" this.accent_text ":" this.muted_text ":" this.divider ":" this.badge_background
    }

    ; Layout is in physical pixels (-DPIScale) to match monitor work areas, but fonts still scale with DPI.
    static Scale(n) => Round(n * A_ScreenDPI / 96)

    static row_pitch => this.Scale(34)

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
    static AddNumberCell(gui, y) => gui.AddText("x" this.Scale(8) " y" y " w" this.Scale(36) " h" this.Scale(30) " +0x281 +Background" this.background, "")

    ; SS_ICON | SS_CENTERIMAGE centers the icon in the row highlight without stretching it.
    static AddIconCell(gui, y) => gui.AddText("x" this.Scale(44) " y" y " w" this.Scale(32) " h" this.Scale(30) " +0x203 +Background" this.background)

    static AddTextCell(gui, x, y, w, options := "") => gui.AddText("x" x " y" y " w" w " h" this.Scale(30) " +0x4280 +Background" this.background " " options, "")

    ; A fill below all other controls; WS_CLIPSIBLINGS keeps it from painting over cells laid on top of it.
    static AddBackdrop(gui, x, y, w, h) {
        cell := gui.AddText("x" x " y" y " w" w " h" h " +0x4000000 +Background" this.background)  ; WS_CLIPSIBLINGS
        DllCall("SetWindowPos", "Ptr", cell.Hwnd, "Ptr", 1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)  ; HWND_BOTTOM, no move/size/activate
        return cell
    }

    ; SS_BITMAP; SetBadge gives it a pre-drawn badge and sizes it to fit.
    static AddBadge(gui, y, options := "") => gui.AddText("x0 y" y " w0 h" this.Scale(20) " +0xE " options)

    ; Shows text in a rounded badge right-aligned at right, on the row color behind it; returns its left edge.
    static SetBadge(cell, text, color, right, selected := false) {
        badge := this.Badge(text, selected ? this.row_selected_background : this.background, color)
        if (!cell.HasOwnProp("badge") || cell.badge != badge) {
            previous := cell.HasOwnProp("badge") ? cell.badge.bitmap : 0
            cell.badge := badge
            ; The static shows its own copy of a bitmap with alpha and returns the previous copy.
            old := SendMessage(0x172, 0, badge.bitmap, cell)  ; STM_SETIMAGE, IMAGE_BITMAP
            if (old && old != previous)
                DllCall("DeleteObject", "Ptr", old)
        }
        cell.GetPos(&x, , &w, &h)
        if (x != right - badge.w || w != badge.w || h != badge.h)
            cell.Move(right - badge.w, , badge.w, badge.h)
        return right - badge.w
    }

    ; Static controls ignore window regions when they repaint (CS_PARENTDC), so badges are bitmaps
    ; with their corners painted in the color behind them. Bitmaps are cached by text and colors.
    static Badge(text, back, color) {
        h := this.Scale(20)
        key := text "`n" back "`n" color "`n" this.badge_background "`n" h
        if this.badges.Has(key)
            return this.badges[key]
        if !this.badge_font
            this.badge_font := DllCall("CreateFontW", "Int", -Round(this.small_font_size * A_ScreenDPI / 72), "Int", 0, "Int", 0, "Int", 0
                , "Int", 400, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "Str", this.font_face, "Ptr")  ; FW_NORMAL, DEFAULT_CHARSET
        dc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
        old_font := DllCall("SelectObject", "Ptr", dc, "Ptr", this.badge_font, "Ptr")
        size := Buffer(8, 0)
        DllCall("GetTextExtentPoint32W", "Ptr", dc, "Str", text, "Int", StrLen(text), "Ptr", size)
        w := Max(NumGet(size, 0, "Int") + this.Scale(14), h)
        info := Buffer(40, 0)
        NumPut("UInt", 40, "Int", w, "Int", -h, "UShort", 1, "UShort", 32, info)  ; top-down 32bpp BITMAPINFOHEADER
        bits := 0
        bitmap := DllCall("CreateDIBSection", "Ptr", dc, "Ptr", info, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
        old_bitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        rect := Buffer(16, 0)
        NumPut("Int", w, "Int", h, rect, 8)
        brush := DllCall("CreateSolidBrush", "UInt", this.ColorRef(back), "Ptr")
        DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", brush)
        DllCall("DeleteObject", "Ptr", brush)
        brush := DllCall("CreateSolidBrush", "UInt", this.ColorRef(this.badge_background), "Ptr")
        old_brush := DllCall("SelectObject", "Ptr", dc, "Ptr", brush, "Ptr")
        old_pen := DllCall("SelectObject", "Ptr", dc, "Ptr", DllCall("GetStockObject", "Int", 8, "Ptr"), "Ptr")  ; NULL_PEN
        ; Without a pen, RoundRect leaves out the right and bottom edges.
        DllCall("RoundRect", "Ptr", dc, "Int", 0, "Int", 0, "Int", w + 1, "Int", h + 1, "Int", this.Scale(8), "Int", this.Scale(8))
        DllCall("SelectObject", "Ptr", dc, "Ptr", old_pen)
        DllCall("SelectObject", "Ptr", dc, "Ptr", old_brush)
        DllCall("DeleteObject", "Ptr", brush)
        DllCall("SetBkMode", "Ptr", dc, "Int", 1)  ; TRANSPARENT
        DllCall("SetTextColor", "Ptr", dc, "UInt", this.ColorRef(color))
        DllCall("DrawTextW", "Ptr", dc, "Str", text, "Int", -1, "Ptr", rect, "UInt", 0x825)  ; DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX
        DllCall("GdiFlush")
        ; Without alpha the static makes COLOR_3DFACE pixels transparent; opaque alpha makes it blend instead.
        Loop w * h
            NumPut("UChar", 0xFF, bits, A_Index * 4 - 1)
        DllCall("SelectObject", "Ptr", dc, "Ptr", old_font)
        DllCall("SelectObject", "Ptr", dc, "Ptr", old_bitmap)
        DllCall("DeleteDC", "Ptr", dc)
        return this.badges[key] := {bitmap: bitmap, w: w, h: h, text: text}
    }

    ; "RRGGBB" to a 0x00BBGGRR COLORREF.
    static ColorRef(rgb) {
        rgb := Integer("0x" rgb)
        return (rgb & 0xFF) << 16 | rgb & 0xFF00 | rgb >> 16
    }

    ; Rendered width of text in the control's current font.
    static TextWidth(cell, text) {
        hdc := DllCall("GetDC", "Ptr", cell.Hwnd, "Ptr")
        old := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, cell), "Ptr")  ; WM_GETFONT
        size := Buffer(8, 0)
        DllCall("GetTextExtentPoint32W", "Ptr", hdc, "Str", text, "Int", StrLen(text), "Ptr", size)
        DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
        DllCall("ReleaseDC", "Ptr", cell.Hwnd, "Ptr", hdc)
        return NumGet(size, 0, "Int")
    }

    ; Static controls repaint on every WM_SETTEXT, even when the text is unchanged.
    static SetText(cell, text) {
        if (cell.Text !== String(text))
            cell.Text := text
    }

    static SetIcon(cell, hicon) {
        if (SendMessage(0x171, 0, 0, cell) != hicon)  ; STM_GETICON
            SendMessage(0x170, hicon, 0, cell)        ; STM_SETICON
    }

    ; For cells without text, such as icons and row backdrops.
    static StyleFill(cell, selected) {
        cell.Opt("+Background" (selected ? this.row_selected_background : this.background))
        cell.Redraw()
    }

    static StyleCell(cell, selected, color := "") {
        cell.Opt("+Background" (selected ? this.row_selected_background : this.background))
        cell.SetFont("norm c" (selected ? (color || this.row_selected_text) : (color || this.text)))
    }

    ; Scales a window, class or executable icon to fit the icon cell, caching the copy by source.
    static WindowIcon(hwnd) {
        size := this.Scale(16)
        raw := this.MessageIcon(hwnd, 2) || this.MessageIcon(hwnd, 0)              ; ICON_SMALL2, ICON_SMALL
            || DllCall("GetClassLongPtrW", "Ptr", hwnd, "Int", -34, "Ptr")         ; GCLP_HICONSM
            || this.MessageIcon(hwnd, 1)                                           ; ICON_BIG
            || DllCall("GetClassLongPtrW", "Ptr", hwnd, "Int", -14, "Ptr")         ; GCLP_HICON
        if raw {
            key := "h:" raw ":" size
            if this.icons.Has(key)
                return this.icons[key]
            if (icon := DllCall("CopyImage", "Ptr", raw, "UInt", 1, "Int", size, "Int", size, "UInt", 0x4000, "Ptr"))
                return this.icons[key] := icon
            if (icon := DllCall("CopyImage", "Ptr", raw, "UInt", 1, "Int", size, "Int", size, "UInt", 0, "Ptr"))
                return this.icons[key] := icon
        }
        path := ""
        try path := WinGetProcessPath(hwnd)
        if (path != "") {
            key := "p:" StrLower(path) ":" size
            if this.icons.Has(key)
                return this.icons[key]
            try if (icon := LoadPicture(path, "Icon1 w" size " h" size, &img_type))
                return this.icons[key] := icon
        }
        key := "default:" size
        if this.icons.Has(key)
            return this.icons[key]
        app := DllCall("LoadIconW", "Ptr", 0, "Ptr", 32512, "Ptr")  ; IDI_APPLICATION
        return this.icons[key] := DllCall("CopyImage", "Ptr", app, "UInt", 1, "Int", size, "Int", size, "UInt", 0, "Ptr") || app
    }

    static MessageIcon(hwnd, type) {
        icon := 0
        DllCall("SendMessageTimeoutW", "Ptr", hwnd, "UInt", 0x7F, "UPtr", type, "Ptr", 0, "UInt", 2, "UInt", 50, "UPtr*", &icon)  ; WM_GETICON, SMTO_ABORTIFHUNG
        return icon
    }

    ; Rounded corners and an accent border on Windows 11; earlier versions ignore both attributes.
    static Frame(hwnd) {
        corner := 2  ; DWMWCP_ROUND
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Int*", &corner, "UInt", 4)  ; DWMWA_WINDOW_CORNER_PREFERENCE
        colorref := this.ColorRef(this.selected_background)
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