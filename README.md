# ScanSnap Home unter Linux mit Wine

Dieses Repository enthält ein Skript, das **ScanSnap Home** (die Windows-Software für Scanner der
Reihe ScanSnap von PFU/Ricoh) unter Linux mit Wine installiert. Es wendet außerdem alle Anpassungen
an, die ScanSnap Home unter Wine brauchbar machen. Damit kannst du auf einem Linux-Rechner mit
ScanSnap Home scannen, einschließlich **durchsuchbarer PDFs** (Texterkennung), automatischer
Dokumenterkennung und der Dokumentverwaltung von ScanSnap Home.

> Wine startet ScanSnap Home, aber ohne Anpassungen scheitert es an vielen Stellen: Der Installer
> lehnt die Windows-Version ab, die Fenster bleiben leer, die Programmteile können nicht miteinander
> sprechen, die Texterkennung stürzt ab, und das Scan-Fenster friert nach dem Scan ein.
> Das Skript behebt all das.

## Was funktioniert und was nicht

| | |
|---|---|
| ✅ Scannen per **WLAN** | getestet mit ScanSnap iX1600 |
| ✅ Durchsuchbare PDFs (OCR) | |
| ✅ Dokumentverwaltung, Profile, Vorschau | |
| ✅ Mehrere Scans hintereinander im selben Scan-Fenster | |
| ❌ Scannen per **USB** | Wine kann den Windows-USB-Treiber des Scanners nicht laden |
| ⚠️ Online-Update von ScanSnap Home | nicht verwenden: Ein Update überschreibt die angepassten Dateien (siehe [Nach einem Update](#nach-einem-update)) |
| ⚠️ Scanner-Firmware-Update, Cloud-Dienste | nicht getestet |

## Getestet unter

| Komponente | Version |
|---|---|
| Distribution | Linux Mint 22.2 „Zara“ (Basis Ubuntu 24.04), x86_64 |
| Desktop | Cinnamon 6.4.14, X11-Sitzung |
| Kernel | 7.0.0-34-generic |
| Wine | wine-9.0 (Ubuntu 9.0~repack-4build3), 64-Bit-Präfix (`win64`) |
| winetricks | 20240105 |
| Python | 3.12.3 |
| ScanSnap Home | 4.0.0 (Offline-Installer `WinSSHOfflineInstaller_4_0_0.exe`) |
| Scanner | ScanSnap iX1600, per WLAN (Hotspot des Linux-Rechners) |
| Hardware | Lenovo ThinkPad X1 Carbon, 7,6 GB RAM |

Andere Distributionen, Wine-Versionen, Desktops (vor allem Wayland) und ScanSnap-Home-Versionen
sind **nicht getestet**. Die Anpassungen sind auf ScanSnap Home 4.0.0 zugeschnitten. Bei anderen
Versionen können einzelne Schritte fehlschlagen. Das Skript bricht dann mit einer Meldung ab.

## Voraussetzungen

- Ein Offline-Installer von ScanSnap Home für Windows, z. B. `WinSSHOfflineInstaller_4_0_0.exe`
  von der Download-Seite von PFU/Ricoh. **Der Installer ist nicht Teil dieses Repositorys.**
- Pakete (Ubuntu / Linux Mint):

  ```sh
  sudo dpkg --add-architecture i386 && sudo apt update
  sudo apt install wine wine32 wine64 winetricks winbind cabextract curl unzip python3 wmctrl x11-utils fonts-dejavu-core
  ```

- Internetzugang während der Installation: winetricks lädt .NET 4.8 und Schriften herunter,
  das Skript zusätzlich die Visual-C++-Laufzeit von Microsoft und Mono.Cecil von NuGet.
- Etwa **10 GB** freier Speicherplatz (das Wine-Präfix belegt danach rund 8 GB) und mindestens
  **3 GB freier Arbeitsspeicher**. Schließ vor der Installation große Programme wie Browser und
  Mailprogramm. Auf dem Testrechner wurde der Installer einmal wegen Speichermangels abgebrochen.
- Eine X11-Sitzung.

## Benutzung

```sh
git clone <dieses Repository>
cd <Repository>
./install-scansnap-home.sh /pfad/zu/WinSSHOfflineInstaller_4_0_0.exe
```

Standardmäßig wird ins Wine-Präfix `~/.wine` installiert. Ein eigenes Präfix wählst du mit
`--prefix ~/.wine-scansnap`.

Das Skript arbeitet die Schritte nacheinander ab. **An zwei Stellen musst du selbst klicken:**

1. **Entpacken des Installers:** Der Offline-Installer entpackt sich und startet den eigentlichen
   ScanSnap-Home-Installer. Falls Dialoge erscheinen, klickst du auf „Weiter“. Sobald der innere
   Installer läuft, sichert das Skript ihn und beendet alles wieder. Eine Meldung „Dieses Produkt
   kann nicht in der aktuellen Version von Windows installiert werden“ ist dabei normal.
2. **Installation:** Das Skript startet die angepasste Kopie des Installers. Klick dich durch den
   Assistenten und wähl als **Datenspeicherordner `C:\ScanSnapData`**. Unter Linux ist das
   `~/.wine/drive_c/ScanSnapData`, dort landen deine Scans. Am Ende startet ScanSnap Home
   den Verbindungsassistenten. Brich ihn ab und bestätige im Terminal mit Enter.

Danach wendet das Skript die übrigen Anpassungen ohne weitere Eingaben an. Rechne insgesamt mit
einer guten halben Stunde, allein .NET 4.8 braucht einige Minuten.

ScanSnap Home startest du anschließend über das Startmenü, die Verknüpfung auf dem Schreibtisch oder
mit `~/.local/bin/scansnap-home`. Starte es nicht direkt mit `wine …PfuSshMain.exe`, sonst fehlen
die Fensterkorrekturen des Startskripts (siehe unten).

### Scanner verbinden (WLAN)

1. Bring den Scanner über sein Display ins WLAN, und zwar ins selbe Netz wie der Linux-Rechner.
   Getestet wurde mit einem WLAN-Hotspot, den der Linux-Rechner selbst aufgespannt hat.
2. Richte den Scanner im Verbindungsassistenten von ScanSnap Home ein und wähl dort die Verbindung
   per WLAN.

## Was das Skript macht

| Problem unter Wine | Lösung im Skript |
|---|---|
| Der Installer meldet „nicht in der aktuellen Version von Windows installierbar“. Das Manifest des inneren Installers nennt nur Windows 7, dadurch meldet Windows ihm Version 6.2. | Windows-Version auf Windows 11 stellen und im Manifest einer Kopie des inneren Installers die Windows-7-Kennung durch die Windows-10-Kennung ersetzen |
| Der Installer meldet „Keine Schreibrechte für den Datenspeicherordner“, weil `GetShellWindow()` unter Wine NULL liefert. | Import in der Installer-Kopie auf `GetFocus()` umbiegen, `GetAppdata.exe` bereitstellen |
| ScanSnap Home braucht .NET 4.7 oder neuer. | `winetricks dotnet48` |
| WPF-Fenster bleiben leer oder zeigen Artefakte (Render-Thread-Absturz `0x88980406`). | WPF-Hardwarebeschleunigung abschalten (`Avalon.Graphics\DisableHWAcceleration`) |
| Kästchen statt Zeichen: Die App verlangt „Meiryo UI“, und `C:\windows\Fonts` ist leer. | `winetricks corefonts tahoma`, DejaVu Sans, Ersatz Meiryo → Arial |
| Die Programmteile sprechen über WCF Named Pipes mit Windows-Anmeldung. Wine liefert dafür keine Anmeldedaten (SSPI `0x8009030e`). | In 13 `.config`-Dateien `security mode="None"` setzen und in 7 Assemblies die im Code erzeugten Pipe-Bindungen genauso umstellen (`tools/PipePatch.cs`, mit Mono.Cecil). Danach werden alle Methoden testweise JIT-übersetzt (`tools/JitCheck.cs`). |
| Bildverarbeitung bricht mit Fehler −14 ab, Texterkennung mit „Allgemeine Schutzverletzung in Engine“, Fehler −6/−12 oder „alle Seiten leer“. Wines eigene `concrt140.dll` und `msvcp140.dll` fehlen Funktionen. | Aktuelle native Visual-C++-2015–2022-Laufzeit (x86) direkt aus `vc_redist.x86.exe` nach `syswow64` entpacken und Wine auf `native,builtin` stellen |
| Leere Fenster („ScanSnap Home“, „Form1“) erscheinen beim Start, eines davon schwarz und bildschirmfüllend, und lassen sich nicht schließen. Das sind unsichtbare Hilfsformulare von `SshRegister.exe`, `SshCloudMonitor.exe` und `PfuSsMon.exe`. | Das Startskript `scansnap-home` blendet sie aus |
| Das Scan-Fenster friert nach dem Scan ein. ScanSnap Home minimiert es beim Scan, Wine zeigt es danach wieder an, obwohl es für Windows minimiert bleibt. | Das Startskript stellt das Fenster auf Windows-Seite wieder her (`files/RestoreIfMinimized.cs`) |
| »Beenden« im Menü des Tray-Symbols reagiert nicht. Das Menü öffnet sich mit der Unterkante am Mauszeiger, der unterste Eintrag liegt dadurch über der Leiste, und die fängt unter Cinnamon die Klicks ab. | `SshTaskTray.exe` so patchen, dass es das Menü nach dem Öffnen in die Arbeitsfläche verschiebt (`tools/TrayMenuPatch.cs`, `files/TrayMenuFix.cs`) |
| Bei mehreren Monitoren verschwindet das Tray-Symbol, zurück bleibt ein schwarzes, nicht klickbares Feld. Wine 9.0 verschiebt angedockte Tray-Symbole um den Versatz des virtuellen Bildschirms, wenn der Hauptmonitor nicht ganz links liegt, und zwar bei jeder Aktualisierung des Symbols erneut (in Wine 10 behoben). | Das Startskript schiebt das Symbol sofort an seinen Platz im Tray zurück |
| Das Startmenü zeigt das Wine-Symbol statt des ScanSnap-Symbols. | Menüeinträge auf das ScanSnap-Symbol und das Startskript umstellen |

Alle geänderten Programm- und Konfigurationsdateien werden vorher als `*.orig` neben dem Original
gesichert. Die Menüeinträge von Wine liegen gesichert in `<präfix>/.scansnap-install/desktop-backup/`.

## Nach einem Update

Ein Update von ScanSnap Home überschreibt die angepassten Dateien. Danach treten die alten Fehler
wieder auf, zum Beispiel leere Fenster, keine Verbindung zwischen den Programmteilen oder Fehler −14.
Die Anpassungen lassen sich ohne Neuinstallation erneut anwenden:

```sh
rm -f "<präfix>/drive_c/Program Files (x86)/PFU/ScanSnap/Home/"*.orig   # nur nach einem Update!
./install-scansnap-home.sh --post-install-only
```

Die `*.orig`-Dateien musst du nur nach einem Update löschen, weil das Skript sonst die alten
Originale statt der neuen Dateien patcht. Ob eine neuere ScanSnap-Home-Version mit diesen
Anpassungen funktioniert, ist nicht getestet.

## Dateien

| Datei | Zweck |
|---|---|
| `install-scansnap-home.sh` | Installations- und Anpassungsskript |
| `files/scansnap-home` | Startskript (Python), wird nach `~/.local/bin` installiert |
| `files/RestoreIfMinimized.cs` | Hilfsprogramm für das Scan-Fenster, läuft in Wine |
| `tools/PipePatch.cs` | Stellt die im Code erzeugten WCF-Named-Pipe-Bindungen auf `SecurityMode.None` um |
| `files/TrayMenuFix.cs` | Hält das Tray-Menü oberhalb der Leiste, wird neben `SshTaskTray.exe` installiert |
| `tools/TrayMenuPatch.cs` | Bindet `TrayMenuFix` in `SshTaskTray.exe` ein |
| `tools/JitCheck.cs` | Prüft gepatchte Assemblies auf ungültigen IL-Code |

Die C#-Quellen übersetzt das Skript mit dem C#-Compiler, der zu .NET Framework 4.8 gehört, innerhalb
von Wine. Die Werkzeuge liegen danach in `<präfix>/drive_c/scansnap-tools`.

## Deinstallieren

Am einfachsten installierst du in ein eigenes Präfix (`--prefix`) und löschst es später samt
Startskript:

```sh
rm -rf ~/.wine-scansnap ~/.local/bin/scansnap-home ~/.local/share/scansnap-home
rm -rf ~/.local/share/applications/wine/Programs/ScanSnap*
```

## Hinweise

- Dieses Projekt steht in keiner Verbindung zu PFU Limited oder Ricoh. ScanSnap ist eine Marke
  der PFU Limited.
- Das Skript verändert nur deine lokal installierte Kopie von ScanSnap Home. Es enthält und
  verbreitet keine Dateien von PFU. Für die Nutzung von ScanSnap Home gelten dessen Lizenzbedingungen.
- Die Anpassungen schalten die Windows-Authentifizierung der **lokalen** Named Pipes zwischen den
  Programmteilen ab. Named Pipes von WCF sind nur auf dem eigenen Rechner erreichbar. Andere
  Programme desselben Benutzers könnten aber mit den Diensten von ScanSnap Home sprechen.
- Benutzung auf eigene Gefahr.

## Lizenz

[MIT](LICENSE)
