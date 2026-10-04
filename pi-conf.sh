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
sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]-' '-' | sed 's/^-\|-$//g'
}

# --- Main --------------------------------------------------------------------

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi

    require_cmd jq

    echo "pi-conf.sh — creazione profilo provider per pi-code"
    echo "=================================================="
    echo "Config: $PI_CONF_FILE"
    echo "Binario pi: $PI_BIN"
    echo

    # 1. Endpoint
    prompt "1/8  Endpoint URL (es. https://api.server.example)"
    ENDPOINT="$REPLY"
    if [[ ! "$ENDPOINT" =~ ^https?:// ]]; then
        echo "Errore: endpoint non valido (deve iniziare con http:// o https://)" >&2
        exit 1
    fi

    # 2. Standard
    echo
    echo "2/8  Standard API — scegli tra:"
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
    prompt "3/8  Model ID (es. MLR-3, claude-sonnet-4-5)"
    MODEL_ID="$REPLY"

    # 4. Nome profilo (default = model-id sanitized)
    SUGGESTED_NAME="$(sanitize_name "$MODEL_ID")"
    [[ -z "$SUGGESTED_NAME" ]] && SUGGESTED_NAME="custom-provider"
    echo
    prompt "4/8  Nome del profilo (provider name in pi)" "$SUGGESTED_NAME"
    PROFILE_NAME="$REPLY"
    if [[ ! "$PROFILE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Errore: nome '$PROFILE_NAME' non valido (usa solo [a-zA-Z0-9_-])" >&2
        exit 1
    fi

    # 5. API key (opzionale)
    echo
    echo "5/8  API key"
    prompt_secret "      Inserisci"
    API_KEY="$REPLY"
    if [[ -z "$API_KEY" ]]; then
        echo "      (saltata — configura dopo con: /login $PROFILE_NAME, oppure imposta env var, oppure edita $PI_CONF_FILE)"
    fi

    # 6. Reasoning
    echo
    prompt_yn "6/8  Modello con reasoning esteso?" "y"
    if [[ "$REPLY" == "y" ]]; then REASONING="true"; else REASONING="false"; fi

    # 7. Context window
    echo
    prompt "7/8  Context window (tokens)" "512000"
    CONTEXT_WINDOW="$REPLY"
    if [[ ! "$CONTEXT_WINDOW" =~ ^[0-9]+$ ]]; then
        echo "Errore: deve essere un intero" >&2
        exit 1
    fi

    # 8. Max output tokens
    echo
    prompt "8/8  Max output tokens" "32768"
    MAX_TOKENS="$REPLY"
    if [[ ! "$MAX_TOKENS" =~ ^[0-9]+$ ]]; then
        echo "Errore: deve essere un intero" >&2
        exit 1
    fi

    # Costruisci provider JSON con jq (escaping safe)
    PROVIDER_JSON="$(jq -n \
        --arg baseUrl "$ENDPOINT" \
        --arg api "$STANDARD_API" \
        --arg apiKey "$API_KEY" \
        --arg modelId "$MODEL_ID" \
        --argjson reasoning "$REASONING" \
        --argjson contextWindow "$CONTEXT_WINDOW" \
        --argjson maxTokens "$MAX_TOKENS" \
        '{
            baseUrl: $baseUrl,
            api: $api
        }
        + (if $apiKey != "" then {apiKey: $apiKey} else {} end)
        + {
            models: [{
                id: $modelId,
                name: $modelId,
                reasoning: $reasoning,
                input: ["text"],
                contextWindow: $contextWindow,
                maxTokens: $maxTokens,
                cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }
            }]
        }')"

    # Preview
    echo
    echo "----------------------------------------------------------"
    echo "ANTEPRIMA — verra' scritto in $PI_CONF_FILE"
    echo "----------------------------------------------------------"
    echo "Profilo: $PROFILE_NAME"
    echo "$PROVIDER_JSON" | jq .
    echo "----------------------------------------------------------"

    # Controlla sovrascrittura
    if [[ -f "$PI_CONF_FILE" ]] && jq -e --arg n "$PROFILE_NAME" '.providers[$n]' "$PI_CONF_FILE" >/dev/null 2>&1; then
        echo
        echo "(!) Esiste gia' un provider '$PROFILE_NAME' — verra' sovrascritto"
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
    if [[ ! -f "$PI_CONF_FILE" ]]; then
        umask 077
        mkdir -p "$(dirname "$PI_CONF_FILE")"
        echo "{}" > "$PI_CONF_FILE"
    fi

    # Merge con jq
    TMP="$(mktemp)"
    trap 'rm -f "$TMP"' EXIT

    if ! jq --arg name "$PROFILE_NAME" --argjson provider "$PROVIDER_JSON" \
        '.providers[$name] = $provider' "$PI_CONF_FILE" > "$TMP"; then
        echo "Errore: merge jq fallito, file invariato" >&2
        exit 1
    fi
    mv "$TMP" "$PI_CONF_FILE"
    trap - EXIT
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
