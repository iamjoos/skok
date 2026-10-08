#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\window-outline.ahk

; A click-through live thumbnail over a window's visible frame: shows it in place without activating
; it, so focus, z-order and the Alt+Tab order stay untouched.
class WindowPeek {
    static window := 0
    static thumbnail := 0
    static target := 0

    ; overlay: the strip or picker, kept above the peek.
    static Show(hwnd, overlay := 0) {
        if (hwnd = this.target)
            return true
        ; DWM bounds are physical pixels; system-DPI coordinates would misplace the peek on other-DPI monitors.
        context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")  ; PER_MONITOR_AWARE_V2
        try {
            if !this.window {
                ; WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT; the color key leaves only the thumbnail visible.
                this.window := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080020", "skok window peek")
                this.window.BackColor := "010203"
                DllCall("SetLayeredWindowAttributes", "Ptr", this.window.Hwnd, "UInt", 0x030201, "UChar", 0, "UInt", 1)  ; LWA_COLORKEY
            }
            ; Swap the thumbnail without hiding the window so moving between results doesn't flicker.
            this.Unregister()
            thumbnail := 0
            if (DllCall("dwmapi\DwmRegisterThumbnail", "Ptr", this.window.Hwnd, "Ptr", hwnd, "Ptr*", &thumbnail, "Int") != 0)
                throw Error("Could not register thumbnail.")
            this.thumbnail := thumbnail
            if !this.Bounds(hwnd, &left, &top, &width, &height)
                throw Error("Could not place thumbnail.")
            props := Buffer(48, 0)
            NumPut("UInt", 0x9, props, 0)  ; DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE
            NumPut("Int", 0, "Int", 0, "Int", width, "Int", height, props, 4)
            NumPut("Int", true, props, 40)
            if (DllCall("dwmapi\DwmUpdateThumbnailProperties", "Ptr", thumbnail, "Ptr", props, "Int") != 0)
                throw Error("Could not show thumbnail.")
            ; Only slot in under the overlay when appearing: the outline then raises itself and the overlay above.
            visible := DllCall("IsWindowVisible", "Ptr", this.window.Hwnd)
            flags := visible ? 0x54 : 0x50  ; SWP_NOACTIVATE | SWP_SHOWWINDOW (| SWP_NOZORDER)
            DllCall("SetWindowPos", "Ptr", this.window.Hwnd, "Ptr", overlay, "Int", left, "Int", top, "Int", width, "Int", height, "UInt", flags)
            this.target := hwnd
            return true
        } catch {
            this.Hide()
            return false
        } finally {
            DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
        }
    }

    ; The thumbnail source is the visible frame; a minimized window is centered on the display it restores to.
    static Bounds(hwnd, &left, &top, &width, &height) {
        if (WinGetMinMax(hwnd) != -1)
            return WindowOutline.FrameRect(hwnd, &left, &top, &width, &height)
        size := Buffer(8, 0)
        if (DllCall("dwmapi\DwmQueryThumbnailSourceSize", "Ptr", this.thumbnail, "Ptr", size, "Int") != 0)
            return false
        width := NumGet(size, 0, "Int"), height := NumGet(size, 4, "Int")
        if (width < 2 || height < 2)
            return false
        placement := Buffer(44, 0)
        NumPut("UInt", 44, placement)
        if !DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", placement)
            return false
        monitor := DllCall("MonitorFromRect", "Ptr", placement.Ptr + 28, "UInt", 2, "Ptr")  ; rcNormalPosition, MONITOR_DEFAULTTONEAREST
        info := Buffer(40, 0)
        NumPut("UInt", 40, info)
        if !DllCall("GetMonitorInfo", "Ptr", monitor, "Ptr", info)
            return false
        area_left := NumGet(info, 20, "Int"), area_top := NumGet(info, 24, "Int")
        area_width := NumGet(info, 28, "Int") - area_left, area_height := NumGet(info, 32, "Int") - area_top
        scale := Min(1, area_width / width, area_height / height)
        width := Round(width * scale), height := Round(height * scale)
        left := area_left + (area_width - width) // 2, top := area_top + (area_height - height) // 2
        return true
    }

    static Hide() {
        this.target := 0
        this.Unregister()
        if (this.window && DllCall("IsWindowVisible", "Ptr", this.window.Hwnd))
            this.window.Hide()
    }

    static Unregister() {
        if this.thumbnail
            DllCall("dwmapi\DwmUnregisterThumbnail", "Ptr", this.thumbnail)
        this.thumbnail := 0
    }
}
