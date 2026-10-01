#!/usr/bin/env bash
# Installiert ScanSnap Home (Windows) unter Wine auf Linux und wendet alle Anpassungen an,
# die ScanSnap Home unter Wine lauffähig machen. Siehe README.md.
#
# Aufruf:
#   ./install-scansnap-home.sh [--prefix DIR] <WinSSHOfflineInstaller_x_y_z.exe>
#   ./install-scansnap-home.sh [--prefix DIR] --post-install-only
#
# --post-install-only wendet nur die Anpassungen nach der Installation erneut an
# (z. B. nachdem ein Update von ScanSnap Home Dateien überschrieben hat).
set -uo pipefail

REPO_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
WINEPREFIX=${WINEPREFIX:-$HOME/.wine}
POST_INSTALL_ONLY=0
INSTALLER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) WINEPREFIX=$2; shift 2 ;;
        --post-install-only) POST_INSTALL_ONLY=1; shift ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) INSTALLER=$1; shift ;;
    esac
done

export WINEPREFIX WINEARCH=win64 WINEDEBUG=-all

CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/scansnap-wine
STATE_DIR=$WINEPREFIX/.scansnap-install
DRIVE_C=$WINEPREFIX/drive_c
PFU_HOME="$DRIVE_C/Program Files (x86)/PFU/ScanSnap/Home"
SETUP_DIR=$DRIVE_C/scansnap-setup     # gepatchte Kopie des inneren Installers
TOOLS_DIR=$DRIVE_C/scansnap-tools     # kompilierte Hilfswerkzeuge (Mono.Cecil, PipePatch, JitCheck)
DATA_DIR=$DRIVE_C/ScanSnapData
CSC='C:\windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
HELPER_DIR=$HOME/.local/share/scansnap-home
LAUNCHER=$HOME/.local/bin/scansnap-home
CECIL_VERSION=0.11.5
VCREDIST_URL=https://aka.ms/vs/17/release/vc_redist.x86.exe
TESTED_INSTALLER=WinSSHOfflineInstaller_4_0_0.exe

# Visual-C++-Laufzeit: Wines eingebaute Versionen fehlen Funktionen, die ScanSnap Home braucht
# (concrt140: _Cancellation_beacon::_Confirm_cancel, msvcp140: std::_Throw_Cpp_error).
VC_DLLS="concrt140 msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids
vcruntime140 vcruntime140_threads vcomp140 mfc140 mfc140u"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mWarnung:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mFehler:\033[0m %s\n' "$*" >&2; exit 1; }
done_marker() { [ -f "$STATE_DIR/$1" ]; }
mark_done()   { mkdir -p "$STATE_DIR" && touch "$STATE_DIR/$1"; }
pause() { read -r -p "    $1 [Enter] " _ </dev/tty; }
winpath() { winepath -w "$1" 2>/dev/null; }
wine_reg_add() { wine reg add "$1" /v "$2" /t "$3" /d "$4" /f >/dev/null 2>&1 || die "Registry-Eintrag $1\\$2 fehlgeschlagen"; }
stop_wine() { wineserver -k 2>/dev/null; wineserver -w 2>/dev/null; true; }

# ---------------------------------------------------------------------------------------------
check_prerequisites() {
    log "Voraussetzungen prüfen"
    local missing=() cmd
    for cmd in wine wineserver winepath winetricks cabextract curl unzip python3 wmctrl xprop xwininfo ntlm_auth; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if command -v dpkg >/dev/null && ! dpkg -s wine32:i386 >/dev/null 2>&1; then
        warn "Das Paket wine32 (32-Bit-Wine) fehlt. ScanSnap Home ist ein 32-Bit-Programm."
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        warn "Es fehlen: ${missing[*]}"
        info "Unter Ubuntu/Linux Mint installierst du alles mit:"
        info "  sudo dpkg --add-architecture i386 && sudo apt update"
        info "  sudo apt install wine wine32 wine64 winetricks winbind cabextract curl unzip python3 wmctrl x11-utils fonts-dejavu-core"
        die "Bitte fehlende Pakete installieren und das Skript erneut starten."
    fi
    [ "${XDG_SESSION_TYPE:-x11}" = "x11" ] || warn "Getestet wurde nur unter X11 (Sitzung: $XDG_SESSION_TYPE)."
    local mem_kb
    mem_kb=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    [ "${mem_kb:-0}" -ge 3000000 ] || warn "Weniger als 3 GB RAM frei. Schließe am besten große Programme (Browser, Mail)."
    info "Wine-Präfix: $WINEPREFIX ($(wine --version))"
}

setup_prefix() {
    log "Wine-Präfix anlegen"
    if [ -f "$WINEPREFIX/system.reg" ]; then
        info "Präfix existiert bereits."
        grep -q '^#arch=win64' "$WINEPREFIX/system.reg" || die "$WINEPREFIX ist kein 64-Bit-Präfix. Nimm ein anderes (--prefix)."
    else
        wineboot --init >/dev/null 2>&1
        stop_wine
    fi
}

install_dotnet() {
    log ".NET Framework 4.8 installieren (dauert einige Minuten)"
    # Wine-Mono setzt denselben Registry-Schlüssel "Release" wie echtes .NET. Mono kann aber die
    # WCF-Named-Pipe-Konfiguration nicht auswerten (NotImplementedException in
    # NetNamedPipeBindingElement), deshalb gilt nur das echte .NET (clr.dll) als installiert.
    if [ -f "$DRIVE_C/windows/Microsoft.NET/Framework/v4.0.30319/clr.dll" ] \
        && wine reg query 'HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' /v Release 2>/dev/null | grep -qi 'Release'; then
        info "Bereits installiert."
    else
        winetricks -q dotnet48 || die "winetricks dotnet48 fehlgeschlagen."
    fi
    # winetricks stellt dabei Windows 7 ein; ScanSnap Home braucht Windows 10 oder neuer.
    wine winecfg /v win11 >/dev/null 2>&1
    stop_wine
}

install_fonts() {
    log "Schriften installieren"
    # Die App verlangt "Meiryo UI". WPF sucht nur in C:\windows\Fonts; ohne Schriften dort
    # erscheinen Kästchen statt Zeichen (z. B. statt "-").
    if [ -f "$DRIVE_C/windows/Fonts/arial.ttf" ] && [ -f "$DRIVE_C/windows/Fonts/tahoma.ttf" ]; then
        info "Core Fonts und Tahoma bereits vorhanden."
    else
        winetricks -q corefonts tahoma || die "winetricks corefonts tahoma fehlgeschlagen."
    fi
    local f
    for f in DejaVuSans.ttf DejaVuSans-Bold.ttf; do
        [ -f "/usr/share/fonts/truetype/dejavu/$f" ] && cp "/usr/share/fonts/truetype/dejavu/$f" "$DRIVE_C/windows/Fonts/"
    done
    wine_reg_add 'HKCU\Software\Wine\Fonts\Replacements' 'Meiryo UI' REG_SZ Arial
    wine_reg_add 'HKCU\Software\Wine\Fonts\Replacements' 'Meiryo' REG_SZ Arial
}

configure_wpf() {
    log "WPF auf Software-Rendering stellen"
    # Mit Hardware-Beschleunigung stürzt der WPF-Render-Thread ab (0x88980406), Fenster bleiben leer.
    wine_reg_add 'HKCU\Software\Microsoft\Avalon.Graphics' DisableHWAcceleration REG_DWORD 1
}

wine_temp_dir() {
    local t
    t=$(wine cmd /c echo %TEMP% 2>/dev/null | tr -d '\r')
    winepath -u "$t" 2>/dev/null
}

capture_inner_installer() {
    log "Inneren Installer aus $(basename "$INSTALLER") gewinnen"
    if [ -f "$SETUP_DIR/SSHDownloadInstaller.exe.orig" ]; then
        info "Bereits vorhanden: $SETUP_DIR"
        return
    fi
    [ "$(basename "$INSTALLER")" = "$TESTED_INSTALLER" ] || warn "Getestet wurde nur mit $TESTED_INSTALLER."
    local tmp inner
    tmp=$(wine_temp_dir)
    [ -n "$tmp" ] || die "Konnte das Wine-Temp-Verzeichnis nicht ermitteln."
    inner=$tmp/SSHomeDownloadInstaller
    stop_wine
    info "Der Installer entpackt sich jetzt (1,3 GB, dauert etwas)."
    info "Falls Dialoge erscheinen, klicke auf »Weiter«. Sobald der eigentliche ScanSnap-Home-Installer"
    info "gestartet ist, sichert dieses Skript ihn und beendet den Installer wieder. Eine Meldung"
    info "»Dieses Produkt kann nicht in der aktuellen Version von Windows installiert werden« ist dabei normal."
    (cd "$(dirname "$INSTALLER")" && wine "$(basename "$INSTALLER")" >/dev/null 2>&1 &)
    local waited=0
    until [ -f "$inner/download/WinSSHDownloadInstaller.xml" ] \
        && ps -eo args | grep -q '^C:.*SSHomeDownloadInstaller.SSHDownloadInstaller\.ex[e]'; do
        sleep 3; waited=$((waited + 3))
        [ $waited -lt 1800 ] || { stop_wine; die "Der innere Installer ist nach 30 Minuten nicht erschienen."; }
    done
    # warten, bis die großen Pakete fertig geschrieben sind
    local before after=-1
    until [ "${before:-}" = "$after" ]; do
        before=$after; sleep 5
        after=$(du -sb "$inner" | cut -f1)
    done
    rm -rf "$SETUP_DIR"
    cp -r "$inner" "$SETUP_DIR" || die "Kopieren von $inner fehlgeschlagen."
    stop_wine
    info "Gesichert nach $SETUP_DIR ($(du -sh "$SETUP_DIR" | cut -f1))."
    patch_inner_installer
}

patch_inner_installer() {
    log "Inneren Installer für Wine anpassen"
    local exe=$SETUP_DIR/SSHDownloadInstaller.exe
    [ -f "$exe.orig" ] || cp -p "$exe" "$exe.orig"
    # 1. Das Manifest nennt nur Windows 7 als unterstützt -> GetVersionEx liefert 6.2, die Prüfung
    #    "mindestens Windows 10" schlägt fehl. Windows-7-GUID durch die Windows-10-GUID ersetzen.
    # 2. Die Ordnerprüfung startet GetAppdata.exe über GetShellWindow(), das unter Wine NULL liefert
    #    ("Keine Schreibrechte für den Datenspeicherordner"). Import auf GetFocus umbiegen.
    python3 - "$exe.orig" "$exe" <<'EOF' || die "Patchen des inneren Installers fehlgeschlagen."
import sys
data = bytearray(open(sys.argv[1], 'rb').read())
patches = [
    (b'35138b9a-5d96-4fbd-8e2d-a2440225f93a', b'8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a'),
    (b'GetShellWindow\x00', b'GetFocus' + b'\x00' * 7),
]
for old, new in patches:
    assert len(old) == len(new)
    if data.count(old) != 1:
        sys.exit('Muster %r nicht genau einmal gefunden' % old)
    i = data.index(old)
    data[i:i + len(old)] = new
open(sys.argv[2], 'wb').write(data)
EOF
    mkdir -p "$DRIVE_C/ProgramData/ScanSnapHomeInstallerWork"
    cp "$SETUP_DIR/GetAppdata.exe" "$DRIVE_C/ProgramData/ScanSnapHomeInstallerWork/" \
        || die "GetAppdata.exe nicht gefunden."
    info "Manifest (Windows 10) und Ordnerprüfung (GetShellWindow -> GetFocus) gepatcht."
}

run_inner_installer() {
    log "ScanSnap Home installieren"
    if [ -f "$PFU_HOME/PfuSshMain.exe" ] && done_marker installed; then
        info "Bereits installiert."
        return
    fi
    mkdir -p "$DATA_DIR"
    stop_wine
    info "Der Installationsassistent öffnet sich jetzt. Bitte durchklicken."
    info "WICHTIG: Beim Datenspeicherordner  C:\\ScanSnapData  wählen."
    info "Am Ende startet ScanSnap Home mit dem Verbindungsassistenten. Den kannst du abbrechen;"
    info "verbunden wird nach dem Ende dieses Skripts (per WLAN, siehe README)."
    (cd "$SETUP_DIR" && wine SSHDownloadInstaller.exe >/dev/null 2>&1 &)
    sleep 10
    while ps -eo args | grep -q '^C:.*SSHDownloadInstaller\.ex[e]'; do sleep 5; done
    pause "Wenn die Installation abgeschlossen ist (oder ScanSnap Home schon läuft), weiter mit"
    [ -f "$PFU_HOME/PfuSshMain.exe" ] || die "ScanSnap Home wurde nicht installiert ($PFU_HOME fehlt)."
    stop_wine
    mark_done installed
}

# --------------------------- Anpassungen nach der Installation -------------------------------
install_vc_runtime() {
    log "Native Visual-C++-Laufzeit (x86) installieren"
    # vc_redist selbst bricht unter Wine ab ("newer version is installed"), weil ScanSnap Home eine
    # ältere Version (2017) registriert hat. Deshalb die DLLs direkt aus dem Paket entpacken.
    mkdir -p "$CACHE_DIR"
    local redist=$CACHE_DIR/vc_redist.x86.exe work
    [ -s "$redist" ] || curl -fsSL -o "$redist" "$VCREDIST_URL" || die "Download von $VCREDIST_URL fehlgeschlagen."
    work=$(mktemp -d)
    cabextract -q -d "$work/outer" "$redist" >/dev/null || die "Entpacken von vc_redist fehlgeschlagen."
    local cab dll n=0
    for cab in "$work"/outer/*; do cabextract -q -d "$work/inner" "$cab" >/dev/null 2>&1; done
    for dll in $VC_DLLS; do
        if [ -f "$work/inner/$dll.dll_x86" ]; then
            cp "$work/inner/$dll.dll_x86" "$DRIVE_C/windows/syswow64/$dll.dll"
            n=$((n + 1))
        fi
        wine_reg_add 'HKCU\Software\Wine\DllOverrides' "$dll" REG_SZ native,builtin
    done
    wine_reg_add 'HKCU\Software\Wine\DllOverrides' vcruntime140_1 REG_SZ native,builtin
    rm -rf "$work"
    [ $n -ge 8 ] || die "Nur $n Laufzeit-DLLs gefunden."
    info "$n DLLs nach syswow64 kopiert, Wine nutzt die nativen Versionen."
}

patch_pipe_configs() {
    log "WCF-Pipes in den .config-Dateien auf security mode=\"None\" stellen"
    # Wine kann keine Windows-Anmeldedaten für die Named Pipes liefern (SSPI 0x8009030e).
    python3 - "$PFU_HOME" <<'EOF' || die "Anpassen der .config-Dateien fehlgeschlagen."
import glob, os, re, shutil, sys

SEC = '<security mode="None" />'

def fix_section(sec):
    sec = re.sub(r'<binding\b([^>]*?)\s*/>', lambda m: '<binding%s>%s</binding>' % (m.group(1), SEC), sec)
    def open_binding(m):
        return m.group(0) if '<security' in m.group(2) else '<binding%s>%s%s</binding>' % (m.group(1), SEC, m.group(2))
    sec = re.sub(r'<binding\b([^>]*[^/])>(.*?)</binding>', open_binding, sec, flags=re.S)
    if not re.search(r'<binding>\s*<security', sec):  # default for endpoints without bindingConfiguration
        sec = sec.replace('</netNamedPipeBinding>', '<binding>%s</binding></netNamedPipeBinding>' % SEC)
    return sec

count = 0
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.config'))):
    if '<netNamedPipeBinding>' not in open(f, encoding='utf-8-sig', errors='replace').read():
        continue
    if not os.path.exists(f + '.orig'):
        shutil.copy2(f, f + '.orig')
    src = open(f + '.orig', encoding='utf-8-sig').read()
    out = re.sub(r'<netNamedPipeBinding>.*?</netNamedPipeBinding>', lambda m: fix_section(m.group(0)), src, flags=re.S)
    import xml.dom.minidom
    xml.dom.minidom.parseString(out.encode('utf-8'))  # must stay valid XML
    open(f, 'w', encoding='utf-8').write(out)
    count += 1
print('    %d .config-Dateien angepasst' % count)
EOF
}

build_tools() {
    log "Hilfswerkzeuge bauen (Mono.Cecil, PipePatch, JitCheck, RestoreIfMinimized)"
    mkdir -p "$TOOLS_DIR" "$CACHE_DIR"
    local nupkg=$CACHE_DIR/mono.cecil.$CECIL_VERSION.nupkg
    [ -s "$nupkg" ] || curl -fsSL -o "$nupkg" "https://www.nuget.org/api/v2/package/Mono.Cecil/$CECIL_VERSION" \
        || die "Download von Mono.Cecil fehlgeschlagen."
    unzip -oqj "$nupkg" 'lib/net40/Mono.Cecil.dll' 'lib/net40/Mono.Cecil.Rocks.dll' -d "$TOOLS_DIR" \
        || die "Entpacken von Mono.Cecil fehlgeschlagen."
    cp "$REPO_DIR/tools/PipePatch.cs" "$REPO_DIR/tools/JitCheck.cs" "$REPO_DIR/files/RestoreIfMinimized.cs" "$TOOLS_DIR/"
    (
        cd "$TOOLS_DIR" || exit 1
        wine "$CSC" /nologo /r:Mono.Cecil.dll /r:Mono.Cecil.Rocks.dll /out:PipePatch.exe PipePatch.cs &&
        wine "$CSC" /nologo /platform:x86 /out:JitCheck.exe JitCheck.cs &&
        wine "$CSC" /nologo /platform:x86 /out:RestoreIfMinimized.exe RestoreIfMinimized.cs
    ) >/dev/null || die "Kompilieren der Hilfswerkzeuge fehlgeschlagen."
    info "Werkzeuge liegen in $TOOLS_DIR"
}

is_il_only() {
    python3 - "$1" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
try:
    pe = struct.unpack_from('<I', d, 0x3c)[0]; opt = pe + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    rva = struct.unpack_from('<I', d, opt + (96 if magic == 0x10b else 112) + 14 * 8)[0]
    nsec = struct.unpack_from('<H', d, pe + 6)[0]; osz = struct.unpack_from('<H', d, pe + 20)[0]
    for i in range(nsec):
        _, vs, va, rs, rp = struct.unpack_from('<8sIIII', d, opt + osz + i * 40)
        if rva and va <= rva < va + max(vs, rs):
            sys.exit(0 if struct.unpack_from('<I', d, rva - va + rp + 16)[0] & 1 else 1)
except struct.error:
    pass
sys.exit(1)
EOF
}

patch_pipe_assemblies() {
    log "Im Code erzeugte WCF-Pipes auf security mode None patchen"
    local out=$TOOLS_DIR/out f patched=()
    mkdir -p "$out"
    cd "$PFU_HOME" || die "$PFU_HOME fehlt."
    for f in *.dll *.exe; do
        [ -f "$f.orig" ] || { grep -q -a 'NetNamedPipeBinding' "$f" && is_il_only "$f"; } || continue
        [ -f "$f.orig" ] || cp -p "$f" "$f.orig"
        rm -f "$out/$f"
        wine "$TOOLS_DIR/PipePatch.exe" patch "$(winpath "$PFU_HOME/$f.orig")" "$(winpath "$out/$f")" >/dev/null 2>&1
        case $? in
            0) [ -s "$out/$f" ] || die "PipePatch hat für $f keine Datei erzeugt."
               cp "$out/$f" "$f"; patched+=("$f") ;;
            1) rm -f "$f.orig" ;;   # nichts zu patchen (Bindung schon mit explizitem Modus)
            *) die "PipePatch ist bei $f fehlgeschlagen." ;;
        esac
    done
    [ ${#patched[@]} -gt 0 ] || die "Keine Assembly gepatcht - unerwartet für ScanSnap Home 4.0."
    info "Gepatcht: ${patched[*]}"
    cp "$TOOLS_DIR/JitCheck.exe" "$PFU_HOME/zz_JitCheck.exe"
    local result
    result=$(wine zz_JitCheck.exe "${patched[@]}" 2>&1 | tr -d '\r')
    rm -f "$PFU_HOME/zz_JitCheck.exe"
    info "JIT-Prüfung: $(echo "$result" | tail -1)"
    echo "$result" | grep -q 'invalid 0$' || die "Gepatchte Assemblies enthalten ungültigen Code:
$result"
    cd - >/dev/null || true
}

install_launcher() {
    log "Startskript und Menüeinträge einrichten"
    mkdir -p "$(dirname "$LAUNCHER")" "$HELPER_DIR"
    sed "s|@WINEPREFIX@|$WINEPREFIX|" "$REPO_DIR/files/scansnap-home" > "$LAUNCHER"
    chmod +x "$LAUNCHER"
    cp "$TOOLS_DIR/RestoreIfMinimized.exe" "$REPO_DIR/files/RestoreIfMinimized.cs" "$HELPER_DIR/"
    info "Startskript: $LAUNCHER"

    # Menüeinträge von Wine auf das Startskript umstellen. Das Symbol der Desktop-Verknüpfung
    # ist das echte ScanSnap-Symbol; der Startmenüeintrag bekommt von Wine oft das Wine-Glas.
    local desktop_dir icon="" f backup=$STATE_DIR/desktop-backup
    desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    mkdir -p "$backup"
    while IFS= read -r -d '' f; do
        grep -q 'Public.*Desktop.*ScanSnap' "$f" && icon=$(sed -n 's/^Icon=//p' "$f")
    done < <(grep -lZ 'ScanSnap\\\\* Home\.lnk' "$desktop_dir"/*.desktop 2>/dev/null)
    while IFS= read -r -d '' f; do
        local saved
        saved="$backup/$(basename "$(dirname "$f")")-$(basename "$f")"
        [ -f "$saved" ] || cp -p "$f" "$saved"
        sed -i "s|^Exec=.*|Exec=$LAUNCHER|" "$f"
        [ -n "$icon" ] && sed -i "s|^Icon=.*|Icon=$icon|" "$f"
        info "Angepasst: $f"
    done < <(grep -lZ -e 'ScanSnap\\\\* Home\.lnk' -e "Exec=$LAUNCHER" \
        "$HOME/.local/share/applications/wine/Programs/ScanSnap/"*.desktop "$desktop_dir"/*.desktop 2>/dev/null)
    command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
    true
}

# ---------------------------------------------------------------------------------------------
main() {
    check_prerequisites
    if [ $POST_INSTALL_ONLY -eq 0 ]; then
        [ -n "$INSTALLER" ] || die "Bitte die Installationsdatei angeben, z. B. $TESTED_INSTALLER (siehe --help)."
        [ -f "$INSTALLER" ] || die "Datei nicht gefunden: $INSTALLER"
        INSTALLER=$(readlink -f "$INSTALLER")
        setup_prefix
        install_dotnet
        install_fonts
        configure_wpf
        capture_inner_installer
        run_inner_installer
    else
        [ -f "$PFU_HOME/PfuSshMain.exe" ] || die "ScanSnap Home ist in $WINEPREFIX nicht installiert."
    fi
    stop_wine
    install_vc_runtime
    patch_pipe_configs
    build_tools
    patch_pipe_assemblies
    install_launcher
    stop_wine

    log "Fertig"
    info "Starte ScanSnap Home über das Startmenü oder mit:  $LAUNCHER"
    info "Den Scanner verbindest du per WLAN (USB funktioniert unter Wine nicht), siehe README.md."
    info "Den Ordner $SETUP_DIR (~1,3 GB) brauchst du nur für eine Neuinstallation."
}

main
