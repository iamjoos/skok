#Requires AutoHotkey v2.0
#Include ..\window-search.ahk

Entry(hwnd, app, current := false, text := "same") {
    return {hwnd: hwnd, app: app, current: current, text: text}
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
    FileAppend("Window search tests passed.`n", "*")
    ExitApp(0)
} catch as err {
    FileAppend(err.Message "`n", "**")
    ExitApp(1)
}