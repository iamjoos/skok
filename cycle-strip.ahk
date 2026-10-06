#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\window-theme.ahk

; A click-through, non-activating list of window titles; real windows keep their geometry.
class CycleStrip {
    static window := 0
    static numbers := []
    static titles := []
    static selected_row := 0
    static row_count := 0
    static size := ""

    static Show(hwnds, selected) {
        ; Do not claim that a window was selected if activation failed or a dialog intervened.
        if (hwnds.Length < 2 || !selected || !WindowTheme.WorkArea(hwnds[selected], &left, &top, &right, &bottom)) {
            this.Hide()
            return
        }
        theme := WindowTheme.Refresh()
        width := Min(WindowTheme.Scale(640), right - left - WindowTheme.Scale(32))
        pitch := WindowTheme.Scale(32)
        capacity := Max(1, Floor((bottom - top - WindowTheme.Scale(44)) / pitch))
        ; The window background is only set at build time.
        if (this.size != width ":" capacity ":" theme)
            this.Build(width, capacity, theme)
        this.row_count := Min(hwnds.Length, capacity)

        ; If there are too many windows, keep the selected title in a sliding visible range.
        first := Max(1, Min(selected - Floor(this.row_count / 2), hwnds.Length - this.row_count + 1))
        if (this.selected_row != selected - first + 1) {
            this.Highlight(this.selected_row, false)
            this.selected_row := selected - first + 1
            this.Highlight(this.selected_row, true)
        }
        Loop this.row_count {
            index := first + A_Index - 1
            title := "(window closed)"
            try title := WinGetTitle(hwnds[index])
            this.numbers[A_Index].Text := index
            this.titles[A_Index].Text := title
        }
        ; Rows past row_count are clipped by the window height.
        height := WindowTheme.Scale(12) + this.row_count * pitch
        this.window.Show("NA " WindowTheme.Placement(left, top, right, width) " h" height)
    }

    static Hide() {
        if this.window
            this.window.Hide()
    }

    static Highlight(row, on) {
        if !row
            return
        WindowTheme.StyleCell(this.numbers[row], on)
        WindowTheme.StyleCell(this.titles[row], on)
    }

    ; Rows fill the monitor so lists of any length reuse the window without flicker.
    static Build(width, row_count, theme) {
        if this.window
            this.window.Destroy()
        ; WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT: never focused; clicks pass through.
        this.window := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale", "skok window titles")
        ; A layered window stays invisible until its opacity is set.
        DllCall("SetLayeredWindowAttributes", "Ptr", this.window.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2)
        WindowTheme.Frame(this.window.Hwnd)
        this.window.BackColor := WindowTheme.background
        this.window.SetFont("s" WindowTheme.row_font_size " c" WindowTheme.text, WindowTheme.font_face)
        s := ObjBindMethod(WindowTheme, "Scale")
        this.numbers := []
        this.titles := []
        this.selected_row := 0
        ; A fixed number column keeps the bold index from shifting the title.
        Loop row_count {
            y := s(8) + (A_Index - 1) * s(32)
            this.numbers.Push(WindowTheme.AddNumberCell(this.window, y))
            this.titles.Push(WindowTheme.AddTextCell(this.window, s(48), y, width - s(56)))
        }
        this.size := width ":" row_count ":" theme
    }
}
