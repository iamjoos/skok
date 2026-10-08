#Requires AutoHotkey v2.0
; Outline assertions shared by the cycle and search suites; defines functions only.
#Include lib.ahk

; Physical pixels, like the DWM bounds the outline follows.
PhysicalPos(hwnd, &x, &y, &w, &h) {
    context := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try WinGetPos(&x, &y, &w, &h, hwnd)
    finally DllCall("SetThreadDpiAwarenessContext", "Ptr", context, "Ptr")
}

IsAbove(upper, lower) {
    hwnd := lower
    while (hwnd := DllCall("GetWindow", "Ptr", hwnd, "UInt", 3, "Ptr")) {  ; GW_HWNDPREV
        if (hwnd = upper)
            return true
    }
    return false
}

AssertOutline(hwnd, overlay := 0) {
    AssertEqual(WindowOutline.target, hwnd)
    AssertEqual(WindowOutline.bars.Length, 4)
    rect := Buffer(16, 0)
    Assert(DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", rect, "UInt", 16, "Int") = 0, "Could not read visible frame")
    left := NumGet(rect, 0, "Int"), top := NumGet(rect, 4, "Int")
    right := NumGet(rect, 8, "Int"), bottom := NumGet(rect, 12, "Int")
    thickness := Min(WindowTheme.Scale(3), Floor((right - left) / 2), Floor((bottom - top) / 2))
    expected := [[left, top, right - left, thickness], [left, bottom - thickness, right - left, thickness]
        , [left, top, thickness, bottom - top], [right - thickness, top, thickness, bottom - top]]
    for i, bar in WindowOutline.bars {
        Assert(DllCall("IsWindowVisible", "Ptr", bar.Hwnd), "Outline bar is hidden")
        Assert((WinGetExStyle(bar) & 0x080800A0) = 0x080800A0, "Outline is not click-through/nonactivating")
        PhysicalPos(bar.Hwnd, &x, &y, &w, &h)
        Assert(x = expected[i][1] && y = expected[i][2] && w = expected[i][3] && h = expected[i][4], "Outline does not follow visible bounds")
        AssertEqual(bar.BackColor, WindowTheme.selected_background)
        if overlay
            Assert(IsAbove(overlay, bar.Hwnd), "Outline covers its overlay")
    }
}

AssertNoOutline(message) {
    Assert(!WindowOutline.target, message)
    for _, bar in WindowOutline.bars
        Assert(!DllCall("IsWindowVisible", "Ptr", bar.Hwnd), message)
}

; The window is shown in place, under its overlay and outline, without being activated.
AssertPeekShown(hwnd, overlay := 0, outlined := true) {
    AssertEqual(WindowPeek.target, hwnd)
    peek := WindowPeek.window.Hwnd
    Assert(DllCall("IsWindowVisible", "Ptr", peek), "Peek is hidden")
    Assert((WinGetExStyle(peek) & 0x080800A0) = 0x080800A0, "Peek is not click-through/nonactivating")
    if overlay
        Assert(IsAbove(overlay, peek), "Peek covers its overlay")
    PhysicalPos(peek, &x, &y, &w, &h)
    if (WinGetMinMax(hwnd) = -1) {
        Assert(w > 0 && h > 0, "Minimized peek is empty")
    } else {
        Assert(WindowOutline.FrameRect(hwnd, &left, &top, &width, &height), "Could not read peek target frame")
        Assert(x = left && y = top && w = width && h = height, "Peek does not cover the visible frame")
    }
    if outlined
        AssertOutline(peek, overlay)
    else
        AssertNoOutline("Disabled highlight outlined the peek")
}

AssertNoPeek(message) {
    Assert(!WindowPeek.target, message)
    if WindowPeek.window
        Assert(!DllCall("IsWindowVisible", "Ptr", WindowPeek.window.Hwnd), message)
    AssertNoOutline(message)
}

; Positions of the given windows in z-order, the order Alt+Tab follows after activations.
ZOrder(hwnds) {
    order := []
    for _, hwnd in WinGetList()
        for i, candidate in hwnds
            if (candidate = hwnd)
                order.Push(i)
    return order
}
