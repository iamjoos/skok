#Requires AutoHotkey v2.0

; Wraps VirtualDesktopAccessor.dll (https://github.com/Ciantic/VirtualDesktopAccessor).
; Desktop numbers are 0-based here; the config numbers desktops from 1.
class VirtualDesktopAccessor {
    static exports := ["GetDesktopCount", "GetCurrentDesktopNumber", "GoToDesktopNumber", "CreateDesktop"
        , "GetDesktopName", "SetDesktopName", "GetWindowDesktopNumber", "MoveWindowToDesktopNumber"
        , "IsPinnedWindow", "IsPinnedApp", "PinWindow", "UnPinWindow", "UnPinApp"
        , "RegisterPostMessageHook", "UnregisterPostMessageHook", "RestartVirtualDesktopAccessor"]

    __New(path) {
        if (A_PtrSize != 8)
            throw Error("VirtualDesktopAccessor.dll needs 64-bit AutoHotkey; run skok with AutoHotkey64.exe.")
        if !FileExist(path)
            throw Error("VirtualDesktopAccessor.dll not found at " path ".")
        if !(this.module := DllCall("LoadLibrary", "Str", path, "Ptr"))
            throw Error("Could not load " path " (error " A_LastError ").")
        this.procs := Map()
        for _, name in VirtualDesktopAccessor.exports {
            if !(proc := DllCall("GetProcAddress", "Ptr", this.module, "AStr", name, "Ptr"))
                throw Error(path " has no " name " export; use a current release.")
            this.procs[name] := proc
        }
        ; A build that doesn't match this Windows version can't reach the virtual desktop service.
        if (this.Count() < 1 || this.Current() < 0)
            throw Error("VirtualDesktopAccessor.dll cannot read virtual desktops; it may not support this Windows build.")
    }

    Count() => DllCall(this.procs["GetDesktopCount"], "Int")
    Current() => DllCall(this.procs["GetCurrentDesktopNumber"], "Int")
    GoTo(number) => DllCall(this.procs["GoToDesktopNumber"], "Int", number, "Int")
    Create() => DllCall(this.procs["CreateDesktop"], "Int")
    ; -1 if the window isn't on a virtual desktop.
    WindowDesktop(hwnd) => DllCall(this.procs["GetWindowDesktopNumber"], "Ptr", hwnd, "Int")
    MoveWindow(hwnd, number) => DllCall(this.procs["MoveWindowToDesktopNumber"], "Ptr", hwnd, "Int", number, "Int")
    IsPinned(hwnd) => DllCall(this.procs["IsPinnedWindow"], "Ptr", hwnd, "Int") = 1
        || DllCall(this.procs["IsPinnedApp"], "Ptr", hwnd, "Int") = 1
    ; Reconnects to the virtual desktop service after Explorer restarts.
    Restart() => DllCall(this.procs["RestartVirtualDesktopAccessor"], "Int")

    ; Unpins the window and its app if either is pinned, else pins the window. Returns whether it ends up pinned.
    TogglePin(hwnd) {
        if this.IsPinned(hwnd) {
            DllCall(this.procs["UnPinWindow"], "Ptr", hwnd, "Int")
            DllCall(this.procs["UnPinApp"], "Ptr", hwnd, "Int")
        } else {
            DllCall(this.procs["PinWindow"], "Ptr", hwnd, "Int")
        }
        return this.IsPinned(hwnd)
    }

    ; Names are UTF-8; an unnamed desktop returns "".
    Name(number) {
        name := Buffer(1024, 0)
        if (DllCall(this.procs["GetDesktopName"], "Int", number, "Ptr", name, "UPtr", name.Size, "Int") != 1)
            return ""
        return StrGet(name, "UTF-8")
    }

    SetName(number, name) {
        utf8 := Buffer(StrPut(name, "UTF-8"))
        StrPut(name, utf8, "UTF-8")
        return DllCall(this.procs["SetDesktopName"], "Int", number, "Ptr", utf8, "Int")
    }

    ; Posts message to hwnd on every desktop switch, with wParam the old and lParam the new desktop number.
    Listen(hwnd, message) {
        DllCall(this.procs["UnregisterPostMessageHook"], "Ptr", hwnd)
        DllCall(this.procs["RegisterPostMessageHook"], "Ptr", hwnd, "UInt", message)
    }
}
