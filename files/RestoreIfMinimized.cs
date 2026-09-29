// Restores a visible top-level window with the given title if it is minimized on the Windows (Wine) side.
// Prints "1" if a window was restored, else "0".
// Build: wine csc.exe /platform:x86 /out:RestoreIfMinimized.exe RestoreIfMinimized.cs
using System;
using System.Runtime.InteropServices;
using System.Text;

class RestoreIfMinimized
{
    const int SW_RESTORE = 9;

    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);

    static int Main(string[] args)
    {
        bool restored = false;
        EnumWindows((h, l) =>
        {
            var t = new StringBuilder(256);
            GetWindowText(h, t, 256);
            if (t.ToString() == args[0] && IsWindowVisible(h) && IsIconic(h))
            {
                ShowWindow(h, SW_RESTORE);
                restored = true;
            }
            return true;
        }, IntPtr.Zero);
        Console.Write(restored ? "1" : "0");
        return 0;
    }
}
