# ScanSnap Home on Linux with Wine

This repository contains a script that installs **ScanSnap Home** (the Windows software for
PFU/Ricoh ScanSnap scanners) on Linux using Wine. It also applies all the tweaks that make
ScanSnap Home usable under Wine. This lets you scan on a Linux machine with ScanSnap Home,
including **searchable PDFs** (text recognition), automatic document detection and ScanSnap Home's
document management.

> Wine starts ScanSnap Home, but without tweaks it fails in many places: the installer rejects the
> Windows version, windows stay empty, the program components cannot talk to each other, text
> recognition crashes, and the scan window freezes after a scan.
> The script fixes all of this.

## What works and what doesn't

| | |
|---|---|
| ✅ Scanning via **Wi-Fi** | tested with ScanSnap iX1600 |
| ✅ Searchable PDFs (OCR) | |
| ✅ Document management, profiles, preview | |
| ✅ Several consecutive scans in the same scan window | |
| ❌ Scanning via **USB** | Wine cannot load the scanner's Windows USB driver |
| ⚠️ Online update of ScanSnap Home | do not use: an update overwrites the patched files (see [After an update](#after-an-update)) |
| ⚠️ Scanner firmware update, cloud services | not tested |

## Tested on

| Component | Version |
|---|---|
| Distribution | Linux Mint 22.2 "Zara" and Linux Mint 22.3 (based on Ubuntu 24.04), x86_64 |
| Desktop | Cinnamon 6.4.14, X11 session |
| Kernel | 7.0.0-34-generic |
| Wine | wine-9.0 (Ubuntu 9.0~repack-4build3), 64-bit prefix (`win64`) |
| winetricks | 20240105 |
| Python | 3.12.3 |
| ScanSnap Home | 4.0.0 (offline installer `WinSSHOfflineInstaller_4_0_0.exe`) |
| Scanner | ScanSnap iX1600, via Wi-Fi (hotspot of the Linux machine) |
| Hardware | Lenovo ThinkPad X1 Carbon, 7.6 GB RAM |

Other distributions, Wine versions, desktops (especially Wayland) and ScanSnap Home versions
are **not tested**. The tweaks are tailored to ScanSnap Home 4.0.0. With other versions,
individual steps may fail. The script then aborts with a message.

## Requirements

- An offline installer of ScanSnap Home for Windows, e.g. `WinSSHOfflineInstaller_4_0_0.exe`
  from the PFU/Ricoh download page. **The installer is not part of this repository.**
- Packages (Ubuntu / Linux Mint):

  ```sh
  sudo dpkg --add-architecture i386 && sudo apt update
  sudo apt install wine wine32 wine64 winetricks winbind cabextract curl unzip python3 wmctrl x11-utils fonts-dejavu-core
  ```

- Internet access during installation: winetricks downloads .NET 4.8 and fonts; the script
  additionally downloads the Visual C++ runtime from Microsoft and Mono.Cecil from NuGet.
- About **10 GB** of free disk space (the Wine prefix takes up around 8 GB afterwards) and at least
  **3 GB of free RAM**. Close large programs such as the browser and mail client before installing.
  On the test machine, the installer was aborted once due to lack of memory.
- An X11 session.

## Usage

```sh
git clone <this repository>
cd <repository>
./install-scansnap-home.sh /path/to/WinSSHOfflineInstaller_4_0_0.exe
```

By default, it installs into the Wine prefix `~/.wine`. To choose your own prefix, use
`--prefix ~/.wine-scansnap`.

The script works through the steps one after another. **In two places you have to click yourself:**

1. **Unpacking the installer:** The offline installer unpacks itself and starts the actual
   ScanSnap Home installer. If dialogs appear, click "Next". As soon as the inner installer is
   running, the script backs it up and closes everything again. A message saying "This product
   cannot be installed on the current version of Windows" is normal at this point.
2. **Installation:** The script starts the patched copy of the installer. Click through the wizard
   and choose **`C:\ScanSnapData` as the data storage folder**. On Linux this is
   `~/.wine/drive_c/ScanSnapData`, which is where your scans end up. At the end, ScanSnap Home
   starts the connection wizard. Cancel it and confirm in the terminal with Enter.

After that, the script applies the remaining tweaks without further input. Expect a good half hour
in total; .NET 4.8 alone takes several minutes.

You start ScanSnap Home afterwards via the start menu, the desktop shortcut, or
`~/.local/bin/scansnap-home`. Do not start it directly with `wine …PfuSshMain.exe`, otherwise the
window fixes of the launcher script are missing (see below).

### Connecting the scanner (Wi-Fi)

1. Connect the scanner to Wi-Fi via its display, to the same network as the Linux machine.
   It was tested with a Wi-Fi hotspot created by the Linux machine itself.
2. Set up the scanner in ScanSnap Home's connection wizard and choose the Wi-Fi connection there.

## What the script does

| Problem under Wine | Solution in the script |
|---|---|
| The installer reports "cannot be installed on the current version of Windows". The inner installer's manifest only lists Windows 7, so Windows reports version 6.2 to it. | Set the Windows version to Windows 11 and, in a copy of the inner installer, replace the Windows 7 ID in the manifest with the Windows 10 ID |
| The installer reports "No write permission for the data storage folder" because `GetShellWindow()` returns NULL under Wine. | Redirect the import in the installer copy to `GetFocus()`, provide `GetAppdata.exe` |
| ScanSnap Home needs .NET 4.7 or newer. | `winetricks dotnet48` |
| WPF windows stay empty or show artifacts (render thread crash `0x88980406`). | Disable WPF hardware acceleration (`Avalon.Graphics\DisableHWAcceleration`) |
| Boxes instead of characters: the app asks for "Meiryo UI", and `C:\windows\Fonts` is empty. | `winetricks corefonts tahoma`, DejaVu Sans, replace Meiryo → Arial |
| The program components talk via WCF named pipes with Windows authentication. Wine provides no credentials for this (SSPI `0x8009030e`). | Set `security mode="None"` in 13 `.config` files and switch the pipe bindings created in code in 7 assemblies the same way (`tools/PipePatch.cs`, using Mono.Cecil). Afterwards all methods are JIT-compiled as a test (`tools/JitCheck.cs`). |
| Image processing aborts with error −14, text recognition with "General protection fault in engine", error −6/−12 or "all pages empty". Wine's own `concrt140.dll` and `msvcp140.dll` lack functions. | Extract the current native Visual C++ 2015–2022 runtime (x86) directly from `vc_redist.x86.exe` into `syswow64` and set Wine to `native,builtin` |
| Empty windows ("ScanSnap Home", "Form1") appear at startup, one of them black and fullscreen, and cannot be closed. These are invisible helper forms of `SshRegister.exe`, `SshCloudMonitor.exe` and `PfuSsMon.exe`. | The `scansnap-home` launcher script hides them |
| The scan window freezes after the scan. ScanSnap Home minimizes it during the scan; Wine shows it again afterwards although it remains minimized as far as Windows is concerned. | The launcher script restores the window on the Windows side (`files/RestoreIfMinimized.cs`) |
| "Exit" in the tray icon menu does not respond. The menu opens with its bottom edge at the mouse pointer, so the last entry lies over the panel, which intercepts the clicks under Cinnamon. | Patch `SshTaskTray.exe` so that it moves the menu into the work area after opening (`tools/TrayMenuPatch.cs`, `files/TrayMenuFix.cs`) |
| With several monitors, the tray icon disappears, leaving behind a black, unclickable box. Wine 9.0 shifts docked tray icons by the offset of the virtual screen if the primary monitor is not at the far left, and does so again on every update of the icon (fixed in Wine 10). | The launcher script immediately moves the icon back to its place in the tray |
| The start menu shows the Wine icon instead of the ScanSnap icon. | Switch menu entries to the ScanSnap icon and the launcher script |

All modified program and configuration files are backed up beforehand as `*.orig` next to the
original. Wine's menu entries are backed up in `<prefix>/.scansnap-install/desktop-backup/`.

## After an update

An update of ScanSnap Home overwrites the patched files. The old errors then come back, for example
empty windows, no connection between the program components, or error −14.
The tweaks can be applied again without reinstalling:

```sh
rm -f "<prefix>/drive_c/Program Files (x86)/PFU/ScanSnap/Home/"*.orig   # only after an update!
./install-scansnap-home.sh --post-install-only
```

You only need to delete the `*.orig` files after an update, because otherwise the script patches
the old originals instead of the new files. Whether a newer ScanSnap Home version works with these
tweaks has not been tested.

## Files

| File | Purpose |
|---|---|
| `install-scansnap-home.sh` | Installation and patching script |
| `files/scansnap-home` | Launcher script (Python), installed to `~/.local/bin` |
| `files/RestoreIfMinimized.cs` | Helper program for the scan window, runs in Wine |
| `tools/PipePatch.cs` | Switches the WCF named pipe bindings created in code to `SecurityMode.None` |
| `files/TrayMenuFix.cs` | Keeps the tray menu above the panel, installed next to `SshTaskTray.exe` |
| `tools/TrayMenuPatch.cs` | Hooks `TrayMenuFix` into `SshTaskTray.exe` |
| `tools/JitCheck.cs` | Checks patched assemblies for invalid IL code |

The script compiles the C# sources inside Wine using the C# compiler that ships with
.NET Framework 4.8. Afterwards, the tools are located in `<prefix>/drive_c/scansnap-tools`.

## Uninstalling

The easiest way is to install into a separate prefix (`--prefix`) and delete it later together
with the launcher script:

```sh
rm -rf ~/.wine-scansnap ~/.local/bin/scansnap-home ~/.local/share/scansnap-home
rm -rf ~/.local/share/applications/wine/Programs/ScanSnap*
```

## Notes

- This project is not affiliated with PFU Limited or Ricoh. ScanSnap is a trademark of
  PFU Limited.
- The script only modifies your locally installed copy of ScanSnap Home. It contains and
  distributes no files from PFU. The license terms of ScanSnap Home apply to its use.
- The tweaks disable Windows authentication for the **local** named pipes between the program
  components. WCF named pipes are only reachable on your own machine. However, other programs
  of the same user could talk to the ScanSnap Home services.
- Use at your own risk.

## License

[MIT](LICENSE)
