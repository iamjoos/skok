#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\window-theme.ahk

; A focusable picker that fuzzy-filters window entries ({hwnd, app, exe, title, current}) as you type.
class WindowSearch {
    static window := 0
    static edit := 0
    static overflow := 0
    static numbers := []
    static labels := []
    static titles := []
    static styles := []
    static size := ""
    static capacity := 0
    static rows_top := 0
    static height := 0
    static entries := []
    static matches := []
    static selected := 0
    static first := 1
    static origin := 0
    static on_pick := 0
    static on_hide := 0
    static active := false
    static closing := false
    static cancelled := false
    static finish_target := 0
    static previewing := false
    static preview_pending := false
    static preview := 0

    static Show(entries, on_pick, on_hide := 0, origin := 0) {
        ; Repeated search hotkeys must not replace the origin with the picker itself.
        if this.active
            return
        theme := WindowTheme.Refresh()
        active := WinExist("A")
        this.origin := origin || active
        if !WindowTheme.WorkArea(active, &left, &top, &right, &bottom)
            return
        width := Min(WindowTheme.Scale(720), right - left - WindowTheme.Scale(32))
        ; Reserve room for the overflow footer even on short work areas.
        capacity := Max(1, Min(20, Floor((bottom - top - WindowTheme.Scale(120)) / WindowTheme.Scale(32))))
        ; Window, panel and edit colors are only set at build time.
        if (this.size != width ":" capacity ":" theme)
            this.Build(width, capacity, theme)

        for _, entry in entries
            entry.text := (entry.app != "" ? entry.app " " : "") entry.exe " " entry.title
        this.entries := entries
        this.on_pick := on_pick
        this.on_hide := on_hide
        this.closing := false
        this.cancelled := false
        this.preview_pending := false
        this.finish_target := 0
        this.edit.Value := ""
        this.Update()
        ; The current window is already in front; re-activating it would only flicker.
        this.preview := this.selected && this.matches[this.selected].current ? this.matches[this.selected].hwnd : 0
        this.active := true
        this.window.Show(WindowTheme.Placement(left, top, right, width) " h" this.height)
        WinActivate(this.window)
        this.edit.Focus()
    }

    static Hide(activated := 0) {
        this.closing := true
        if (this.active && this.on_hide)
            this.on_hide.Call(activated, this.cancelled)
        this.active := false
        if this.window
            this.window.Hide()
    }

    static Cancel(*) {
        this.Finish(this.origin, true)
    }

    ; Latch the outcome before activation can yield to a queued edit/key event.
    static Finish(hwnd, cancelled := false) {
        if (!this.active || this.closing)
            return
        this.closing := true
        this.cancelled := cancelled
        this.finish_target := hwnd
        ; Let an outstanding preview finish before restoring/accepting the target.
        if !this.previewing
            this.Complete()
    }

    static Complete() {
        if (this.finish_target && WinExist(this.finish_target))
            this.FocusWindow(this.finish_target)
        this.Hide()
    }

    ; Activating the pick before hiding keeps this process allowed to set the foreground window.
    static Pick(index) {
        if (!this.active || this.closing || index < 1 || index > this.matches.Length)
            return
        this.Finish(this.matches[index].hwnd)
    }

    ; Bring the selection forward underneath the picker, then keep typing in the edit.
    static PreviewSelection() {
        if (!this.active || this.closing)
            return
        ; Key/edit events can interrupt activation; defer them so previews never overlap.
        if this.previewing {
            this.preview_pending := true
            return
        }
        this.previewing := true
        try {
            Loop {
                this.preview_pending := false
                if (this.closing || !this.selected)
                    break
                hwnd := this.matches[this.selected].hwnd
                if (hwnd = this.preview || !WinExist(hwnd))
                    break
                this.on_pick.Call(hwnd)
                if this.closing
                    break
                this.preview := hwnd
                WinActivate(this.window)
                if this.closing
                    break
                this.edit.Focus()
                if !this.preview_pending
                    break
            }
        } finally {
            this.previewing := false
            if (this.active && this.closing)
                this.Complete()
        }
    }

    ; Internal activations must not be mistaken for clicking away from the picker.
    static FocusWindow(hwnd) {
        this.previewing := true
        try this.on_pick.Call(hwnd)
        finally this.previewing := false
    }

    static Move(direction) {
        if (!this.active || this.closing)
            return
        if !(count := this.matches.Length)
            return
        this.selected := Mod(this.selected - 1 + direction + count, count) + 1
        this.Render()
        this.PreviewSelection()
    }

    static Update(*) {
        if this.closing
            return
        this.matches := this.Filter(this.entries, this.edit.Value)
        this.selected := this.matches.Length ? 1 : 0
        this.first := 1
        this.Render()
        this.PreviewSelection()
    }

    static Render() {
        rows := Min(this.matches.Length, this.capacity)
        if (this.selected && this.selected < this.first)
            this.first := this.selected
        else if (this.selected >= this.first + rows)
            this.first := this.selected - rows + 1
        Loop rows {
            index := this.first + A_Index - 1
            entry := this.matches[index]
            this.numbers[A_Index].Text := index
            this.labels[A_Index].Text := entry.app != "" ? entry.app : entry.exe
            this.titles[A_Index].Text := entry.title
            this.Style(A_Index, index = this.selected, entry.app != "")
        }
        ; Rows past the matches are clipped by the window height.
        this.height := this.rows_top + rows * WindowTheme.Scale(32) + (rows ? WindowTheme.Scale(4) : 0)
        if (this.matches.Length > rows) {
            above := this.first - 1
            last := this.first + rows - 1
            below := this.matches.Length - last
            this.overflow.Text := (above ? "↑ " above " above   ·   " : "")
                . this.first "–" last " of " this.matches.Length
                . (below ? "   ·   ↓ " below " below" : "")
            this.overflow.Visible := true
            this.height += WindowTheme.Scale(24)
        } else {
            this.overflow.Visible := false
            this.overflow.Text := ""
        }
        WinMove(, , , this.height, this.window)
    }

    ; Restyling only changed rows avoids flicker while typing.
    static Style(row, selected, configured) {
        state := selected ":" configured
        if (this.styles[row] = state)
            return
        this.styles[row] := state
        WindowTheme.StyleCell(this.numbers[row], selected)
        WindowTheme.StyleCell(this.labels[row], selected, configured ? WindowTheme.configured_text : WindowTheme.unconfigured_text)
        WindowTheme.StyleCell(this.titles[row], selected)
    }

    static OnKeyDown(vk, lParam, msg, hwnd) {
        if !(this.active && this.edit && hwnd = this.edit.Hwnd)
            return
        ctrl := GetKeyState("Ctrl")
        if (vk = 0x0D)                                        ; Enter
            this.Pick(this.selected)
        else if (vk = 0x1B)                                   ; Esc
            this.Cancel()
        else if (vk = 0x28 || ctrl && (vk = 0x4A || vk = 0x4E))  ; Down, Ctrl+J, Ctrl+N
            this.Move(1)
        else if (vk = 0x26 || ctrl && (vk = 0x4B || vk = 0x50))  ; Up, Ctrl+K, Ctrl+P
            this.Move(-1)
        else if (ctrl && vk >= 0x31 && vk <= 0x39)            ; Ctrl+1..9
            this.Pick(vk - 0x30)
        else if (ctrl && vk = 0x08)
            this.DeleteWord()
        else
            return
        return 0
    }

    ; A plain Edit inserts a box character for Ctrl+Backspace instead of deleting a word.
    static DeleteWord() {
        caret := SendMessage(0xB0, 0, 0, this.edit) >> 16  ; EM_GETSEL
        kept := StrLen(RegExReplace(SubStr(this.edit.Value, 1, caret), "\S*\s*$"))
        SendMessage(0xB1, kept, caret, this.edit)               ; EM_SETSEL
        SendMessage(0xC2, true, StrPtr(""), this.edit)          ; EM_REPLACESEL
    }

    static OnActivate(wParam, lParam, msg, hwnd) {
        if (this.active && !this.closing && !this.previewing && this.window && hwnd = this.window.Hwnd && !(wParam & 0xFFFF))  ; WA_INACTIVE
            this.Hide(lParam)
    }

    ; Empty queries put the current window first, then configured windows; otherwise use stable score ties.
    static Filter(entries, query) {
        if (Trim(query, " ") = "") {
            matches := [], unconfigured := []
            for _, entry in entries {
                if entry.current
                    matches.InsertAt(1, entry)
                else if (entry.app != "")
                    matches.Push(entry)
                else
                    unconfigured.Push(entry)
            }
            matches.Push(unconfigured*)
            return matches
        }
        matches := [], scores := []
        for _, entry in entries {
            score := this.Score(query, entry.text)
            if (score < 0)
                continue
            i := scores.Length
            while (i && scores[i] < score)
                i--
            matches.InsertAt(i + 1, entry)
            scores.InsertAt(i + 1, score)
        }
        return matches
    }

    ; Space-separated terms must all match, in any order; -1 if one doesn't.
    static Score(query, text) {
        chars := StrSplit(StrLower(text))
        bonus := []
        prev := ""
        ; Word starts follow a non-alphanumeric character or a lower-to-upper case change.
        Loop Parse text {
            bonus.Push(prev = "" || !IsAlnum(prev, "Locale") || IsLower(prev, "Locale") && IsUpper(A_LoopField, "Locale") ? 8 : 0)
            prev := A_LoopField
        }
        total := 0
        for _, term in StrSplit(StrLower(query), " ") {
            if (term = "")
                continue
            score := this.ScoreTerm(term, chars, bonus)
            if (score < 0)
                return -1
            total += score
        }
        return total
    }

    ; Best in-order alignment of the term's characters (fzf-like): word starts and runs
    ; score higher, gaps cost 3 plus 1 per extra skipped character. -1 if there is none.
    static ScoreTerm(term, chars, bonus) {
        static NONE := -0x7FFFFFFF
        n := chars.Length
        prev := [], run := []
        Loop Parse term {
            i := A_Index, ch := A_LoopField
            cur := [], cur_run := []
            gap_best := NONE  ; max of prev[k] + k over k <= j - 2
            Loop n {
                j := A_Index
                if (i > 1 && j >= 3 && prev[j - 2] != NONE)
                    gap_best := Max(gap_best, prev[j - 2] + j - 2)
                score := NONE, carried := 0
                if (chars[j] = ch) {
                    if (i = 1) {
                        score := 1 + bonus[j], carried := bonus[j]
                    } else {
                        ; A run keeps the bonus of the word start it began at.
                        if (j > 1 && prev[j - 1] != NONE) {
                            carried := Max(bonus[j], run[j - 1], 4)
                            score := prev[j - 1] + 1 + carried
                        }
                        if (gap_best != NONE && gap_best - j + bonus[j] > score)
                            score := gap_best - j + bonus[j], carried := bonus[j]
                    }
                }
                cur.Push(score), cur_run.Push(carried)
            }
            prev := cur, run := cur_run
        }
        best := NONE
        for _, score in prev
            best := Max(best, score)
        return best = NONE ? -1 : Max(best, 0)
    }

    static Build(width, capacity, theme) {
        if this.window {
            this.window.Destroy()
        } else {
            OnMessage(0x0100, ObjBindMethod(this, "OnKeyDown"))   ; WM_KEYDOWN
            OnMessage(0x0006, ObjBindMethod(this, "OnActivate"))  ; WM_ACTIVATE
        }
        ; Not cycleable (tool window), so opening the picker leaves the window history alone.
        this.window := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale", "skok window search")
        ; Dialog processing can consume Esc without delivering WM_KEYDOWN to the edit.
        this.window.OnEvent("Escape", ObjBindMethod(this, "Cancel"))
        this.window.OnEvent("Close", ObjBindMethod(this, "Cancel"))
        WindowTheme.Frame(this.window.Hwnd)
        this.window.BackColor := WindowTheme.background
        s := ObjBindMethod(WindowTheme, "Scale")
        this.window.SetFont("s" WindowTheme.search_font_size " c" WindowTheme.text, WindowTheme.font_face)
        ; A single-line Edit draws text at its top, so a one-line-high Edit sits centered on a taller panel.
        panel := this.window.AddText("x" s(8) " y" s(8) " w" (width - s(16)) " +0x4000000 +Background" WindowTheme.panel_background, " ")  ; WS_CLIPSIBLINGS
        panel.GetPos(, , , &line_h)
        panel_h := line_h + s(16)
        panel.Move(, , , panel_h)
        this.edit := this.window.AddEdit("x" s(16) " y" (s(8) + (panel_h - line_h) // 2) " w" (width - s(32)) " h" line_h
            . " -E0x200 +Background" WindowTheme.panel_background)
        DllCall("SetWindowPos", "Ptr", this.edit.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)  ; HWND_TOP, no move/size/activate
        this.edit.OnEvent("Change", ObjBindMethod(this, "Update"))
        SendMessage(0x1501, true, StrPtr("Search windows"), this.edit)  ; EM_SETCUEBANNER
        this.rows_top := s(8) + panel_h + s(8)

        this.window.SetFont("s" WindowTheme.row_font_size " norm c" WindowTheme.text, WindowTheme.font_face)
        this.numbers := [], this.labels := [], this.titles := [], this.styles := []
        Loop capacity {
            y := this.rows_top + (A_Index - 1) * s(32)
            this.numbers.Push(WindowTheme.AddNumberCell(this.window, y))
            this.labels.Push(WindowTheme.AddTextCell(this.window, s(48), y, s(120)))
            this.titles.Push(WindowTheme.AddTextCell(this.window, s(168), y, width - s(176)))
            this.styles.Push("")
        }
        this.window.SetFont("norm c" WindowTheme.unconfigured_text)
        this.overflow := this.window.AddText("x" s(8) " y" (this.rows_top + capacity * s(32))
            . " w" (width - s(16)) " h" s(24) " +0x281 +Hidden +Background" WindowTheme.background, "")
        this.size := width ":" capacity ":" theme
        this.capacity := capacity
    }
}
