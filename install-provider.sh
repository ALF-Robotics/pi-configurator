#!/bin/sh
# install-provider.sh - installa pi-configurator E configura un provider,
# con una sola invocazione e senza separatori da ricordare.
#
# Questo e' il punto d'ingresso per il provisioning: i parametri del provider
# sono flag di primo livello, quindi non serve il separatore `--` che
# install.sh usa per passare argomenti a pi-conf.sh.
#
#   curl -fsSL https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.sh \
#     | sh -s -- \
#         --endpoint https://api.server.example \
#         --api anthropic \
#         --model MLR-3 \
#         --key-env MLR_API_KEY
#
# Con un ref pinnato, che rende l'installazione riproducibile:
#
#   curl -fsSL .../main/install-provider.sh | sh -s -- --ref v0.2.0 --endpoint ... --model ...
#
# Se vuoi installare il tool e poi usarlo a mano, usa install.sh: questo script
# nasconde i parametri del provider dietro i flag che capisce lui.
#
# Come install.sh: POSIX sh puro e non legge MAI da stdin, perche' quando viene
# eseguito tramite pipe stdin contiene il suo stesso testo.
#
# L'installazione e' delegata a install.sh allo stesso ref, cosi' la logica di
# download e di verifica SHA256 esiste in un solo posto. Prima di eseguirlo
# questo script ne verifica comunque l'hash: un installer delegato e' codice che
# si sta per eseguire.

set -eu

OWNER="ALF-Robotics"
REPO="pi-configurator"

REF="${PI_CONF_REF:-main}"
PREFIX="${PI_CONF_PREFIX:-$HOME/.local/bin}"
VERIFY=true
DRY_RUN=false
PROVIDER_ARGS=""

die() { printf '%s: %s\n' "install-provider.sh" "$1" >&2; exit "${2:-1}"; }
info() { printf '  %s\n' "$1"; }
step() { printf '\n==> %s\n' "$1"; }

# Flag dell'installer. Tutto il resto va a pi-conf.sh add.
INSTALLER_FLAGS="--ref --prefix --no-verify --dry-run"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Flag dell'installer:
  --ref <tag|commit>   versione da installare (default: main, che NON e' pinnata)
  --prefix <dir>       dove installare (default: $HOME/.local/bin)
  --no-verify          salta il controllo sha256 (sconsigliato)
  --dry-run            mostra cosa farebbe senza scrivere
  -h, --help           questo messaggio

Flag del provider (passati a pi-conf.sh add):
  --endpoint <url>     obbligatorio
  --api <nome>         anthropic|openai|responses|google|mistral|bedrock|vertex|
                       codex|azure|<raw>                (default: anthropic)
  --model <id>         obbligatorio
  --profile <nome>     default: model id sanitizzato
  --key <valore>       chiave in chiaro (sconsigliato)
  --key-env <NOME>     scrive "apiKey": "$NOME": la chiave non finisce su disco
  --reasoning          default
  --no-reasoning       disattiva il reasoning
  --context <n>        default: 512000
  --max-tokens <n>     default: 32768
  --from-file <json>   valori mancanti da un JSON
  --config <path>      models.json da scrivere
  --yes                non chiedere conferma
EOF
}

# --- argomenti: si separa cio' che e' dell'installer dal resto ---------------

while [ $# -gt 0 ]; do
    case "$1" in
        --ref)       [ $# -ge 2 ] || die "--ref richiede un valore"; REF="$2"; shift 2 ;;
        --ref=*)     REF="${1#*=}"; shift ;;
        --prefix)    [ $# -ge 2 ] || die "--prefix richiede un valore"; PREFIX="$2"; shift 2 ;;
        --prefix=*)  PREFIX="${1#*=}"; shift ;;
        --no-verify) VERIFY=false; shift ;;
        --dry-run)   DRY_RUN=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           PROVIDER_ARGS="$PROVIDER_ARGS $1"; shift ;;
    esac
done
PROVIDER_ARGS="${PROVIDER_ARGS# }"

if [ -z "$PROVIDER_ARGS" ]; then
    usage >&2
    die "nessun parametro del provider: specifica almeno --endpoint e --model"
fi

# --endpoint e --model sono obbligatori: controllarlo qui evita di installare
# il tool e poi fallire sul colpo successivo.
has_flag() {
    for a in $PROVIDER_ARGS; do
        [ "$a" = "$1" ] && return 0
        case "$a" in "$1="*) return 0 ;; esac
    done
    return 1
}
has_flag --endpoint || die "manca --endpoint (obbligatorio)"
has_flag --model    || die "manca --model (obbligatorio)"

RAW="https://raw.githubusercontent.com/${OWNER}/${REPO}/${REF}"

# --- recupero e verifica di install.sh, l'installer che stiamo per eseguire --

have() { command -v "$1" >/dev/null 2>&1; }
fetch() {
    if have curl; then curl -fsSL "$1" -o "$2"
    elif have wget; then wget -qO "$2" "$1"
    else die "serve curl oppure wget"
    fi
}
sha256() {
    if have sha256sum; then sha256sum "$1" | cut -d' ' -f1
    elif have shasum; then shasum -a 256 "$1" | cut -d' ' -f1
    elif have openssl; then openssl dgst -sha256 "$1" | sed 's/.*= *//'
    else printf ''
    fi
}

TMPD="$(mktemp -d)"
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT INT TERM

step 'pi-configurator — installazione e configurazione'
info "ref:     $REF$( [ "$REF" = "main" ] && printf '  (NON pinnata)' || printf '  (pinnata)' )"
info "prefix:  $PREFIX"
info "provider:$PROVIDER_ARGS"

if [ "$REF" = "main" ]; then
    cat <<'EOF'

  ATTENZIONE: stai installando da "main", che puo' cambiare in qualsiasi
  momento. Usa un tag per un'installazione riproducibile:
      ... | sh -s -- --ref v0.2.0 --endpoint ... --model ...
EOF
fi

# se siamo in un checkout locale, install.sh e' gia' qui
DELEGATE="$TMPD/install.sh"
if [ -f "./install.sh" ]; then
    step 'Installer delegato: copia dal checkout locale'
    cp "./install.sh" "$DELEGATE"
else
    step 'Installer delegato: download'
    info "$RAW/install.sh"
    fetch "$RAW/install.sh" "$DELEGATE" || die "download fallito: install.sh"
fi

if [ "$VERIFY" = true ]; then
    SUMS=""
    if [ -f "./SHA256SUMS" ]; then
        SUMS="./SHA256SUMS"
    else
        fetch "$RAW/SHA256SUMS" "$TMPD/SHA256SUMS" 2>/dev/null && SUMS="$TMPD/SHA256SUMS" || true
    fi
    if [ -n "$SUMS" ]; then
        step 'Verifica sha256 di install.sh'
        want="$(awk -v n="install.sh" '$2 == n || $2 == "*"n {print $1}' "$SUMS" | head -1)"
        got="$(sha256 "$DELEGATE")"
        if [ -z "$want" ]; then
            info 'nessun hash per install.sh in SHA256SUMS, salto'
        elif [ -z "$got" ]; then
            info 'nessuno strumento sha256 disponibile, verifica impossibile'
        elif [ "$want" = "$got" ]; then
            info "install.sh  OK"
        else
            die "checksum non corrispondente per install.sh
  atteso:  $want
  ottenuto: $got
  Il codice che sto per eseguire non e' quello dichiarato. Non proseguo."
        fi
    fi
fi

# --- installazione, delegata -----------------------------------------------

INSTALLER_ARGS="--ref $REF --prefix $PREFIX"
[ "$VERIFY" = true ] || INSTALLER_ARGS="$INSTALLER_ARGS --no-verify"
[ "$DRY_RUN" = true ] && INSTALLER_ARGS="$INSTALLER_ARGS --dry-run"

# shellcheck disable=SC2086
sh "$DELEGATE" $INSTALLER_ARGS

if [ "$DRY_RUN" = true ]; then
    step 'Dry run: nessuna scrittura'
    info "poi sarebbe stato eseguito: pi-conf.sh add$PROVIDER_ARGS"
    exit 0
fi

# --- configurazione ---------------------------------------------------------

step 'Configurazione del provider'
# shellcheck disable=SC2086
"$PREFIX/pi-conf.sh" add $PROVIDER_ARGS

step 'Fatto'
cat <<EOF
  Tool:    $PREFIX/pi-conf.sh
  Config:  vedi l'output di pi-conf.sh add qui sopra

  Per usare il provider:
      pi --provider <nome> --model <model>

  Se hai usato --key-env, la variabile deve essere esportata nella shell da cui
  lanci pi, altrimenti il provider risultera' non autenticato.
EOF
