# Window Resize Lock

Stops selected windows from being resized. Edge-dragging and the maximize button no longer change the size. The border usually stays.

Requires [AutoHotkey v2](https://www.autohotkey.com/). Run `WindowResizeLock.ahk`.

![Window Resize Lock](docs/screenshot.png)

## Features

- **Lock or unlock windows.** Check a window in the list, or press the shortcut (Win+Shift+L by default) to toggle the active window. A check applies to that window’s program and title, so other windows from the same program stay as they are.
- **Freeze a window's position.** Select a row and click **Freeze position**. If Windows moves the window after a desktop work-area change, its original position is restored. Restore a minimized or maximized window before freezing it. Position freezes last only until the script exits.
- **Change the shortcut.** Click **Change…** and press the keys you want.
- **Turn the shortcut off.** Uncheck **Enable keyboard shortcut**. The chosen shortcut is kept for when you turn it back on.
- **Remember locks.** Check **Remember locked windows** and the same windows are locked again the next time they are open.
- **Start in the tray.** Check **Start hidden in the tray** to skip the window on launch. Click the tray icon to open it.
- **Quit.** **Quit** (or Exit on the tray menu) restores every resize lock and stops position freezes. **Close** only hides the window.

Settings are saved next to the script in `WindowResizeLock.ini`.

## Use Cases

I like to cordon off sections of my screen real estate using tools like [DesktopCoral](https://www.donationcoder.com/programs/mouser/other-windows-apps/desktopcoral/). Dragging normal app windows over into the DesktopCoral area usually causes the app window to want to resize. This AutoHotkey script prevents that for windows you select, resulting in much easier window management. Freeze position also keeps selected windows in place when DesktopCoral or OneNote's Dock to Desktop changes the desktop work area.

## Limitations

The script removes the sizing border (`WS_THICKFRAME`) and the maximize box (`WS_MAXIMIZEBOX`), then puts them back if the app resets them. Some apps draw their own frame and ignore this, including many Electron, game, and WinUI windows.

Two windows that share both the same program and the exact same title are treated as one.
