#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\window-theme.ahk
#Include %A_LineFile%\..\window-outline.ahk
#Include %A_LineFile%\..\window-peek.ahk

; A focusable picker that fuzzy-filters window entries ({hwnd, desktop, desktop_number, here, exe, title, current}) as you type.
class WindowSearch {
    static window := 0
    static edit := 0
    static status := 0
    static footer := []
    static footer_top := 0
    static numbers := []
    static icons := []
    static titles := []
    static exes := []
    static badges := []
    static backdrops := []
    static headers := []
    static rules := []
    static styles := []
    static texts := []
    static size := ""
    static width := 0
    static capacity := 0
    static rows_top := 0
    static height := 0
    static entries := []
    static matches := []
    static lines := []
    static line_of := []
    static grouped := true
    static selected := 0
    static digits := ""
    static first := 1
    static origin := 0
    static on_pick := 0
    static active := false
    static closing := false
    static previews := true

    static Show(entries, on_pick, origin := 0) {
        ; Repeated Show calls must not replace the origin with the picker itself.
        if this.active
            return
        theme := WindowTheme.Refresh()
        active := WinExist("A")
        this.origin := origin || active
        WindowTheme.OverlayWorkArea(active, &left, &top, &right, &bottom)
        width := WindowTheme.PopupWidth(720, left, right)
        ; Reserve room for the search box and footer even on short work areas.
        capacity := Max(1, Min(20, Floor((bottom - top - WindowTheme.Scale(136)) / WindowTheme.row_pitch)))
        ; Window, panel and edit colors are only set at build time.
        if (this.size != width ":" capacity ":" theme)
            this.Build(width, capacity, theme)

        for _, entry in entries {
            if !entry.HasOwnProp("icon")
                entry.icon := WindowTheme.WindowIcon(entry.hwnd)
            this.Prepare(entry)
        }
        this.entries := entries
        this.on_pick := on_pick
        this.closing := false
        this.digits := ""
        this.edit.Value := ""
        this.Update()
        this.active := true
        this.window.Show(WindowTheme.Placement(left, top, right, width) " h" this.height)
        WinActivate(this.window)
        this.edit.Focus()
        this.Peek()
    }

    static Hide() {
        this.closing := true
        this.digits := ""
        WindowOutline.Hide()
        WindowPeek.Hide()
        this.active := false
        if this.window
            this.window.Hide()
    }

    static Cancel(*) {
        this.Finish(this.origin)
    }

    ; Only the outcome is activated; activating it before hiding keeps this process allowed to set the foreground window.
    static Finish(hwnd) {
        if (!this.active || this.closing)
            return
        this.closing := true
        if (hwnd && WinExist(hwnd))
            this.on_pick.Call(hwnd)
        this.Hide()
    }

    static Pick(index) {
        if (!this.active || this.closing || index < 1 || index > this.matches.Length)
            return
        this.Finish(this.matches[index].hwnd)
    }

    ; Show the selection in place under the picker without activating it.
    static Peek() {
        hwnd := this.selected ? this.matches[this.selected].hwnd : 0
        if (this.previews && this.active && !this.closing && hwnd && WindowPeek.Show(hwnd, this.window.Hwnd)) {
            WindowOutline.Show(WindowPeek.window.Hwnd, this.window.Hwnd)
            return
        }
        WindowOutline.Hide()
        WindowPeek.Hide()
    }

    static Move(direction) {
        if (!this.active || this.closing)
            return
        if !(count := this.matches.Length)
            return
        this.selected := Mod(this.selected - 1 + direction + count, count) + 1
        this.Render()
        this.Peek()
    }

    static Update(*) {
        if this.closing
            return
        this.matches := this.Filter(this.entries, this.edit.Value)
        this.grouped := Trim(this.edit.Value, " ") = ""
        ; An empty query lists matches by desktop, so each group gets a header line.
        this.lines := [], this.line_of := []
        group := ""
        for index, entry in this.matches {
            key := entry.here ? "here" : entry.desktop_number ":" entry.desktop
            if (this.grouped && key !== group) {
                group := key
                this.lines.Push({header: entry.desktop, here: entry.here})
            }
            this.lines.Push({index: index})
            this.line_of.Push(this.lines.Length)
        }
        this.selected := this.matches.Length ? 1 : 0
        this.first := 1
        this.Render()
        this.Peek()
    }

    static Render() {
        lines := this.lines
        rows := Min(lines.Length, this.capacity)
        if this.selected {
            line := this.line_of[this.selected]
            ; Keep a group's header in view along with its first window.
            top := line > 1 && lines[line - 1].HasOwnProp("header") ? line - 1 : line
            if (top < this.first)
                this.first := top
            else if (line >= this.first + rows)
                this.first := line - rows + 1
        }
        s := ObjBindMethod(WindowTheme, "Scale")
        first_entry := last_entry := 0
        Loop rows {
            row := A_Index
            line := lines[this.first + row - 1]
            if line.HasOwnProp("header") {
                this.SetHeader(row, line.header)
                this.Style(row, "header", false, line.here)
                continue
            }
            index := line.index
            entry := this.matches[index]
            first_entry := first_entry || index
            last_entry := index
            WindowTheme.SetText(this.numbers[row], index)
            WindowTheme.SetIcon(this.icons[row], entry.icon)
            ; Ranked results end with a desktop badge; grouped ones use the full width.
            right := this.width - s(16)
            if !this.grouped
                right := WindowTheme.SetBadge(this.badges[row], entry.desktop
                    , entry.here ? WindowTheme.accent_text : WindowTheme.muted_text, right, index = this.selected) - s(12)
            this.SetTitle(row, entry.title, entry.exe, right)
            this.Style(row, this.grouped ? "entry" : "tagged", index = this.selected, entry.here)
        }
        ; Unused rows would otherwise overlap the footer.
        Loop this.capacity - rows
            this.Style(rows + A_Index, "none", false, false)
        WindowTheme.SetText(this.status, this.StatusText(rows, first_entry, last_entry))
        footer_top := this.rows_top + rows * WindowTheme.row_pitch + (rows ? s(4) : 0)
        if (footer_top != this.footer_top) {
            for _, cell in this.footer {
                cell.GetPos(, &y)
                cell.Move(, y + footer_top - this.footer_top)
            }
            this.footer_top := footer_top
        }
        ; Show applies the height itself, so an unchanged height needs no resize.
        height := footer_top + s(40)
        if (height != this.height) {
            this.height := height
            WinMove(, , , height, this.window)
        }
    }

    ; The footer's left side counts the matches, or shows which ones are scrolled out of view.
    static StatusText(rows, first_entry, last_entry) {
        count := this.matches.Length
        if (this.lines.Length > rows && first_entry) {
            above := first_entry - 1
            below := count - last_entry
            return (above ? "↑ " above " above   ·   " : "") first_entry "–" last_entry " of " count
                . (below ? "   ·   ↓ " below " below" : "")
        }
        if !count
            return "No matching windows"
        total := this.entries.Length
        return (count < total ? count " of " : "") total (total = 1 ? " window" : " windows")
    }

    ; The muted executable follows the title. Long titles are truncated first, leaving the executable up to a third of the row.
    static SetTitle(row, title, exe, right) {
        layout := title "`n" exe "`n" right
        if (this.texts[row] == layout)
            return
        this.texts[row] := layout
        s := ObjBindMethod(WindowTheme, "Scale")
        title_cell := this.titles[row], exe_cell := this.exes[row]
        x := s(76), gap := s(12)
        available := right - x
        exe_w := exe = "" ? 0 : Min(WindowTheme.TextWidth(exe_cell, exe) + s(2), available // 3)
        title_w := Max(0, Min(WindowTheme.TextWidth(title_cell, title) + s(2), available - (exe_w ? gap + exe_w : 0)))
        exe_x := x + title_w + gap
        title_cell.Move(, , title_w)
        exe_cell.Move(exe_x, , Max(0, right - exe_x))
        WindowTheme.SetText(title_cell, title)
        WindowTheme.SetText(exe_cell, exe)
    }

    ; A row is a desktop header, a window ("entry"), a window with its desktop badge ("tagged") or unused ("none").
    ; Restyling only changed rows avoids flicker while typing. Desktop text is muted for other desktops.
    static Style(row, kind, selected, here) {
        state := kind ":" selected ":" here
        previous := this.styles[row]
        if (previous = state)
            return
        this.styles[row] := state
        if (SubStr(previous, 1, InStr(previous ":", ":") - 1) != kind) {
            header := kind = "header"
            entry := kind = "entry" || kind = "tagged"
            this.backdrops[row].Visible := kind != "none"
            this.headers[row].Visible := header
            this.rules[row].Visible := header
            this.numbers[row].Visible := entry
            this.icons[row].Visible := entry
            this.titles[row].Visible := entry
            this.exes[row].Visible := entry
            this.badges[row].Visible := kind = "tagged"
        }
        if (kind = "none")
            return
        color := here ? WindowTheme.accent_text : WindowTheme.muted_text
        WindowTheme.StyleFill(this.backdrops[row], selected)
        if (kind = "header") {
            this.headers[row].SetFont("bold c" color)
            return
        }
        WindowTheme.StyleFill(this.icons[row], selected)
        WindowTheme.StyleCell(this.numbers[row], selected)
        WindowTheme.StyleCell(this.titles[row], selected)
        WindowTheme.StyleCell(this.exes[row], selected, WindowTheme.muted_text)
    }

    ; The divider starts just after the header text.
    static SetHeader(row, text) {
        cell := this.headers[row]
        if (cell.Text == text)
            return
        cell.Text := text
        s := ObjBindMethod(WindowTheme, "Scale")
        cell.GetPos(&x)
        w := Min(WindowTheme.TextWidth(cell, text) + s(4), this.width - x - s(24))
        cell.Move(, , w)
        this.rules[row].Move(x + w + s(8), , Max(0, this.width - x - w - s(24)))
    }

    static OnKeyDown(vk, lParam, msg, hwnd) {
        if !(this.active && this.edit && hwnd = this.edit.Hwnd)
            return
        ctrl := GetKeyState("Ctrl")
        if (ctrl && vk >= 0x30 && vk <= 0x39) {               ; Ctrl+0..9
            if !(lParam & 0x40000000)                         ; not auto-repeat
                this.TypeDigit(vk - 0x30)
            return 0
        }
        if (vk != 0x11)                                       ; held Ctrl auto-repeats
            this.digits := ""
        if (vk = 0x0D)                                        ; Enter
            this.Pick(this.selected)
        else if (vk = 0x1B)                                   ; Esc
            this.Cancel()
        else if (vk = 0x28 || ctrl && (vk = 0x4A || vk = 0x4E))  ; Down, Ctrl+J, Ctrl+N
            this.Move(1)
        else if (vk = 0x26 || ctrl && (vk = 0x4B || vk = 0x50))  ; Up, Ctrl+K, Ctrl+P
            this.Move(-1)
        else if (ctrl && vk = 0x08)
            this.DeleteWord()
        else
            return
        return 0
    }

    static OnKeyUp(vk, lParam, msg, hwnd) {
        if !(this.active && this.edit && hwnd = this.edit.Hwnd && vk = 0x11 && this.digits != "")
            return
        index := Integer(this.digits)
        this.digits := ""
        this.Pick(index)
    }

    ; Digits typed while Ctrl is held build a result number, picked on Ctrl release or once no digit can extend it.
    ; A digit that would overshoot the results starts a new number.
    static TypeDigit(digit) {
        count := this.matches.Length
        number := Integer(this.digits digit)
        if (number > count)
            number := digit
        if (number < 1 || number > count) {
            this.digits := ""
            return
        }
        if (number * 10 > count)
            return this.Pick(number)
        this.digits := String(number)
        this.selected := number
        this.Render()
        this.Peek()
    }

    ; A plain Edit inserts a box character for Ctrl+Backspace instead of deleting a word.
    static DeleteWord() {
        caret := SendMessage(0xB0, 0, 0, this.edit) >> 16  ; EM_GETSEL
        kept := StrLen(RegExReplace(SubStr(this.edit.Value, 1, caret), "\S*\s*$"))
        SendMessage(0xB1, kept, caret, this.edit)               ; EM_SETSEL
        SendMessage(0xC2, true, StrPtr(""), this.edit)          ; EM_REPLACESEL
    }

    static OnActivate(wParam, lParam, msg, hwnd) {
        if (this.active && !this.closing && this.window && hwnd = this.window.Hwnd && !(wParam & 0xFFFF))  ; WA_INACTIVE
            this.Hide()
    }

    ; Empty queries group by desktop (current first), preserving recent-use order within each; typing ranks by score.
    static Filter(entries, query) {
        if (Trim(query, " ") = "") {
            matches := [], elsewhere := []
            for _, entry in entries {
                if entry.current
                    matches.InsertAt(1, entry)
                else if entry.here
                    matches.Push(entry)
                else {
                    i := elsewhere.Length
                    while (i && elsewhere[i].desktop_number > entry.desktop_number)
                        i--
                    elsewhere.InsertAt(i + 1, entry)
                }
            }
            matches.Push(elsewhere*)
            return matches
        }
        matches := [], scores := []
        terms := []
        for _, term in StrSplit(StrLower(query), " ") {
            if (term != "")
                terms.Push(term)
        }
        for _, entry in entries {
            score := this.Score(terms, entry)
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

    ; Entries are rescored on every keystroke, so derive their search text once.
    static Prepare(entry) {
        text := entry.desktop " " RegExReplace(entry.exe, "i)\.exe$") " " entry.title
        entry.lower := StrLower(text)
        entry.chars := StrSplit(entry.lower)
        entry.terms := Map()
        entry.bonus := []
        prev := ""
        ; Word starts follow a non-alphanumeric character or a lower-to-upper case change.
        Loop Parse text {
            entry.bonus.Push(prev = "" || !IsAlnum(prev, "Locale") || IsLower(prev, "Locale") && IsUpper(A_LoopField, "Locale") ? 8 : 0)
            prev := A_LoopField
        }
    }

    ; Lowercase terms must all match, in any order; -1 if one doesn't.
    static Score(terms, entry) {
        ; Cheap in-order check first; most entries fail it and skip the alignment.
        for _, term in terms {
            if !this.IsSubsequence(term, entry.lower)
                return -1
        }
        total := 0
        scored := Map()
        for _, term in terms {
            score := this.ScoreTerm(term, entry, scored).best
            if (score <= 0)
                return -1
            total += score
        }
        ; Keep only the current terms so the cache stays one query deep.
        entry.terms := scored
        return total
    }

    static IsSubsequence(term, text) {
        pos := 0
        Loop Parse term {
            if !(pos := InStr(text, A_LoopField, false, pos + 1))
                return false
        }
        return true
    }

    ; Best in-order alignment of the term's characters (fzf-like): word starts and runs
    ; score higher, gaps cost 3 plus 1 per extra skipped character. best is -1 if there is none.
    ; Rows depend only on the term's prefix, so typing resumes from the previous query's rows.
    static ScoreTerm(term, entry, scored) {
        static NONE := -0x7FFFFFFF
        if scored.Has(term)
            return scored[term]
        cached := entry.terms
        len := StrLen(term)
        while (len && !cached.Has(SubStr(term, 1, len)))
            len--
        if len {
            state := cached[SubStr(term, 1, len)]
            prev := state.prev, run := state.run, best := state.best
        } else {
            prev := run := 0
        }
        if (len < StrLen(term)) {
            chars := entry.chars, bonus := entry.bonus, n := chars.Length
            Loop Parse SubStr(term, len + 1) {
                ch := A_LoopField
                cur := [], cur_run := []
                cur.Capacity := cur_run.Capacity := n
                gap_best := NONE  ; max of prev[k] + k over k <= j - 2
                Loop n {
                    j := A_Index
                    if (prev && j >= 3 && (p := prev[j - 2]) != NONE && p + j - 2 > gap_best)
                        gap_best := p + j - 2
                    if (chars[j] != ch) {
                        cur.Push(NONE), cur_run.Push(0)
                        continue
                    }
                    b := bonus[j]
                    if !prev {
                        cur.Push(1 + b), cur_run.Push(b)
                        continue
                    }
                    score := NONE, carried := 0
                    ; A run keeps the bonus of the word start it began at.
                    if (j > 1 && (p := prev[j - 1]) != NONE) {
                        carried := Max(b, run[j - 1], 4)
                        score := p + 1 + carried
                    }
                    if (gap_best != NONE && gap_best - j + b > score)
                        score := gap_best - j + b, carried := b
                    cur.Push(score), cur_run.Push(carried)
                }
                prev := cur, run := cur_run
            }
            best := NONE
            for _, score in prev
                if (score > best)
                    best := score
            best := best = NONE ? -1 : best
        }
        return scored[term] := {prev: prev, run: run, best: best}
    }

    static Build(width, capacity, theme) {
        if this.window {
            this.window.Destroy()
        } else {
            OnMessage(0x0100, ObjBindMethod(this, "OnKeyDown"))   ; WM_KEYDOWN
            OnMessage(0x0101, ObjBindMethod(this, "OnKeyUp"))     ; WM_KEYUP
            OnMessage(0x0006, ObjBindMethod(this, "OnActivate"))  ; WM_ACTIVATE
        }
        this.window := WindowTheme.NewPopup("skok window search", "", WindowTheme.search_font_size)
        ; Dialog processing can consume Esc without delivering WM_KEYDOWN to the edit.
        this.window.OnEvent("Escape", ObjBindMethod(this, "Cancel"))
        this.window.OnEvent("Close", ObjBindMethod(this, "Cancel"))
        s := ObjBindMethod(WindowTheme, "Scale")
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
        this.numbers := [], this.icons := [], this.titles := [], this.exes := [], this.badges := [], this.backdrops := []
        this.headers := [], this.rules := [], this.styles := [], this.texts := []
        Loop capacity {
            y := this.rows_top + (A_Index - 1) * WindowTheme.row_pitch
            this.numbers.Push(WindowTheme.AddNumberCell(this.window, y))
            this.icons.Push(WindowTheme.AddIconCell(this.window, y))
            this.titles.Push(WindowTheme.AddTextCell(this.window, s(76), y, 0))
            this.exes.Push(WindowTheme.AddTextCell(this.window, s(76), y, 0))
            this.badges.Push(WindowTheme.AddBadge(this.window, y + s(5), "+Hidden"))
            this.window.SetFont("bold")
            this.headers.Push(WindowTheme.AddTextCell(this.window, s(16), y, s(8), "+Hidden"))
            this.window.SetFont("norm")
            this.rules.Push(this.window.AddText("x" s(16) " y" (y + s(15)) " w0 h" Max(1, s(1)) " +Hidden +Background" WindowTheme.divider))
            ; Fills the gaps between the row's cells with the row's selection color.
            this.backdrops.Push(WindowTheme.AddBackdrop(this.window, s(8), y, width - s(16), s(30)))
            this.styles.Push(""), this.texts.Push("")
        }

        ; Footer cells are laid out from y = 0 and moved below the rows by Render.
        this.window.SetFont("s" WindowTheme.small_font_size " norm c" WindowTheme.text)
        this.footer := [this.window.AddText("x0 y0 w" width " h" Max(1, s(1)) " +Background" WindowTheme.divider)]
        right := width - s(16)
        for _, hint in [["Cancel", "Esc"], ["Pick", "Ctrl", "1–9"], ["Switch to", "Enter"]] {  ; right to left
            Loop hint.Length - 1 {
                key := WindowTheme.AddBadge(this.window, s(10))
                right := WindowTheme.SetBadge(key, hint[hint.Length - A_Index + 1], WindowTheme.text, right) - s(4)
                this.footer.Push(key)
            }
            label := WindowTheme.AddTextCell(this.window, 0, s(5), 0)
            WindowTheme.SetText(label, hint[1])
            w := WindowTheme.TextWidth(label, hint[1]) + s(2)
            right -= s(4) + w
            label.Move(right, , w)
            this.footer.Push(label)
            right -= s(20)
        }
        this.window.SetFont("c" WindowTheme.muted_text)
        this.status := WindowTheme.AddTextCell(this.window, s(16), s(5), Max(0, right - s(16)))
        this.footer.Push(this.status)
        this.footer_top := 0
        this.size := width ":" capacity ":" theme
        this.width := width
        this.capacity := capacity
    }
}
