#!/usr/bin/env bash
# pi-conf.sh — crea un profilo provider custom per pi-code (pi-coding-agent).
#
# Scrive/aggiorna ~/.pi/agent/models.json con un singolo provider, facendo
# merge (non overwrite) dei provider gia' presenti.
#
# Uso:  pi-conf.sh          (interattivo)
#       pi-conf.sh --help

set -euo pipefail

# --- Config ------------------------------------------------------------------

# Path del file di configurazione di pi.
# Override con PI_CONF_FILE oppure PI_CODING_AGENT_DIR.
PI_CONF_FILE="${PI_CONF_FILE:-${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/models.json}"

# Path del binario pi (per auth check finale). Default: stesso path del
# binario `pi` risolto via PATH.
if command -v pi >/dev/null 2>&1; then
    PI_BIN="$(command -v pi)"
else
    PI_BIN="${PI_BIN:-$HOME/.local/bin/pi}"
fi

# --- Helpers -----------------------------------------------------------------

usage() {
    cat <<'EOF'
pi-conf.sh — crea un profilo provider custom per pi-code

Uso:
  pi-conf.sh [--help]

Senza argomenti, lo script e' interattivo e chiede in ordine:
  1. Endpoint URL              (es. https://api.server.example)
  2. Standard API              (anthropic, openai, google, mistral, ...)
  3. Model ID                  (es. MLR-3, claude-sonnet-4-5)
  4. Nome del profilo          (provider name in pi)
  5. API key                   (opzionale: vuoto = configura dopo con /login)
  6. Reasoning? (y/N)
  7. Context window (default 512000)
  8. Max output tokens (default 32768)
  9. Multimodale?         (default: y, il modello accetta immagini)

Scrive/aggiorna: ~/.pi/agent/models.json (merge, mode 0600).

Per usarlo dopo:
  pi --provider <nome> --model <modello>
oppure in TUI: /model

EOF
}

# Friendly name -> pi internal api name
map_standard() {
    case "$1" in
        anthropic|claude)             echo "anthropic-messages" ;;
        openai|gpt)                   echo "openai-completions" ;;
        responses|openai-responses)   echo "openai-responses" ;;
        google|gemini)                echo "google-generative-ai" ;;
        mistral)                      echo "mistral-conversations" ;;
        bedrock)                      echo "bedrock-converse-stream" ;;
        vertex)                       echo "google-vertex" ;;
        codex)                        echo "openai-codex-responses" ;;
        azure)                        echo "azure-openai-responses" ;;
        *)                            echo "$1" ;;
    esac
}

# Stampa prompt e mette la risposta in $REPLY (mai vuoto se non c'e' default)
prompt() {
    local label="$1"
    local default="${2:-}"
    local value
    if [[ -n "$default" ]]; then
        read -r -p "$label [$default]: " value
        value="${value:-$default}"
    else
        read -r -p "$label: " value
        while [[ -z "$value" ]]; do
            echo "  (!) richiesto" >&2
            read -r -p "$label: " value
        done
    fi
    REPLY="$value"
}

# Prompt per secret con feedback visivo (stelle per ogni carattere).
# Mostra '*' durante typing e paste, gestisce backspace.
prompt_secret() {
    local label="$1" value="" char
    printf "%s" "$label (vuoto = salta, configura dopo con /login): "
    while IFS= read -r -s -n 1 char; do
        # read -s -n 1 restituisce stringa vuota su Enter (o EOF)
        if [[ -z "$char" ]]; then
            break
        fi
        # Gestisci backspace (DEL=0x7f su macOS, BS=0x08 su altri terminali)
        if [[ "$char" == $'\x7f' ]] || [[ "$char" == $'\b' ]]; then
            if [[ -n "$value" ]]; then
                value="${value%?}"
                printf '\b \b'
            fi
            continue
        fi
        # Carattere normale: accumula e mostra '*'
        value+="$char"
        printf '*'
    done
    printf '\n'
    REPLY="$value"
}

# y/N prompt; default = "y" o "n"
prompt_yn() {
    local label="$1"
    local default="${2:-y}"
    local value suffix
    case "$default" in
        y|Y|yes|YES) suffix="[Y/n]" ;;
        *)           suffix="[y/N]" ;;
    esac
    while true; do
        read -r -p "$label $suffix: " value
        value="${value:-$default}"
        # case-insensitive: convertiamo a lowercase con tr
        local lower
        lower="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
        case "$lower" in
            y|yes) REPLY="y"; return 0 ;;
            n|no)  REPLY="n"; return 0 ;;
            *) echo "  (!) rispondi y o n" >&2 ;;
        esac
    done
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Errore: '$1' richiesto ma non trovato in PATH" >&2
        exit 1
    }
}

# Sanitize nome provider per pi (lowercase + solo [a-z0-9_-])
# Nota: si usa `tr -cs 'a-z0-9-'` esplicito invece di `[:alnum:]` perche' sotto
# un locale UTF-8 `[:alnum:]` lascia passare caratteri non ASCII, che poi
# fallirebbero la validazione `^[a-zA-Z0-9_-]+$`. Coerente con Get-SanitizedName
# in PowerShell, che usa `[^a-z0-9-]+`.
sanitize_name() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs 'a-z0-9-' '-' \
        | sed -e 's/^[-]*//' -e 's/[-]*$//'
}

# Programma jq del merge non distruttivo, condiviso dai due percorsi.
#  - le chiavi assenti in $p mantengono il valore precedente
#  - i modelli sono uniti per id, in posizione
# `input` e `cost` seguono la stessa regola: se il nuovo modello non li
# dichiara, resta il valore gia' presente nel modello esistente. Senza questo
# un re-run su un modello configurato a mano come multimodale lo degraderebbe
# a ["text"], azzerando la capacita' immagine.
MERGE_PROGRAM='
    .providers[$name] as $old
    | (($old.models // []) | map(select(.id == $p.models[0].id)) | .[0] // {}) as $om
    | ($om
       * ($p.models[0] | .cost = null)
       * { cost: ($om.cost // { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }),
           input: ($p.models[0].input // $om.input // ["text", "image"]) }) as $m
    | .providers[$name] = (
        ($old // {})
        * $p
        * { models:
              ( ($old.models // [])
                | map(if .id == $m.id then $m else . end)
                | (if any(.[]; .id == $m.id) then . else . + [$m] end) ) }
      )
'

# Normalizza una lista di modalita' di input in un array JSON, validandola
# contro il tipo dichiarato da pi: input: ("text" | "image")[]. Non si
# accettano altri valori perche' pi non li accetterebbe.
# Restituisce 1 se la lista non e' valida.
normalize_input() {
    local raw parts tok out=""
    raw="$(printf '%s' "$1" | tr -d '[:space:]')"
    [[ -z "$raw" ]] && return 1
    parts="$(printf '%s' "$raw" | tr ',' '\n')"
    while IFS= read -r tok; do
        case "$tok" in
            text|image) ;;
            *) return 1 ;;
        esac
        out="${out:+$out,}\"$tok\""
    done <<< "$parts"
    printf '[%s]' "$out"
}

# build_provider_json <baseUrl> <api> <apiKey> <modelId> <reasoning> <ctx> <max> [inputJson]
# <apiKey> puo' essere la chiave in chiaro, un riferimento "$NOME_ENV" (usato
# con --key-env) oppure la stringa vuota per ometterla del tutto.
# <inputJson> vuoto = non dichiarare input, e lascia decidere il merge.
build_provider_json() {
    jq -n \
        --arg baseUrl "$1" \
        --arg api "$2" \
        --arg apiKey "$3" \
        --arg modelId "$4" \
        --argjson reasoning "$5" \
        --argjson contextWindow "$6" \
        --argjson maxTokens "$7" \
        --argjson input "${8:-null}" \
        '{
            baseUrl: $baseUrl,
            api: $api
        }
        + (if $apiKey != "" then {apiKey: $apiKey} else {} end)
        + {
            models: [ (
                { id: $modelId, name: $modelId, reasoning: $reasoning }
                + (if $input == null then {} else { input: $input } end)
                + { contextWindow: $contextWindow,
                    maxTokens: $maxTokens,
                    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }
            ) ]
        }'
}

# Maschera l'apiKey per la sola anteprima a terminale.
# `has("apiKey")` e' necessario: in jq, `|=` su una chiave assente la crea con
# null, e l'anteprima mostrerebbe un campo che nel file non esiste.
mask_api_key() {
    jq 'if has("apiKey")
        then .apiKey |= (if . == null or . == "" then . else "••••••••" + .[-4:] end)
        else . end'
}

# write_provider <profileName> <providerJson>
# Backup della versione corrente, poi merge non distruttivo.
# Ritorna 1 senza toccare il file se il backup o il merge falliscono.
TMP=""
write_provider() {
    local name="$1" pjson="$2" file_existed=false

    if [[ -f "$PI_CONF_FILE" ]]; then
        file_existed=true
    else
        umask 077
        mkdir -p "$(dirname "$PI_CONF_FILE")"
        echo "{}" > "$PI_CONF_FILE"
    fi

    if [[ "$file_existed" == true ]]; then
        if ! cp -p "$PI_CONF_FILE" "$PI_CONF_FILE.bak"; then
            echo "Errore: impossibile creare il backup in $PI_CONF_FILE.bak — file invariato" >&2
            return 1
        fi
    fi

    TMP="$(mktemp)"
    if ! jq --arg name "$name" --argjson p "$pjson" "$MERGE_PROGRAM" "$PI_CONF_FILE" > "$TMP"; then
        rm -f "$TMP"
        TMP=""
        echo "Errore: merge jq fallito, file invariato" >&2
        return 1
    fi
    mv "$TMP" "$PI_CONF_FILE"
    TMP=""
    chmod 600 "$PI_CONF_FILE"
    return 0
}

# --- Modalità non interattiva ------------------------------------------------

usage_add() {
    cat <<'EOF'
pi-conf.sh add — scrive un profilo provider senza porre domande

Uso:
  pi-conf.sh add --endpoint <url> --model <id> [opzioni]
  pi-conf.sh      --endpoint <url> --model <id> [opzioni]   # 'add' implicito

Opzioni:
  --endpoint <url>     endpoint base (obbligatorio, salvo --from-file)
  --api <nome>         anthropic|openai|responses|google|mistral|bedrock|
                       vertex|codex|azure|<raw>        (default: anthropic)
  --model <id>         model id, es. MLR-3              (obbligatorio, salvo --from-file)
  --profile <nome>     nome provider in pi (default: model id sanitizzato)
  --key <valore>       chiave in chiaro (sconsigliato)
  --key-env <NOME>     scrive "apiKey": "$NOME": pi la risolve a richiesta
  --reasoning          reasoning esteso (default)
  --no-reasoning       disattiva il reasoning
  --context <n>        context window      (default: 512000)
  --max-tokens <n>     max output tokens   (default: 32768)
  --input <lista>      capacita' di input, separate da virgola. Valori
                       ammessi: text, image (unione di pi). Default quando
                       omesso: text,image su un modello nuovo, altrimenti
                       l'input gia' presente nel modello
  --from-file <json>   valori mancanti da un JSON
  --config <path>      models.json da scrivere
  --dry-run            stampa l'anteprima e non scrive
  --print-config       stampa la configurazione risultante su stdout
  -y, --yes            non chiedere conferma

Esempio:
  pi-conf.sh add --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --key-env MLR_API_KEY --yes
EOF
}

# true se gli argomenti richiedono il percorso non interattivo
looks_noninteractive() {
    local a
    for a in "$@"; do
        case "$a" in
            add|--endpoint|--endpoint=*|--api|--api=*|--model|--model=*|\
            --profile|--profile=*|--key|--key=*|--key-env|--key-env=*|\
            --reasoning|--no-reasoning|--context|--context=*|\
            --max-tokens|--max-tokens=*|--input|--input=*|--from-file|--config|--config=*|\
            --dry-run|--print-config|--yes|-y)
                return 0 ;;
        esac
    done
    return 1
}

OPT_ENDPOINT=""; OPT_API="anthropic"; OPT_MODEL=""; OPT_PROFILE=""
OPT_KEY=""; OPT_KEY_ENV=""; OPT_REASONING="y"
OPT_CONTEXT=""; OPT_MAXTOK=""; OPT_FROM_FILE=""; OPT_INPUT=""; OPT_INPUT_SET=false
OPT_DRY_RUN=false; OPT_PRINT_CONFIG=false

add_err() { echo "Errore: $*" >&2; }

parse_add_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            add) shift ;;
            --endpoint)     OPT_ENDPOINT="${2:-}"; shift 2 || return 1 ;;
            --endpoint=*)   OPT_ENDPOINT="${1#*=}"; shift ;;
            --api)          OPT_API="${2:-}"; shift 2 || return 1 ;;
            --api=*)        OPT_API="${1#*=}"; shift ;;
            --model)        OPT_MODEL="${2:-}"; shift 2 || return 1 ;;
            --model=*)      OPT_MODEL="${1#*=}"; shift ;;
            --profile)      OPT_PROFILE="${2:-}"; shift 2 || return 1 ;;
            --profile=*)    OPT_PROFILE="${1#*=}"; shift ;;
            --key)          OPT_KEY="${2:-}"; shift 2 || return 1 ;;
            --key=*)        OPT_KEY="${1#*=}"; shift ;;
            --key-env)      OPT_KEY_ENV="${2:-}"; shift 2 || return 1 ;;
            --key-env=*)    OPT_KEY_ENV="${1#*=}"; shift ;;
            --reasoning)    OPT_REASONING="y"; shift ;;
            --no-reasoning) OPT_REASONING="n"; shift ;;
            --context)      OPT_CONTEXT="${2:-}"; shift 2 || return 1 ;;
            --context=*)    OPT_CONTEXT="${1#*=}"; shift ;;
            --max-tokens)   OPT_MAXTOK="${2:-}"; shift 2 || return 1 ;;
            --max-tokens=*) OPT_MAXTOK="${1#*=}"; shift ;;
            --input)        OPT_INPUT="${2:-}"; OPT_INPUT_SET=true; shift 2 || return 1 ;;
            --input=*)      OPT_INPUT="${1#*=}"; OPT_INPUT_SET=true; shift ;;
            --from-file)    OPT_FROM_FILE="${2:-}"; shift 2 || return 1 ;;
            --config)       PI_CONF_FILE="${2:-}"; shift 2 || return 1 ;;
            --config=*)     PI_CONF_FILE="${1#*=}"; shift ;;
            --dry-run)      OPT_DRY_RUN=true; shift ;;
            --print-config) OPT_PRINT_CONFIG=true; shift ;;
            --yes|-y)       shift ;;
            -h|--help)      usage_add; exit 0 ;;
            *)              add_err "argomento sconosciuto: $1"; usage_add >&2; return 2 ;;
        esac
    done
}

# Un valore di --from-file riempie solo i campi non dati a riga di comando.
apply_from_file() {
    local f="$1" k v
    [[ -f "$f" ]] || { add_err "--from-file '$f' non esiste"; return 1; }
    jq -e . "$f" >/dev/null 2>&1 || { add_err "--from-file '$f' non e' JSON valido"; return 1; }
    for k in endpoint api model profile keyEnv context maxTokens; do
        v="$(jq -r --arg k "$k" '.[$k] // empty' "$f")"
        [[ -z "$v" ]] && continue
        case "$k" in
            endpoint)  [[ -z "$OPT_ENDPOINT" ]] && OPT_ENDPOINT="$v" ;;
            api)       [[ "$OPT_API" == "anthropic" ]] && OPT_API="$v" ;;
            model)     [[ -z "$OPT_MODEL"   ]] && OPT_MODEL="$v" ;;
            profile)   [[ -z "$OPT_PROFILE" ]] && OPT_PROFILE="$v" ;;
            keyEnv)    [[ -z "$OPT_KEY_ENV" ]] && OPT_KEY_ENV="$v" ;;
            context)   [[ -z "$OPT_CONTEXT" ]] && OPT_CONTEXT="$v" ;;
            maxTokens) [[ -z "$OPT_MAXTOK"  ]] && OPT_MAXTOK="$v" ;;
        esac
    done
    if [[ "$(jq -r '.reasoning // empty' "$f")" == "false" && "$OPT_REASONING" == "y" ]]; then
        OPT_REASONING="n"
    fi
    # input puo' arrivare come array JSON: si appiattisce in una lista CSV
    if [[ "$OPT_INPUT_SET" != true ]]; then
        v="$(jq -r 'if (.[$k] // empty | type) == "array"
                    then (.[$k] | join(","))
                    else (.[$k] // empty) end' --arg k input "$f" 2>/dev/null)"
        if [[ -n "$v" ]]; then OPT_INPUT="$v"; OPT_INPUT_SET=true; fi
    fi
    return 0
}

run_add() {
    [[ -n "$OPT_FROM_FILE" ]] && { apply_from_file "$OPT_FROM_FILE" || return 1; }

    if [[ -z "$OPT_ENDPOINT" ]]; then
        add_err "manca --endpoint (obbligatorio)"
        return 1
    fi
    if [[ ! "$OPT_ENDPOINT" =~ ^https?:// ]]; then
        add_err "endpoint non valido: deve iniziare con http:// o https://"
        return 1
    fi
    if [[ -z "$OPT_MODEL" ]]; then
        add_err "manca --model (obbligatorio)"
        return 1
    fi
    if [[ -n "$OPT_KEY" && -n "$OPT_KEY_ENV" ]]; then
        add_err "--key e --key-env sono incompatibili: scegline uno"
        return 1
    fi

    local profile="$OPT_PROFILE"
    if [[ -z "$profile" ]]; then
        profile="$(sanitize_name "$OPT_MODEL")"
        [[ -z "$profile" ]] && profile="custom-provider"
    fi
    if [[ ! "$profile" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        add_err "nome profilo '$profile' non valido (usa solo [a-zA-Z0-9_-])"
        return 1
    fi

    local ctx="${OPT_CONTEXT:-512000}" max="${OPT_MAXTOK:-32768}"
    if [[ ! "$ctx" =~ ^[0-9]+$ ]]; then add_err "--context deve essere un intero"; return 1; fi
    if [[ ! "$max" =~ ^[0-9]+$ ]]; then add_err "--max-tokens deve essere un intero"; return 1; fi

    # input: validato contro l'unione di pi ("text" | "image"). Se assente
    # resta vuoto e il merge conserva l'input gia' presente nel modello.
    local input_json=""
    if [[ "$OPT_INPUT_SET" == true ]]; then
        input_json="$(normalize_input "$OPT_INPUT")" || {
            add_err "--input accetta solo text e image, separati da virgola (es. --input text,image): '$OPT_INPUT'"
            return 1
        }
    fi

    # --key-env scrive il riferimento "$NOME": pi interpola l'env var a richiesta,
    # quindi la chiave non finisce mai in chiaro nel file.
    local apikey=""
    if [[ -n "$OPT_KEY_ENV" ]]; then
        if [[ ! "$OPT_KEY_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            add_err "--key-env '$OPT_KEY_ENV' non e' un nome di variabile valido"
            return 1
        fi
        apikey="\$${OPT_KEY_ENV}"
    elif [[ -n "$OPT_KEY" ]]; then
        apikey="$OPT_KEY"
    fi

    local reasoning="false"
    [[ "$OPT_REASONING" == "y" ]] && reasoning="true"

    local api_mapped; api_mapped="$(map_standard "$OPT_API")"
    local pjson
    pjson="$(build_provider_json "$OPT_ENDPOINT" "$api_mapped" "$apikey" \
             "$OPT_MODEL" "$reasoning" "$ctx" "$max" "$input_json")" || {
        add_err "costruzione del JSON fallita"; return 1; }

    if [[ "$OPT_DRY_RUN" == true ]]; then
        echo "ANTEPRIMA (dry-run, nulla scritto in $PI_CONF_FILE)"
        echo "$pjson" | mask_api_key | jq .
        return 0
    fi

    if [[ "$OPT_PRINT_CONFIG" == true ]]; then
        # configura la configurazione risultante senza toccare il file
        local base='{"providers":{}}'
        [[ -f "$PI_CONF_FILE" ]] && base="$(cat "$PI_CONF_FILE")"
        printf '%s' "$base" \
          | jq --arg name "$profile" --argjson p "$pjson" "$MERGE_PROGRAM"
        return 0
    fi

    write_provider "$profile" "$pjson" || return 1

    echo "OK - provider '$profile' salvato in $PI_CONF_FILE"
    if [[ -n "$OPT_KEY_ENV" ]]; then
        echo "     apiKey: letta dall'env var $OPT_KEY_ENV (non scritta in chiaro)"
    fi
    return 0
}

# --- Main --------------------------------------------------------------------

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    require_cmd jq

    # Percorso non interattivo: richiesto esplicitamente o implicito da un flag.
    if looks_noninteractive "$@"; then
        parse_add_args "$@" || exit $?
        run_add
        exit $?
    fi

    echo "pi-conf.sh — creazione profilo provider per pi-code"
    echo "=================================================="
    echo "Config: $PI_CONF_FILE"
    echo "Binario pi: $PI_BIN"
    echo

    # 1. Endpoint
    prompt "1/9  Endpoint URL (es. https://api.server.example)"
    ENDPOINT="$REPLY"
    if [[ ! "$ENDPOINT" =~ ^https?:// ]]; then
        echo "Errore: endpoint non valido (deve iniziare con http:// o https://)" >&2
        exit 1
    fi

    # 2. Standard
    echo
    echo "2/9  Standard API — scegli tra:"
    echo "      anthropic  -> anthropic-messages   (Claude, modelli Anthropic-compat)"
    echo "      openai     -> openai-completions    (GPT-4, /v1/chat/completions)"
    echo "      responses  -> openai-responses      (OpenAI Responses API)"
    echo "      google     -> google-generative-ai  (Gemini)"
    echo "      mistral    -> mistral-conversations"
    echo "      bedrock    -> bedrock-converse-stream (AWS Bedrock)"
    echo "      vertex     -> google-vertex         (GCP Vertex)"
    echo "      codex      -> openai-codex-responses"
    echo "      azure      -> azure-openai-responses"
    echo "      <raw>      -> nome API pi passato tal quale"
    prompt "      Standard" "anthropic"
    STANDARD_INPUT="$REPLY"
    STANDARD_API="$(map_standard "$STANDARD_INPUT")"
    echo "      -> mappato a: $STANDARD_API"

    # 3. Modello
    echo
    prompt "3/9  Model ID (es. MLR-3, claude-sonnet-4-5)"
    MODEL_ID="$REPLY"

    # 4. Nome profilo (default = model-id sanitized)
    SUGGESTED_NAME="$(sanitize_name "$MODEL_ID")"
    [[ -z "$SUGGESTED_NAME" ]] && SUGGESTED_NAME="custom-provider"
    echo
    prompt "4/9  Nome del profilo (provider name in pi)" "$SUGGESTED_NAME"
    PROFILE_NAME="$REPLY"
    if [[ ! "$PROFILE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Errore: nome '$PROFILE_NAME' non valido (usa solo [a-zA-Z0-9_-])" >&2
        exit 1
    fi

    # 5. API key (opzionale)
    echo
    echo "5/9  API key"
    prompt_secret "      Inserisci"
    API_KEY="$REPLY"
    if [[ -z "$API_KEY" ]]; then
        echo "      (saltata — configura dopo con: /login $PROFILE_NAME, oppure imposta env var, oppure edita $PI_CONF_FILE)"
    fi

    # 6. Reasoning
    echo
    prompt_yn "6/9  Modello con reasoning esteso?" "y"
    if [[ "$REPLY" == "y" ]]; then REASONING="true"; else REASONING="false"; fi

    # 7. Context window
    echo
    prompt "7/9  Context window (tokens)" "512000"
    CONTEXT_WINDOW="$REPLY"
    if [[ ! "$CONTEXT_WINDOW" =~ ^[0-9]+$ ]]; then
        echo "Errore: deve essere un intero" >&2
        exit 1
    fi

    # 8. Max output tokens
    echo
    prompt "8/9  Max output tokens" "32768"
    MAX_TOKENS="$REPLY"
    if [[ ! "$MAX_TOKENS" =~ ^[0-9]+$ ]]; then
        echo "Errore: deve essere un intero" >&2
        exit 1
    fi

    # 9. Capacita' di input
    # Il default e' multimodale. Se il modello esiste gia' con un input
    # diverso, la risposta ne rispecchia la situazione corrente, cosi' un
    # invio a capo non cambia nulla in silenzio.
    echo
    MM_DEFAULT="y"
    if [[ -f "$PI_CONF_FILE" ]]; then
        EXISTING_INPUT="$(jq -r --arg n "$PROFILE_NAME" --arg m "$MODEL_ID" \
            '[.providers[$n].models[]? | select(.id == $m) | (.input // [])[]] | join(",")' \
            "$PI_CONF_FILE" 2>/dev/null)"
        if [[ -n "$EXISTING_INPUT" && "$EXISTING_INPUT" != *image* ]]; then
            MM_DEFAULT="n"
        fi
    fi
    prompt_yn "9/9  Il modello accetta immagini?" "$MM_DEFAULT"
    if [[ "$REPLY" == "y" ]]; then INPUT_JSON='["text","image"]'; else INPUT_JSON='["text"]'; fi

    # Costruisci provider JSON (escaping safe) — stesso builder del percorso add
    PROVIDER_JSON="$(build_provider_json "$ENDPOINT" "$STANDARD_API" "$API_KEY" \
                     "$MODEL_ID" "$REASONING" "$CONTEXT_WINDOW" "$MAX_TOKENS" \
                     "$INPUT_JSON")"

    # Anteprima: apiKey mascherata, il valore in chiaro resta solo nel file
    PREVIEW_JSON="$(echo "$PROVIDER_JSON" | mask_api_key)"

    # Preview
    echo
    echo "----------------------------------------------------------"
    echo "ANTEPRIMA — verra' scritto in $PI_CONF_FILE"
    echo "----------------------------------------------------------"
    echo "Profilo: $PROFILE_NAME"
    echo "$PREVIEW_JSON" | jq .
    echo "----------------------------------------------------------"

    # Controlla sovrascrittura
    if [[ -f "$PI_CONF_FILE" ]] && jq -e --arg n "$PROFILE_NAME" '.providers[$n]' "$PI_CONF_FILE" >/dev/null 2>&1; then
        echo
        echo "(!) Esiste gia' un provider '$PROFILE_NAME' — verra' aggiornato"
        echo "    I campi che lo script non gestisce (apiKey, promptCache, headers, compat,"
        echo "    cost e input personalizzati) e gli eventuali modelli aggiuntivi vengono conservati."
        echo "    Viene creato un backup in $PI_CONF_FILE.bak"
        prompt_yn "     Procedere?" "n"
        if [[ "$REPLY" != "y" ]]; then
            echo "Annullato."
            exit 0
        fi
    fi

    # Conferma finale
    echo
    prompt_yn "Confermi scrittura?" "y"
    if [[ "$REPLY" != "y" ]]; then
        echo "Annullato."
        exit 0
    fi

    # Crea file se non esiste
    # Backup + merge non distruttivo (stessi helper del percorso add)
    if ! write_provider "$PROFILE_NAME" "$PROVIDER_JSON"; then
        exit 1
    fi
    chmod 600 "$PI_CONF_FILE"

    local size
    size="$(wc -c < "$PI_CONF_FILE" | tr -d ' ')"
    echo
    echo "OK — provider '$PROFILE_NAME' salvato"
    echo "     File: $PI_CONF_FILE ($size byte, mode 600)"
    echo
    echo "Per usarlo:"
    echo "  pi --provider \"$PROFILE_NAME\" --model \"$MODEL_ID\""
    echo "oppure in TUI: /model"

    # Verifica finale (non blocca se fallisce)
    echo
    echo "Verifica auth:"
    if [[ -x "$PI_BIN" ]]; then
        "$PI_BIN" auth check --provider "$PROFILE_NAME" --json 2>&1 || \
            echo "(auth check fallito — verifica manualmente con: pi auth check --provider $PROFILE_NAME)"
    else
        echo "(binario pi non trovato in $PI_BIN — verifica saltata)"
    fi
}

main "$@"
