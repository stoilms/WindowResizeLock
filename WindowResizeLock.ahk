#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; WindowLock — make other apps' windows unresizable.
;
; Hotkey (default Win+Shift+L): toggle the active window
; Tray → Open Window Lock: change hotkey, pick windows, remember locks
; Quit from the tray and every locked window is restored.
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

CONFIG_PATH := A_ScriptDir "\WindowResizeLock.ini"
DEFAULT_HOTKEY := "#+l"

; hwnd => style the window had before we locked it
locked := Map()
; "exePath|title" keys of windows to re-lock on launch / when they reappear
remembered := Map()
settings := { hotkey: DEFAULT_HOTKEY, remember: false }
ui := { gui: 0, lv: 0, hotkeyText: 0, rememberCb: 0, capturing: false, captureIh: 0 }
hwndByRow := Map()

LoadSettings()
ApplyHotkey(settings.hotkey)
if settings.remember
    ApplyRemembered()

A_IconTip := "Window Lock — " HotkeyLabel(settings.hotkey) " toggles resize"
A_TrayMenu.Delete()
A_TrayMenu.Add("Open Window Lock", (*) => ShowUi())
A_TrayMenu.Add("Toggle active window", (*) => Toggle(WinGetID("A")))
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Open Window Lock"
A_TrayMenu.ClickCount := 1

OnExit(OnScriptExit)
SetTimer(Enforce, 250)
if settings.remember
    SetTimer(ApplyRemembered, 2000)

TrayTip(HotkeyLabel(settings.hotkey) " toggles the active window.`nOpen Window Lock from the tray for settings.", "Window Lock")

; --- Settings / persistence -------------------------------------------------

LoadSettings() {
    global CONFIG_PATH, DEFAULT_HOTKEY, settings, remembered
    settings.hotkey := IniRead(CONFIG_PATH, "Settings", "Hotkey", DEFAULT_HOTKEY)
    settings.remember := IniRead(CONFIG_PATH, "Settings", "Remember", "0") = "1"
    remembered := Map()
    ; AHK v2 throws when the section/file is missing — do not use v1's "ERROR" sentinel.
    try
        section := IniRead(CONFIG_PATH, "Remembered")
    catch
        return
    if (section = "")
        return
    for line in StrSplit(section, "`n") {
        if (line = "")
            continue
        parts := StrSplit(line, "=", , 2)
        if parts.Length
            remembered[DecodeKey(parts[1])] := true
    }
}

SaveSettings() {
    global CONFIG_PATH, settings, remembered
    content := "[Settings]`r`nHotkey=" settings.hotkey "`r`nRemember=" (settings.remember ? "1" : "0") "`r`n`r`n[Remembered]`r`n"
    if settings.remember {
        for key, _ in remembered
            content .= EncodeKey(key) "=1`r`n"
    }
    f := FileOpen(CONFIG_PATH, "w", "UTF-8")
    f.Write(content)
    f.Close()
}

EncodeKey(key) => StrReplace(StrReplace(key, "\", "\\"), "=", "\e")
DecodeKey(key) => StrReplace(StrReplace(key, "\e", "="), "\\", "\")

WindowKey(hwnd) {
    try
        exe := WinGetProcessPath("ahk_id " hwnd)
    catch
        exe := ""
    return exe "|" TitleOf(hwnd)
}

RememberAdd(hwnd) {
    global remembered, settings
    if !settings.remember
        return
    remembered[WindowKey(hwnd)] := true
    SaveSettings()
}

RememberRemove(hwnd) {
    global remembered, settings
    if !settings.remember
        return
    key := WindowKey(hwnd)
    if remembered.Has(key)
        remembered.Delete(key)
    SaveSettings()
}

ApplyRemembered(*) {
    global remembered, locked, settings
    if !settings.remember || !remembered.Count
        return
    for hwnd in WinGetList() {
        if !IsLockable(hwnd) || locked.Has(Integer(hwnd))
            continue
        if remembered.Has(WindowKey(hwnd))
            LockWindow(hwnd, false)
    }
}

; --- Hotkey -----------------------------------------------------------------

ApplyHotkey(newHotkey) {
    global settings, DEFAULT_HOTKEY
    old := settings.hotkey
    try {
        if old != ""
            try Hotkey(old, "Off")
        Hotkey(newHotkey, (*) => Toggle(WinGetID("A")), "On")
        settings.hotkey := newHotkey
    } catch as err {
        if old != "" {
            try Hotkey(old, (*) => Toggle(WinGetID("A")), "On")
        } else {
            Hotkey(DEFAULT_HOTKEY, (*) => Toggle(WinGetID("A")), "On")
            settings.hotkey := DEFAULT_HOTKEY
        }
        throw err
    }
    A_IconTip := "Window Lock — " HotkeyLabel(settings.hotkey) " toggles resize"
}

HotkeyLabel(hk) {
    out := hk
    out := StrReplace(out, "#", "Win+")
    out := StrReplace(out, "+", "Shift+")
    out := StrReplace(out, "^", "Ctrl+")
    out := StrReplace(out, "!", "Alt+")
    if RegExMatch(out, "^(.*)([a-z])$", &m)
        out := m[1] StrUpper(m[2])
    return out
}

StartHotkeyCapture(*) {
    global ui, settings
    if ui.capturing
        return
    ui.capturing := true
    ui.hotkeyText.Value := "Press a shortcut… (Esc cancels)"

    ih := InputHook("L0", "{Esc}")
    ih.KeyOpt("{All}", "S")
    ih.OnKeyDown := HotkeyCapture_OnKeyDown
    ui.captureIh := ih
    ih.Start()
    ih.Wait()
    ui.captureIh := 0
    ui.capturing := false

    if (ih.EndReason = "EndKey") {
        ui.hotkeyText.Value := HotkeyLabel(settings.hotkey)
    }
}

HotkeyCapture_OnKeyDown(ih, vk, sc) {
    global ui, settings
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if (name = "")
        name := GetKeyName(Format("vk{:x}", vk))
    if (name = "" || name = "Escape")
        return
    if name ~= "i)^(L|R)?(Control|Ctrl|Alt|Shift|Win|LWin|RWin)$"
        return

    mods := ""
    if GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        mods .= "#"
    if GetKeyState("Ctrl", "P")
        mods .= "^"
    if GetKeyState("Alt", "P")
        mods .= "!"
    if GetKeyState("Shift", "P")
        mods .= "+"

    key := StrLen(name) = 1 ? StrLower(name) : name
    newHk := mods key
    ih.Stop()

    try {
        ApplyHotkey(newHk)
        SaveSettings()
        ui.hotkeyText.Value := HotkeyLabel(settings.hotkey)
        Tip("Hotkey set to " HotkeyLabel(settings.hotkey))
    } catch as err {
        ui.hotkeyText.Value := HotkeyLabel(settings.hotkey)
        MsgBox("Could not set that hotkey:`n" err.Message, "Window Lock", "IconX")
    }
}

; --- Lock / restore ---------------------------------------------------------

IsLockable(hwnd) {
    hwnd := Integer(hwnd)
    if !hwnd || !WinExist("ahk_id " hwnd) || IsShell(hwnd)
        return false
    try {
        if WinGetTitle("ahk_id " hwnd) = ""
            return false
        if WinGetMinMax("ahk_id " hwnd) = -1
            return false
        style := GetStyle(hwnd)
        if !(style & 0x10000000)  ; WS_VISIBLE
            return false
    } catch
        return false
    return true
}

Toggle(hwnd) {
    hwnd := Integer(hwnd)
    if !IsLockable(hwnd)
        return
    global locked
    if locked.Has(hwnd) {
        UnlockWindow(hwnd)
        Tip("Resizable: " TitleOf(hwnd))
    } else {
        LockWindow(hwnd)
        Tip("Not resizable: " TitleOf(hwnd))
    }
    RefreshUiList()
}

LockWindow(hwnd, updateRemember := true) {
    global locked
    hwnd := Integer(hwnd)
    if !hwnd || locked.Has(hwnd)
        return
    orig := GetStyle(hwnd)
    if (orig = 0 && A_LastError)
        return
    locked[hwnd] := orig
    EnsureLocked(hwnd)
    if updateRemember
        RememberAdd(hwnd)
}

UnlockWindow(hwnd) {
    global locked
    hwnd := Integer(hwnd)
    if !locked.Has(hwnd)
        return
    Restore(hwnd, locked[hwnd])
    locked.Delete(hwnd)
    RememberRemove(hwnd)
}

SetLockedState(hwnd, shouldLock) {
    global locked
    hwnd := Integer(hwnd)
    if shouldLock {
        if !locked.Has(hwnd)
            LockWindow(hwnd)
    } else if locked.Has(hwnd) {
        UnlockWindow(hwnd)
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
    changed := false
    for , hwnd in dead {
        locked.Delete(hwnd)
        changed := true
    }
    ; Do not drop remembered entries when a window closes — they re-apply later.
    if changed
        RefreshUiList()
}

OnScriptExit(*) {
    SaveSettings()
    RestoreAll()
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
    global LOCK_MASK
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

IsShell(hwnd) {
    try
        class := WinGetClass("ahk_id " hwnd)
    catch
        return true
    return class ~= "i)^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd|NotifyIconOverflowWindow)$"
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

; --- UI ---------------------------------------------------------------------

ShowUi(*) {
    global ui
    if ui.gui {
        RefreshUiList()
        ui.gui.Show()
        return
    }
    BuildUi()
    RefreshUiList()
    ui.gui.Show()
}

BuildUi() {
    global ui, settings
    g := Gui("+Resize MinSize420x360", "Window Lock")
    g.OnEvent("Close", (*) => g.Hide())
    g.OnEvent("Escape", (*) => g.Hide())
    g.SetFont("s10", "Segoe UI")

    g.Add("Text", "xm ym Section", "Toggle-active hotkey")
    ui.hotkeyText := g.Add("Edit", "xm y+4 w260 ReadOnly", HotkeyLabel(settings.hotkey))
    g.Add("Button", "x+8 yp w110", "Change…").OnEvent("Click", StartHotkeyCapture)

    ui.rememberCb := g.Add("Checkbox", "xm y+14 w400 Checked" (settings.remember ? "1" : "0"),
        "Remember locked windows and re-lock them on next launch")
    ui.rememberCb.OnEvent("Click", OnRememberToggle)

    g.Add("Text", "xm y+14", "Open windows (checked = locked)")
    g.Add("Button", "x+8 yp w90", "Refresh").OnEvent("Click", (*) => RefreshUiList())

    ui.lv := g.Add("ListView", "xm y+6 w400 r14 Checked -Multi", ["Window", "App"])
    ui.lv.OnEvent("ItemCheck", OnWindowCheck)
    ui.lv.ModifyCol(1, 260)
    ui.lv.ModifyCol(2, 120)

    g.Add("Button", "xm y+10 w90", "Close").OnEvent("Click", (*) => g.Hide())
    g.OnEvent("Size", OnUiSize)

    ui.gui := g
}

OnUiSize(g, minMax, width, height) {
    global ui
    if (minMax = -1) || !ui.lv
        return
    ui.lv.Move(, , Max(200, width - 30), Max(100, height - 160))
}

OnRememberToggle(cb, *) {
    global settings, remembered, locked
    settings.remember := !!cb.Value
    if settings.remember {
        for hwnd, _ in locked {
            if WinExist("ahk_id " hwnd)
                remembered[WindowKey(hwnd)] := true
        }
        SaveSettings()
        SetTimer(ApplyRemembered, 2000)
        ApplyRemembered()
    } else {
        SetTimer(ApplyRemembered, 0)
        remembered := Map()
        SaveSettings()
    }
}

OnWindowCheck(lv, row, checked) {
    global hwndByRow, ui
    if ui.capturing
        return
    if !hwndByRow.Has(row)
        return
    hwnd := hwndByRow[row]
    if !WinExist("ahk_id " hwnd) {
        RefreshUiList()
        return
    }
    SetLockedState(hwnd, checked)
}

RefreshUiList() {
    global ui, locked, hwndByRow
    if !ui.gui || !ui.lv
        return
    lv := ui.lv
    lv.OnEvent("ItemCheck", OnWindowCheck, 0)
    lv.Delete()
    hwndByRow := Map()
    ownHwnd := ui.gui.Hwnd
    for hwnd in WinGetList() {
        hwnd := Integer(hwnd)
        if !IsLockable(hwnd)
            continue
        if ownHwnd && hwnd = ownHwnd
            continue
        title := TitleOf(hwnd)
        try
            exe := WinGetProcessName("ahk_id " hwnd)
        catch
            exe := ""
        row := lv.Add(locked.Has(hwnd) ? "Check" : "", title, exe)
        hwndByRow[row] := hwnd
    }
    lv.OnEvent("ItemCheck", OnWindowCheck)
}
