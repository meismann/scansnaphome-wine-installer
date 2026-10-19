// Keeps the context menu of the ScanSnap Home tray icon (SshTaskTray.exe) inside the working area.
//
// WinForms opens the tray menu with its bottom edge at the mouse pointer, so on a bottom panel the
// lowest item ("Beenden"/"Exit") lies on top of the panel. Under Wine with Cinnamon the panel takes
// all clicks in its area, even where the menu is drawn above it, so that item cannot be clicked.
// tools/TrayMenuPatch.cs makes SshTaskTray.exe call Attach() for its menu; the menu is then moved
// into the working area (above the panel) as soon as it has opened.
//
// Build: csc /target:library /platform:x86 /r:System.Windows.Forms.dll /r:System.Drawing.dll
//            /out:TrayMenuFix.dll TrayMenuFix.cs
using System;
using System.Drawing;
using System.Windows.Forms;

public static class TrayMenuFix
{
    public static void Attach(ToolStripDropDown menu)
    {
        menu.Opened += KeepInWorkingArea;
    }

    static void KeepInWorkingArea(object sender, EventArgs e)
    {
        var menu = (ToolStripDropDown)sender;
        Rectangle area = Screen.FromRectangle(menu.Bounds).WorkingArea;
        int x = Math.Max(area.Left, Math.Min(menu.Left, area.Right - menu.Width));
        int y = Math.Max(area.Top, Math.Min(menu.Top, area.Bottom - menu.Height));
        if (x != menu.Left || y != menu.Top)
            menu.Location = new Point(x, y);
    }
}
