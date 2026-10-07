#Requires AutoHotkey v2.0
#Include ..\window-search.ahk
#Include lib.ahk

Entry(hwnd, app, current := false, text := "same") {
    entry := {hwnd: hwnd, app: app, current: current, exe: "", title: text}
    WindowSearch.Prepare(entry)
    return entry
}

AssertOrder(entries, query, expected) {
    matches := WindowSearch.Filter(entries, query)
    if (matches.Length != expected.Length)
        throw Error("Unexpected result count")
    for i, hwnd in expected {
        if (matches[i].hwnd != hwnd)
            throw Error("Unexpected window at result " i)
    }
}

try {
    ; Input is recent-use order with the current window last.
    AssertOrder([Entry(1, ""), Entry(2, "app"), Entry(3, "app", true)], "", [3, 2, 1])
    entries := [Entry(1, "app"), Entry(2, ""), Entry(3, "app"), Entry(4, "", true)]
    AssertOrder(entries, "", [4, 1, 3, 2])
    AssertOrder(entries, "   ", [4, 1, 3, 2])
    ; Typing keeps stable score ties; clearing restores the current window first.
    AssertOrder(entries, "same", [1, 2, 3, 4])
    AssertOrder(entries, "", [4, 1, 3, 2])
    AssertOrder([Entry(1, ""), Entry(2, "app")], "", [2, 1])
    AssertOrder([Entry(1, "", true)], "", [1])
    AssertOrder([], "", [])
    AssertOrder([Entry(1, "app", false, "needle"), Entry(2, "", true, "other")], "needle", [1])
    ; The prefilter must reject an out-of-order or overlong term, but keep gapped and multi-term matches.
    AssertOrder([Entry(1, "", false, "ab"), Entry(2, "", false, "ba")], "abb", [])
    AssertOrder([Entry(1, "", false, "a-x-b"), Entry(2, "", false, "ba")], "ab", [1])
    AssertOrder([Entry(1, "vscode", false, "README.md"), Entry(2, "", false, "vscode")], "rdm vscode", [1])
    ; Rows cached from earlier keystrokes must give the same order as scoring from scratch.
    Fresh() => [Entry(1, "", false, "b-a-ab"), Entry(2, "", false, "abab"), Entry(3, "", false, "b ab"), Entry(4, "", false, "Ab Ba")]
    typed := Fresh()
    for _, query in ["a", "ab", "aba", "ab", "ab ", "ab b", "ab ba", "b", "ba"] {
        expected := []
        for _, match in WindowSearch.Filter(Fresh(), query)
            expected.Push(match.hwnd)
        AssertOrder(typed, query, expected)
    }
    FileAppend("Window search tests passed.`n", "*")
    ExitApp(0)
} catch as err {
    ReportError(err, "window-search")
    ExitApp(1)
}