#!/bin/sh
# install.sh — installa pi-configurator su macOS / Linux.
#
# Pensato per essere eseguito direttamente dalla rete:
#
#   curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.sh | sh
#
# Con un ref pinnato (tag o commit), che e' cio' che rende l'installazione
# riproducibile e l'URL immutabile:
#
#   curl -fsSL .../main/install.sh | sh -s -- --ref v0.2.0
#
# Installando e configurando un provider nella stessa invocazione:
#
#   curl -fsSL .../main/install.sh | sh -s -- --ref v0.2.0 -- \
#       --endpoint https://api.server.example --api anthropic \
#       --model MLR-3 --key-env MLR_API_KEY
#
# Tutto cio' che segue `--` viene passato a pi-conf.sh.
#
# Lo script e' POSIX sh puro e non legge MAI da stdin: quando viene eseguito
# tramite pipe, stdin contiene il suo stesso testo.

set -eu

OWNER="ALF-Robotics"
REPO="pi-configurator"

# --- impostazioni -----------------------------------------------------------

REF="${PI_CONF_REF:-main}"
PREFIX="${PI_CONF_PREFIX:-$HOME/.local/bin}"
VERIFY=true
DRY_RUN=false
PASSTHROUGH=""

# shellcheck disable=SC3043
die() { printf '%s: %s\n' "install.sh" "$1" >&2; exit "${2:-1}"; }
info() { printf '  %s\n' "$1"; }
step() { printf '\n==> %s\n' "$1"; }

usage() {
    # stampa il blocco di commento in testa, fino alla prima riga vuota
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Opzioni:
  --ref <tag|commit>   versione da installare (default: main, che NON e' pinnata)
  --prefix <dir>       dove installare (default: $HOME/.local/bin)
  --no-verify          salta il controllo sha256 (sconsigliato)
  --dry-run            mostra cosa farebbe senza scrivere
  -h, --help           questo messaggio
  -- <args...>         argomenti passati a pi-conf.sh
EOF
}

# --- argomenti --------------------------------------------------------------

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)     [ $# -ge 2 ] || die "--ref richiede un valore"; REF="$2"; shift 2 ;;
        --ref=*)   REF="${1#*=}"; shift ;;
        --prefix)  [ $# -ge 2 ] || die "--prefix richiede un valore"; PREFIX="$2"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        --no-verify) VERIFY=false; shift ;;
        --dry-run)  DRY_RUN=true; shift ;;
        -h|--help)  usage; exit 0 ;;
        --)         shift; PASSTHROUGH="$*"; break ;;
        *)          die "argomento sconosciuto: $1" ;;
    esac
done

RAW="https://raw.githubusercontent.com/${OWNER}/${REPO}/${REF}"
BASE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# se lo script gira da un checkout locale si puo' installare senza rete
LOCAL=false
if [ -f "./pi-conf.sh" ] && [ -f "./install.sh" ]; then LOCAL=true; fi

# --- strumenti --------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

fetch() {  # fetch <url> <dest>
    if have curl; then curl -fsSL "$1" -o "$2"
    elif have wget; then wget -qO "$2" "$1"
    else die "serve curl oppure wget"
    fi
}

sha256() {  # sha256 <file> -> stampa l'hash
    if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
    elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
    elif have openssl; then openssl dgst -sha256 "$1" | sed 's/.*= *//'
    else printf ''
    fi
}

# --- pianificazione ---------------------------------------------------------

step "pi-configurator — installazione"

info "ref:     $REF$( [ "$REF" = "main" ] && printf '  (NON pinnata)' || printf '  (pinnata)' )"
info "prefix:  $PREFIX"
info "sorgente: $( [ "$LOCAL" = true ] && printf 'checkout locale' || printf "$RAW" )"

if [ "$REF" = "main" ]; then
    cat <<'EOF'

  ATTENZIONE: stai installando da "main", che puo' cambiare in qualsiasi
  momento. Per un'installazione riproducibile usa un tag:
      ... | sh -s -- --ref v0.2.0
EOF
fi

# controlla i prerequisiti che serviranno dopo
if [ -z "$PASSTHROUGH" ] || printf '%s' "$PASSTHROUGH" | grep -q -- '--key-env'; then
    :
fi

# --- download ---------------------------------------------------------------

TMPDIR_PC="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR_PC"; }
trap cleanup EXIT INT TERM

FILES="pi-conf.sh pi-conf.ps1"

if [ "$LOCAL" = true ]; then
    step "Copia dal checkout locale"
    for f in $FILES; do
        [ -f "./$f" ] || die "manca $f nel checkout"
        cp "./$f" "$TMPDIR_PC/$f"
    done
else
    step "Download"
    for f in $FILES; do
        info "$RAW/$f"
        fetch "$RAW/$f" "$TMPDIR_PC/$f" || die "download fallito: $f"
    done
fi

# --- verifica integrita' ----------------------------------------------------

# La verifica gira ogni volta che SHA256SUMS e' raggiungibile: sia scaricandolo
# dalla rete sia leggendolo da un checkout locale. In un checkout e' anche il
# modo in cui la suite puo' testare il rifiuto di un file alterato.
SUMS=""
if [ "$LOCAL" = true ] && [ -f "./SHA256SUMS" ]; then
    SUMS="./SHA256SUMS"
elif [ "$LOCAL" = false ]; then
    fetch "$RAW/SHA256SUMS" "$TMPDIR_PC/SHA256SUMS" 2>/dev/null && SUMS="$TMPDIR_PC/SHA256SUMS" || true
fi

if [ "$VERIFY" = true ] && [ -n "$SUMS" ]; then
    step "Verifica sha256"
    for f in $FILES; do
        want="$(awk -v n="$f" '$2 == n || $2 == "*"n {print $1}' "$SUMS" | head -1)"
        if [ -z "$want" ]; then
            info "$f: nessun hash in SHA256SUMS, salto"
            continue
        fi
        got="$(sha256 "$TMPDIR_PC/$f")"
        if [ -z "$got" ]; then
            info "$f: nessuno strumento sha256 disponibile, verifica impossibile"
        elif [ "$want" = "$got" ]; then
            info "$f  OK"
        else
            die "checksum non corrispondente per $f
  atteso:  $want
  ottenuto: $got
  Il file scaricato e' diverso da quello dichiarato. Non proseguo."
        fi
    done
elif [ "$VERIFY" = true ]; then
    info "SHA256SUMS non disponibile: la verifica non verra' eseguita"
fi

# --- permessi ---------------------------------------------------------------

chmod 755 "$TMPDIR_PC/pi-conf.sh" 2>/dev/null || true

# --- installazione ----------------------------------------------------------

if [ "$DRY_RUN" = true ]; then
    step "Dry run: nessuna scrittura"
    info "verrebbe installato: $PREFIX/pi-conf.sh, $PREFIX/pi-conf.ps1"
    [ -n "$PASSTHROUGH" ] && info "poi: pi-conf.sh add $PASSTHROUGH"
    exit 0
fi

step "Installazione in $PREFIX"
mkdir -p "$PREFIX" || die "impossibile creare $PREFIX"
cp "$TMPDIR_PC/pi-conf.sh" "$PREFIX/pi-conf.sh" || die "installazione fallita"
cp "$TMPDIR_PC/pi-conf.ps1" "$PREFIX/pi-conf.ps1" || die "installazione fallita"
chmod 755 "$PREFIX/pi-conf.sh"
info "pi-conf.sh"
info "pi-conf.ps1"

# shellcheck disable=SC3043
case ":$PATH:" in
    *":$PREFIX:"*) : ;;
    *) cat <<EOF

  $PREFIX non e' nel PATH. Aggiungilo al tuo ~/.zshrc o ~/.bashrc:
      export PATH="$PREFIX:\$PATH"
EOF
    ;;
esac

# --- configurazione opzionale ----------------------------------------------

if [ -n "$PASSTHROUGH" ]; then
    step "Configurazione del provider"
    # shellcheck disable=SC2086
    "$PREFIX/pi-conf.sh" $PASSTHROUGH
fi

step "Fatto"
cat <<EOF
  Verifica con:
      $PREFIX/pi-conf.sh --help

  Crea un profilo in modo interattivo:
      $PREFIX/pi-conf.sh

  Oppure senza domande:
      $PREFIX/pi-conf.sh add --endpoint https://api.server.example \\
          --api anthropic --model MLR-3 --key-env MLR_API_KEY
EOF
