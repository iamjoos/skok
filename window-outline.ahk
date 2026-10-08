#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\window-theme.ahk

; Four thin, click-through bars inside the visible frame; never changes the target window.
class WindowOutline {
    static enabled := true
    static bars := []
    static target := 0
    static overlay := 0
    static geometry := ""
    static color := ""

    ; overlay: the strip or picker, kept above the bars.
    ; Callers refresh WindowTheme when their cycle/search session starts.
    static Show(hwnd, overlay := 0) {
        if !this.enabled {
            this.Hide()
            return
        }
        if (this.color != WindowTheme.selected_background) {
            this.color := WindowTheme.selected_background
            for _, bar in this.bars
                bar.BackColor := this.color
            this.geometry := ""
        }
        this.target := hwnd
        this.overlay := overlay
        this.Refresh()
    }

    static Refresh() {
        hwnd := this.target
        if !hwnd
            return
        ; DWM bounds are physical pixels; system-DPI coordinates would misplace bars on other-DPI monitors.
        context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")  ; PER_MONITOR_AWARE_V2
        try {
            if (!DllCall("IsWindowVisible", "Ptr", hwnd) || WinGetMinMax(hwnd) = -1) {
                this.Hide()
                return
            }
            if !this.FrameRect(hwnd, &left, &top, &width, &height) {
                this.Hide()
                return
            }
            geometry := hwnd ":" left ":" top ":" width ":" height
            if (geometry = this.geometry)
                return
            if !this.bars.Length
                this.Build()
            thickness := Min(WindowTheme.Scale(3), Floor(width / 2), Floor(height / 2))
            ; Draw inside the frame so all edges remain visible on maximized windows.
            this.SetBars([[left, top, width, thickness], [left, top + height - thickness, width, thickness]
                , [left, top, thickness, height], [left + width - thickness, top, thickness, height]], 0x50)  ; SWP_NOACTIVATE | SWP_SHOWWINDOW
            if this.overlay
                DllCall("SetWindowPos", "Ptr", this.overlay, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)  ; HWND_TOP, no move/size/activate
            this.geometry := geometry
        } catch {
            this.Hide()
        } finally {
            DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
        }
    }

    ; In physical pixels when called under a per-monitor DPI context.
    static FrameRect(hwnd, &left, &top, &width, &height) {
        rect := Buffer(16, 0)
        ; DWM bounds omit invisible resize margins. Fall back on older/non-DWM windows.
        if (DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16, "Int") != 0)
            if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
                return false
        left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
        width := NumGet(rect, 8, "Int") - left, height := NumGet(rect, 12, "Int") - top
        return width >= 2 && height >= 2
    }

    static Hide() {
        ; Clear the target too: the timer must not resurrect a dismissed/closed outline.
        this.target := 0
        this.overlay := 0
        this.geometry := ""
        ; The bars are always shown and hidden together.
        if (this.bars.Length && DllCall("IsWindowVisible", "Ptr", this.bars[1].Hwnd))
            this.SetBars([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], 0x97)  ; SWP_HIDEWINDOW | NOACTIVATE | NOZORDER | NOMOVE | NOSIZE
    }

    ; One batched update repaints all four bars together instead of one at a time.
    static SetBars(rects, flags) {
        defer := DllCall("BeginDeferWindowPos", "Int", 4, "Ptr")
        for i, r in rects
            if defer
                defer := DllCall("DeferWindowPos", "Ptr", defer, "Ptr", this.bars[i].Hwnd, "Ptr", 0, "Int", r[1], "Int", r[2], "Int", r[3], "Int", r[4], "UInt", flags, "Ptr")
        if !(defer && DllCall("EndDeferWindowPos", "Ptr", defer))
            for i, r in rects
                DllCall("SetWindowPos", "Ptr", this.bars[i].Hwnd, "Ptr", 0, "Int", r[1], "Int", r[2], "Int", r[3], "Int", r[4], "UInt", flags)
    }

    ; Runs inside Refresh's per-monitor DPI context, so the bars are per-monitor aware too.
    static Build() {
        Loop 4 {
            ; WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT.
            bar := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080020", "skok window outline")
            bar.BackColor := this.color
            DllCall("SetLayeredWindowAttributes", "Ptr", bar.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2)
            this.bars.Push(bar)
        }
    }
}