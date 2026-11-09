#!/usr/bin/env bash
#
# openevv-einstellungen.sh – kleiner grafischer Dialog (zenity) für die
# Einstellungen des OpenEVV-Moduls in Speech Dispatcher.
#
#   ./openevv-einstellungen.sh                 Dialog öffnen
#   ./openevv-einstellungen.sh --status        aktuelle Einstellungen anzeigen (ohne Dialog)
#   ./openevv-einstellungen.sh --wideband on   Breitband (22050 Hz) ein/aus (on|off), ohne Dialog
#   ./openevv-einstellungen.sh --debug off     Debug-Protokoll ein/aus (on|off), ohne Dialog
#   ./openevv-einstellungen.sh --conf PFAD     andere openevv.conf verwenden
#   ./openevv-einstellungen.sh --install-launcher   Eintrag im Anwendungsmenü anlegen
#
# Die Einstellungen stehen in ~/.config/speech-dispatcher/modules/openevv.conf.
# Das Modul liest sie nur beim Start; nach einer Änderung muss Speech
# Dispatcher neu gestartet werden (der Dialog bietet das an).

set -uo pipefail

CONF="$HOME/.config/speech-dispatcher/modules/openevv.conf"
SET_WIDEBAND=""; SET_DEBUG=""; STATUS=0; LAUNCHER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --conf) CONF="${2:?}"; shift 2 ;;
    --wideband) SET_WIDEBAND="${2:?}"; shift 2 ;;
    --debug) SET_DEBUG="${2:?}"; shift 2 ;;
    --status) STATUS=1; shift ;;
    --install-launcher) LAUNCHER=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

for v in "$SET_WIDEBAND" "$SET_DEBUG"; do
  [[ -z "$v" || "$v" == on || "$v" == off ]] || { echo "Wert muss on oder off sein." >&2; exit 2; }
done

TITLE="OpenEVV-Einstellungen"

# ---------------------------------------------------------------- Hilfsfunktionen
gui() { [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v zenity >/dev/null; }

say_error() {
  if gui; then zenity --error --title="$TITLE" --text="$1" --width=420 2>/dev/null
  else echo "Fehler: $1" >&2; fi
}

is_on() {   # is_on KEY  -> 0, wenn "KEY 1" aktiv (nicht auskommentiert)
  grep -qE "^[[:space:]]*$1[[:space:]]+1[[:space:]]*$" "$CONF" 2>/dev/null
}

set_flag() {   # set_flag KEY on|off
  local key="$1" want="$2"
  if [[ "$want" == on ]]; then
    if grep -qE "^[[:space:]]*$key\b" "$CONF"; then
      sed -i -E "s/^[[:space:]]*$key\b.*/$key 1/" "$CONF"
    elif grep -qE "^[[:space:]]*#[[:space:]]*$key 1[[:space:]]*$" "$CONF"; then
      sed -i -E "0,/^[[:space:]]*#[[:space:]]*$key 1[[:space:]]*$/s//$key 1/" "$CONF"
    else
      printf '%s 1\n' "$key" >> "$CONF"
    fi
  else
    sed -i -E "s/^[[:space:]]*$key\b.*/# $key 1/" "$CONF"
  fi
}

ensure_conf() {
  [[ -f "$CONF" ]] && return 0
  local modfound=0 d
  for d in "$HOME/.local/libexec/speech-dispatcher-modules" /usr/local/libexec/speech-dispatcher-modules \
           /usr/lib/speech-dispatcher-modules /usr/libexec/speech-dispatcher-modules \
           /usr/lib/*/speech-dispatcher-modules; do
    [[ -x "$d/sd_openevv" ]] && modfound=1
  done
  if [[ $modfound -eq 0 ]]; then
    say_error "Weder $CONF noch das Modul sd_openevv wurden gefunden. Ist OpenEVV installiert?"
    exit 1
  fi
  mkdir -p "$(dirname "$CONF")"
  printf '# OpenEVV – Einstellungen (angelegt von openevv-einstellungen.sh)\n#\n# Wideband 1\n' > "$CONF"
}

backup_once() { [[ -f "$CONF.bak" ]] || cp "$CONF" "$CONF.bak"; }

state() { is_on "$1" && echo "an" || echo "aus"; }

restart_daemon() {
  pkill -x -u "$(id -u)" speech-dispatcher 2>/dev/null || true
}

# ---------------------------------------------------------------- Launcher
if [[ $LAUNCHER -eq 1 ]]; then
  bindir="$HOME/.local/bin"; appdir="$HOME/.local/share/applications"
  mkdir -p "$bindir" "$appdir"
  install -m 0755 "$0" "$bindir/openevv-einstellungen"
  cat > "$appdir/openevv-einstellungen.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=OpenEVV-Einstellungen
Comment=Einstellungen des OpenEVV-Sprachmoduls
Exec=$bindir/openevv-einstellungen
Icon=preferences-desktop-accessibility
Terminal=false
Categories=Settings;Accessibility;
DESK
  echo "Angelegt: $bindir/openevv-einstellungen und $appdir/openevv-einstellungen.desktop"
  exit 0
fi

ensure_conf

# ---------------------------------------------------------------- ohne Dialog
if [[ $STATUS -eq 1 ]]; then
  echo "Konfiguration: $CONF"
  echo "Wideband (22050 Hz): $(state Wideband)"
  echo "Debug:               $(state Debug)"
  exit 0
fi

if [[ -n "$SET_WIDEBAND" || -n "$SET_DEBUG" ]]; then
  backup_once
  [[ -n "$SET_WIDEBAND" ]] && set_flag Wideband "$SET_WIDEBAND"
  [[ -n "$SET_DEBUG" ]]    && set_flag Debug "$SET_DEBUG"
  echo "Gespeichert. Damit es wirkt: Speech Dispatcher neu starten (killall speech-dispatcher)."
  exit 0
fi

# ---------------------------------------------------------------- Dialog
if ! gui; then
  echo "Kein grafischer Dialog möglich (kein Desktop oder zenity fehlt)." >&2
  echo "zenity installieren: sudo apt install zenity   – oder die Optionen --wideband/--debug nutzen (--help)." >&2
  exit 1
fi

w=FALSE; is_on Wideband && w=TRUE
d=FALSE; is_on Debug && d=TRUE

choice="$(zenity --list --checklist --title="$TITLE" --width=560 --height=300 \
  --text="Einstellungen für das OpenEVV-Sprachmodul.\nHäkchen setzen = aktiv." \
  --column="Aktiv" --column="Einstellung" --column="Beschreibung" \
  --print-column=2 --separator=" " \
  "$w" "Wideband" "Breitband-Stimme (22050 Hz statt 11025 Hz)" \
  "$d" "Debug"    "Fehlerprotokoll im Log (nur zur Fehlersuche)" 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || exit 0     # abgebrochen: nichts ändern

new_w=off; new_d=off
[[ " $choice " == *" Wideband "* ]] && new_w=on
[[ " $choice " == *" Debug "* ]] && new_d=on

changed=0
[[ "$new_w" != "$([[ $w == TRUE ]] && echo on || echo off)" ]] && changed=1
[[ "$new_d" != "$([[ $d == TRUE ]] && echo on || echo off)" ]] && changed=1

if [[ $changed -eq 0 ]]; then
  zenity --info --title="$TITLE" --text="Keine Änderung." --width=300 2>/dev/null
  exit 0
fi

backup_once
set_flag Wideband "$new_w"
set_flag Debug "$new_d"

if zenity --question --title="$TITLE" --width=480 \
  --ok-label="Jetzt neu starten" --cancel-label="Später" \
  --text="Gespeichert.\n\nDie Änderung gilt, sobald Speech Dispatcher neu gestartet wurde.\nDabei fällt die Sprachausgabe kurz weg. Falls Orca danach schweigt, Orca neu starten (orca --replace)." 2>/dev/null; then
  restart_daemon
fi
