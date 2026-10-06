#Requires AutoHotkey v2.0

; Separate-process windows exercise the real Windows activation/message ordering.
windows := []
for _, name in ["origin", "preview"] {
    window := Gui(, "Search fixture " name)
    window.AddText(, name)
    window.OnEvent("Close", (*) => ExitApp())
    window.Show("w240 h100")
    windows.Push(window)
}