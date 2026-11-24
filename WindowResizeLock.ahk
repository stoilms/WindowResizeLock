#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; WindowLock — make other apps' windows unresizable.
;
; Hotkeys
;   Win+Shift+L   toggle the active window
;   Win+Shift+K   toggle the window under the mouse
; Tray menu does the same thing. Quit from the tray and every window you
; locked is restored.
;
; What it changes
;   Removes WS_THICKFRAME (0x40000), the style Windows uses for a sizing
;   border. Edge-dragging stops. The border itself usually stays.
;   Also removes WS_MAXIMIZEBOX so the maximize button cannot change the size.
;   Set LOCK_MASK below to 0x40000 if you only want to block edge-dragging.
;
; Some apps (Electron, games, WinUI) redraw their own frame and will ignore
; this. The timer puts the style back when a normal Win32 app resets it.

WS_THICKFRAME  := 0x00040000
WS_MAXIMIZEBOX := 0x00010000
LOCK_MASK      := WS_THICKFRAME | WS_MAXIMIZEBOX

GWL_STYLE := -16
SWP_NOSIZE      := 0x0001
SWP_NOMOVE      := 0x0002
SWP_NOZORDER    := 0x0004
SWP_NOACTIVATE  := 0x0010
SWP_FRAMECHANGED := 0x0020
FRAME_FLAGS := SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED

GetLong := A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong"
SetLong := A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong"

; hwnd => style the window had before we locked it
locked := Map()

A_IconTip := "Window Lock — Win+Shift+L toggles resize"
A_TrayMenu.Delete()
A_TrayMenu.Add("Toggle active window", (*) => Toggle(WinGetID("A")))
A_TrayMenu.Add("Toggle window under cursor", (*) => Toggle(WindowUnderMouse()))
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())

OnExit(RestoreAll)
SetTimer(Enforce, 250)
TrayTip("Win+Shift+L toggles the active window.`nWin+Shift+K toggles the window under the cursor.", "Window Lock")

#+l::Toggle(WinGetID("A"))
#+k::Toggle(WindowUnderMouse())

Toggle(hwnd) {
    global locked
    hwnd := Integer(hwnd)
    if !hwnd || IsShell(hwnd)
        return
    if locked.Has(hwnd) {
        Restore(hwnd, locked[hwnd])
        locked.Delete(hwnd)
        Tip("Resizable: " TitleOf(hwnd))
    } else {
        orig := GetStyle(hwnd)
        if (orig = 0 && A_LastError)
            return
        locked[hwnd] := orig
        EnsureLocked(hwnd)
        Tip("Not resizable: " TitleOf(hwnd))
    }
}

Enforce() {
    global locked
    dead := []
    for hwnd, orig in locked {
        if !WinExist("ahk_id " hwnd)
            dead.Push(hwnd)
        else
            EnsureLocked(hwnd)
    }
    for index, hwnd in dead
        locked.Delete(hwnd)
}

RestoreAll(*) {
    global locked
    for hwnd, orig in locked.Clone() {
        if WinExist("ahk_id " hwnd)
            Restore(hwnd, orig)
    }
    locked.Clear()
}

EnsureLocked(hwnd) {
    global locked, LOCK_MASK
    cur := GetStyle(hwnd)
    desired := cur & ~LOCK_MASK
    if cur != desired {
        SetStyle(hwnd, desired)
        FrameChanged(hwnd)
    }
}

Restore(hwnd, orig) {
    global LOCK_MASK
    cur := GetStyle(hwnd)
    desired := (cur & ~LOCK_MASK) | (orig & LOCK_MASK)
    if cur != desired {
        SetStyle(hwnd, desired)
        FrameChanged(hwnd)
    }
}

GetStyle(hwnd) {
    global GetLong, GWL_STYLE
    DllCall("SetLastError", "UInt", 0)
    return DllCall(GetLong, "Ptr", hwnd, "Int", GWL_STYLE, "UInt")
}

SetStyle(hwnd, style) {
    global SetLong, GWL_STYLE
    DllCall(SetLong, "Ptr", hwnd, "Int", GWL_STYLE, "Ptr", style & 0xFFFFFFFF)
}

FrameChanged(hwnd) {
    global FRAME_FLAGS
    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", FRAME_FLAGS)
}

WindowUnderMouse() {
    MouseGetPos(, , &hwnd)
    return hwnd
}

IsShell(hwnd) {
    class := WinGetClass("ahk_id " hwnd)
    return class ~= "i)^(Progman|WorkerW|Shell_TrayWnd)$"
}

TitleOf(hwnd) {
    try
        return WinGetTitle("ahk_id " hwnd)
    return ""
}

Tip(msg) {
    ToolTip(msg)
    SetTimer(RemoveTip, -1400)
}

RemoveTip() {
    ToolTip()
}
