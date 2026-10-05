#!/usr/bin/env bash
# tests/pi-conf-test.sh — behavioural tests for pi-conf.sh
#
# Covers:
#   issue #1 — re-running the script on an existing profile used to replace the
#              whole provider, dropping apiKey, promptCache, headers, custom
#              cost and the other models
#   issue #2 — the terminal preview used to echo the apiKey in cleartext
#
# Run: bash tests/pi-conf-test.sh
# Exit code 0 = all green, 1 = at least one failure.
#
# The PowerShell script is NOT executed here (pwsh is not required to run this
# suite). pi-conf.ps1 is covered only by the static tripwire checks in §9, which
# guard against deleting the fix. They are not a substitute for running it on
# Windows.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_SH="$REPO_DIR/pi-conf.sh"
CONF_PS1="$REPO_DIR/pi-conf.ps1"

PASS=0
FAIL=0

# --- harness ----------------------------------------------------------------

# A stub `pi` so the trailing auth check never runs for real and never touches
# the network. PATH is prepended, so `command -v pi` in the script finds this.
STUB_DIR="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$STUB_DIR" "$WORK"' EXIT
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_DIR/pi"
chmod +x "$STUB_DIR/pi"
export PATH="$STUB_DIR:$PATH"

# Firma della configurazione reale di pi, per verificare a fine suite che nessun
# test l'ha toccata. Senza questa guardia un test che dimentica PI_CONF_FILE
# scrive sul models.json dell'utente e fallisce in silenzio: e' successo.
REAL_CONF="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/models.json"
conf_sig() {
    if [ -f "$REAL_CONF" ]; then
        if command -v sha256sum >/dev/null 2>&1; then sha256sum "$REAL_CONF" | cut -d' ' -f1
        else shasum -a 256 "$REAL_CONF" | cut -d' ' -f1; fi
    else printf 'assente'; fi
}
REAL_CONF_BEFORE="$(conf_sig)"

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
fail() {
    FAIL=$((FAIL+1))
    printf '  FAIL %s\n         atteso: %s\n         attuale: %s\n' "$1" "$2" "$3"
}

# assert_jq <nome> <file> <filtro jq> <atteso>
assert_jq() {
    local actual
    actual="$(jq -r "$3" "$2" 2>/dev/null)"
    if [[ "$actual" == "$4" ]]; then ok "$1"; else fail "$1" "$4" "${actual:-<jq fallito o file assente>}"; fi
}

# run_conf <target models.json> <stdin payload>  — output lands in $WORK/out
run_conf() {
    printf '%b' "$2" > "$WORK/stdin"
    PI_CONF_FILE="$1" bash "$CONF_SH" < "$WORK/stdin" > "$WORK/out" 2>&1
}

# seed <file> — a provider carrying everything a destructive re-run would delete
seed() {
    cat > "$1" <<'JSON'
{
  "providers": {
    "MLR-3": {
      "baseUrl": "https://api.server.example",
      "api": "anthropic-messages",
      "apiKey": "testkey_KEEPME0000000001",
      "models": [
        { "id": "MLR-3", "name": "MLR-3", "reasoning": true, "input": ["text"],
          "contextWindow": 200000, "maxTokens": 16384,
          "promptCache": { "short": 200000, "long": 1000000 },
          "cost": { "input": 3, "output": 15, "cacheRead": 0.3, "cacheWrite": 3.75 } },
        { "id": "MLR-3-mini", "name": "MLR-3-mini", "reasoning": false, "input": ["text"],
          "contextWindow": 128000, "maxTokens": 8192,
          "cost": { "input": 1, "output": 5, "cacheRead": 0.1, "cacheWrite": 1.25 } }
      ],
      "headers": { "X-Tenant": "fulvio" }
    },
    "altro-provider": {
      "baseUrl": "https://other.example",
      "api": "openai-completions",
      "models": [
        { "id": "gpt-x", "name": "gpt-x", "reasoning": false, "input": ["text"],
          "contextWindow": 4096, "maxTokens": 4096,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } }
      ]
    }
  }
}
JSON
}

# Payloads, in prompt order:
#   1 endpoint, 2 standard, 3 model, 4 profile name, 5 api key, 6 reasoning,
#   7 context, 8 max output, 9 overwrite confirm, 10 final confirm
P_NEW='https://api.server.example\nanthropic\nMLR-3\nfresh\ntestkey_NEWKEY0001\ny\n\n\ny\n'
P_RERUN='https://api.server.example\nanthropic\nMLR-3\nMLR-3\n\ny\n512000\n32768\ny\ny\n'
P_ADD='https://api.server.example\nanthropic\nMLR-3-turbo\nMLR-3\ntestkey_ADDEDKEY02\ny\n800000\n65536\ny\ny\n'

echo "pi-confurator — behavioural test suite"
echo

# --- §1 new provider on an empty file --------------------------------------
echo "§1 nuovo provider su file vuoto"
F="$WORK/s1.json"
run_conf "$F" "$P_NEW"
assert_jq "providers creato"                    "$F" '.providers.fresh.id // .providers.fresh.baseUrl' 'https://api.server.example'
assert_jq "apiKey scritta quando fornita"       "$F" '.providers.fresh.apiKey' 'testkey_NEWKEY0001'
assert_jq "modello scritto"                     "$F" '.providers.fresh.models[0].id' 'MLR-3'
assert_jq "default context window"              "$F" '.providers.fresh.models[0].contextWindow' '512000'
assert_jq "default max output"                  "$F" '.providers.fresh.models[0].maxTokens' '32768'
[ "$(stat -f '%Lp' "$F" 2>/dev/null || stat -c '%a' "$F")" = "600" ] \
    && ok "permessi 0600" || fail "permessi 0600" "600" "$(stat -f '%Lp' "$F" 2>/dev/null || stat -c '%a' "$F")"
echo

# --- §2 new provider, api key omitted ---------------------------------------
echo "§2 nuovo provider senza api key"
F="$WORK/s2.json"
run_conf "$F" 'https://api.server.example\nanthropic\nMLR-3\nnokey\n\ny\n\n\ny\n'
assert_jq "apiKey assente quando omessa"         "$F" '.providers.nokey | has("apiKey")' 'false'
echo

# --- §3 THE CORE OF ISSUE #1: re-run must not destroy -----------------------
echo "§3 re-run su provider esistente (issue #1)"
F="$WORK/s3.json"
seed "$F"
cp "$F" "$WORK/s3-before.json"
run_conf "$F" "$P_RERUN"
assert_jq "apiKey conservata"                   "$F" '.providers["MLR-3"].apiKey' 'testkey_KEEPME0000000001'
assert_jq "promptCache conservato"              "$F" '.providers["MLR-3"].models[0].promptCache.short' '200000'
assert_jq "promptCache.long conservato"         "$F" '.providers["MLR-3"].models[0].promptCache.long' '1000000'
assert_jq "headers conservati"                  "$F" '.providers["MLR-3"].headers["X-Tenant"]' 'fulvio'
assert_jq "cost reale conservato (input)"       "$F" '.providers["MLR-3"].models[0].cost.input' '3'
assert_jq "cost reale conservato (output)"      "$F" '.providers["MLR-3"].models[0].cost.output' '15'
assert_jq "secondo modello conservato"          "$F" '[.providers["MLR-3"].models[].id] | index("MLR-3-mini") != null' 'true'
echo

# --- §4 re-run must still apply what the user asked ------------------------
echo "§4 re-run applica i valori nuovi"
assert_jq "contextWindow aggiornato"            "$F" '.providers["MLR-3"].models[0].contextWindow' '512000'
assert_jq "maxTokens aggiornato"                "$F" '.providers["MLR-3"].models[0].maxTokens' '32768'
assert_jq "endpoint aggiornato"                 "$F" '.providers["MLR-3"].baseUrl' 'https://api.server.example'
echo

# --- §5 adding a second model to an existing provider ----------------------
echo "§5 aggiungere un modello a un provider esistente"
F="$WORK/s5.json"
seed "$F"
run_conf "$F" "$P_ADD"
assert_jq "modello nuovo presente"              "$F" '[.providers["MLR-3"].models[].id] | index("MLR-3-turbo") != null' 'true'
assert_jq "modello vecchio ancora presente"     "$F" '[.providers["MLR-3"].models[].id] | index("MLR-3") != null' 'true'
assert_jq "mini ancora presente"                "$F" '.providers["MLR-3"].models | length' '3'
assert_jq "promptCache non perso"               "$F" '.providers["MLR-3"].models[0].promptCache.short' '200000'
assert_jq "apiKey aggiornata quando fornita"    "$F" '.providers["MLR-3"].apiKey' 'testkey_ADDEDKEY02'
assert_jq "cost del modello nuovo a zero"       "$F" '.providers["MLR-3"].models[] | select(.id=="MLR-3-turbo") | .cost.input' '0'
echo

# --- §6 neighbours, idempotence, ordering -----------------------------------
echo "§6 isolamento e idempotenza"
F="$WORK/s6.json"
seed "$F"
run_conf "$F" "$P_RERUN"
assert_jq "provider vicino intatto"             "$F" '.providers["altro-provider"].models[0].id' 'gpt-x'
assert_jq "ordine dei modelli preservato"       "$F" '[.providers["MLR-3"].models[].id] | join(",")' 'MLR-3,MLR-3-mini'
cp "$F" "$WORK/s6-pass1.json"
run_conf "$F" "$P_RERUN"
if diff -q "$WORK/s6-pass1.json" "$F" >/dev/null 2>&1; then ok "secondo giro identico"
else fail "secondo giro identico" "nessuna differenza" "$(diff "$WORK/s6-pass1.json" "$F" 2>&1 | head -5)"; fi
echo

# --- §7 ISSUE #2: the preview must not echo the key ------------------------
echo "§7 anteprima senza chiave in chiaro (issue #2)"
F="$WORK/s7.json"
run_conf "$F" "$P_NEW"
if grep -q 'testkey_NEWKEY0001' "$WORK/out"; then
    fail "chiave assente dall'output del terminale" "nessuna occorrenza" "trovata: $(grep -n 'testkey_NEWKEY0001' "$WORK/out" | head -2)"
else
    ok "chiave assente dall'output del terminale"
fi
if grep -q '••••' "$WORK/out"; then ok "maschera presente in anteprima"
else fail "maschera presente in anteprima" "••••" "nessun carattere di maschera"; fi
assert_jq "il file conserva la chiave in chiaro" "$F" '.providers.fresh.apiKey' 'testkey_NEWKEY0001'
echo

# --- §8 a backup of the previous content must exist before the overwrite ----
echo "§8 backup prima della sovrascrittura"
F="$WORK/s8.json"
seed "$F"
run_conf "$F" "$P_RERUN"
if [ -f "$F.bak" ]; then ok "backup creato"; else fail "backup creato" "$F.bak" "assente"; fi
if [ -f "$F.bak" ]; then
    assert_jq "il backup ha lo stato precedente (2 modelli)" "$F.bak" '.providers["MLR-3"].models | length' '2'
    assert_jq "il backup ha la context window precedente"      "$F.bak" '.providers["MLR-3"].models[0].contextWindow' '200000'
    assert_jq "il backup ha la vecchia apiKey"                 "$F.bak" '.providers["MLR-3"].apiKey' 'testkey_KEEPME0000000001'
fi
G="$WORK/s8-new.json"
run_conf "$G" "$P_NEW"
[ -f "$G.bak" ] && fail "nessun backup su file inesistente" "assente" "$G.bak esiste" || ok "nessun backup su file inesistente"
echo

# --- §9 static tripwires for pi-conf.ps1 (not executed here) ----------------
echo "§9 controlli statici su pi-conf.ps1 (non eseguito)"
INSTALL_PS1="$REPO_DIR/install.ps1"
if [ -f "$INSTALL_PS1" ]; then
    nb_o=$(grep -o '{' "$INSTALL_PS1" | wc -l | tr -d ' ')
    nb_c=$(grep -o '}' "$INSTALL_PS1" | wc -l | tr -d ' ')
    [[ "$nb_o" == "$nb_c" ]] && ok "install.ps1: graffe bilanciate ($nb_o)" \
        || fail "install.ps1: graffe bilanciate" "$nb_o" "$nb_c"
    for needle in 'Invoke-WebRequest' 'Get-FileHash' 'SHA256SUMS' 'ValueFromRemainingArguments' 'Passthrough'; do
        grep -q "$needle" "$INSTALL_PS1" && ok "install.ps1 contiene $needle" \
            || fail "install.ps1 contiene $needle" "$needle" "assente"
    done
    # Windows PowerShell 5.1 lo richiede esplicitamente
    grep -q -- '-UseBasicParsing' "$INSTALL_PS1" && ok "install.ps1 usa -UseBasicParsing (PS 5.1)" \
        || fail "install.ps1 usa -UseBasicParsing (PS 5.1)" "-UseBasicParsing" "assente"
else
    echo "  (install.ps1 assente)"
fi
if grep -q 'providers\.\$ProfileName = \$providerObj' "$CONF_PS1"; then
    fail "sovrascrittura grezza rimossa" "assente" "presente: providers.\$ProfileName = \$providerObj"
else ok "sovrascrittura grezza rimossa"; fi
if grep -q 'function Merge-Provider' "$CONF_PS1"; then ok "helper Merge-Provider presente"
else fail "helper Merge-Provider presente" "function Merge-Provider" "assente"; fi
if grep -q 'function Mask-ApiKey' "$CONF_PS1"; then ok "helper Mask-ApiKey presente"
else fail "helper Mask-ApiKey presente" "function Mask-ApiKey" "assente"; fi
if grep -q 'function Save-ConfigBackup' "$CONF_PS1"; then ok "helper Save-ConfigBackup presente"
else fail "helper Save-ConfigBackup presente" "function Save-ConfigBackup" "assente"; fi
if grep -q 'function Get-AddOptions' "$CONF_PS1"; then ok "parser Get-AddOptions presente"
else fail "parser Get-AddOptions presente" "function Get-AddOptions" "assente"; fi
if grep -q 'function Invoke-Add' "$CONF_PS1"; then ok "Invoke-Add presente"
else fail "Invoke-Add presente" "function Invoke-Add" "assente"; fi
if grep -q 'function Show-AddUsage' "$CONF_PS1"; then ok "Show-AddUsage presente"
else fail "Show-AddUsage presente" "function Show-AddUsage" "assente"; fi
if grep -q 'ValueFromRemainingArguments' "$CONF_PS1"; then ok "parametro \$Rest cattura gli argomenti"
else fail "parametro \$Rest cattura gli argomenti" "ValueFromRemainingArguments" "assente"; fi
# i default delle due implementazioni non devono divergere
defaults_of() {  # <file> <bash|ps1>
    python3 - "$1" "$2" <<'PY'
import re, sys
src, kind = open(sys.argv[1]).read(), sys.argv[2]
pats = {
  'bash': ((r'ctx="\$\{OPT_CONTEXT:-(\d+)\}"', 'ctx'),
           (r'max="\$\{OPT_MAXTOK:-(\d+)\}"',   'max')),
  'ps1':  ((r"\$ctx\s*=\s*if\s*\(.*?else\s*\{\s*'(\d+)'\s*\}", 'ctx'),
           (r"\$max\s*=\s*if\s*\(.*?else\s*\{\s*'(\d+)'\s*\}", 'max')),
}[kind]
out = []
for pat, key in pats:
    m = re.search(pat, src, re.S)
    out.append(f"{key}={m.group(1) if m else '?'}")
print(" ".join(out))
PY
}
sh_def=$(defaults_of "$CONF_SH" bash)
ps_def=$(defaults_of "$CONF_PS1" ps1)
[[ "$sh_def" == "$ps_def" && "$sh_def" != *"=?"* ]] \
    && ok "default coerenti fra bash e PowerShell ($sh_def)" \
    || fail "default coerenti fra bash e PowerShell" "stessi valori, nessuno mancante" "bash='$sh_def' ps1='$ps_def'"
echo

# --- §10 non-interactive mode: the one-line installer's entry point ---------
echo "§10 modalità non interattiva (add)"

# run_args <target models.json> <args...> — no stdin at all
run_args() {
    local target="$1"; shift
    PI_CONF_FILE="$target" bash "$CONF_SH" "$@" < /dev/null > "$WORK/out" 2>&1
}

F="$WORK/s10.json"
run_args "$F" add \
    --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --profile cfg1 --key-env MLR_KEY \
    --reasoning --context 512000 --max-tokens 32768 --yes
assert_jq "endpoint scritto"                   "$F" '.providers.cfg1.baseUrl' 'https://api.server.example'
assert_jq "api mappata"                        "$F" '.providers.cfg1.api' 'anthropic-messages'
assert_jq "apiKey per env var (NON in chiaro)" "$F" '.providers.cfg1.apiKey' '$MLR_KEY'
assert_jq "reasoning applicato"                "$F" '.providers.cfg1.models[0].reasoning' 'true'
assert_jq "context applicato"                  "$F" '.providers.cfg1.models[0].contextWindow' '512000'
assert_jq "max tokens applicato"               "$F" '.providers.cfg1.models[0].maxTokens' '32768'

F="$WORK/s10b.json"
run_args "$F" add --endpoint https://api.server.example --api openai \
    --model gpt-x --key-env K --no-reasoning --yes
assert_jq "no-reasoning applicato"             "$F" '.providers["gpt-x"].models[0].reasoning' 'false'
assert_jq "default profile = model sanitizzato" "$F" '.providers["gpt-x"].models[0].id' 'gpt-x'
assert_jq "api openai mappata"                 "$F" '.providers["gpt-x"].api' 'openai-completions'

# defaults: no --context/--max-tokens given
F="$WORK/s10c.json"
run_args "$F" add --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --key-env K --yes
assert_jq "context di default"                 "$F" '.providers["mlr-3"].models[0].contextWindow' '512000'
assert_jq "max tokens di default"              "$F" '.providers["mlr-3"].models[0].maxTokens' '32768'

# bare flags without the `add` subcommand
F="$WORK/s10d.json"
run_args "$F" --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --key-env K --yes
assert_jq "flag senza 'add' funzionano"        "$F" '.providers["mlr-3"].baseUrl' 'https://api.server.example'

# --dry-run must not write
F="$WORK/s10e.json"
run_args "$F" add --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --key-env K --dry-run
[ -f "$F" ] && fail "--dry-run non scrive" "file assente" "file creato" || ok "--dry-run non scrive"

# --print-config emits valid JSON on stdout
F="$WORK/s10f.json"
run_args "$F" add --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --profile pc --key-env K --print-config
jq -e '.providers.pc.apiKey' "$WORK/out" >/dev/null 2>&1 \
    && ok "--print-config emette JSON valido" || fail "--print-config emette JSON valido" "JSON con providers.pc" "output non parsabile: $(head -3 "$WORK/out")"

# missing required arguments must fail loudly, not silently
F="$WORK/s10g.json"
run_args "$F" add --api anthropic --model MLR-3 --yes
[ -f "$F" ] && fail "manca --endpoint => nessuna scrittura" "file assente" "file creato" \
              || ok "manca --endpoint => nessuna scrittura"
grep -qi "endpoint" "$WORK/out" && ok "messaggio d'errore utile" || fail "messaggio d'errore utile" "menziona endpoint" "$(head -2 "$WORK/out")"

# non-interactive mode must not destroy an existing provider
F="$WORK/s10h.json"
seed "$F"
run_args "$F" add --endpoint https://api.server.example --api anthropic \
    --model MLR-3 --profile MLR-3 --key-env MLR_KEY --yes
assert_jq "apiKey aggiornata a env var"         "$F" '.providers["MLR-3"].apiKey' '$MLR_KEY'
assert_jq "promptCache conservato"              "$F" '.providers["MLR-3"].models[0].promptCache.short' '200000'
assert_jq "modello extra conservato"            "$F" '[.providers["MLR-3"].models[].id] | index("MLR-3-mini") != null' 'true'
[ -f "$F.bak" ] && ok "backup creato in add" || fail "backup creato in add" "$F.bak" "assente"

echo

# --- §11 sanitize_name: no trailing dash, no non-ASCII ----------------------
# Regressione: `echo` aggiunge un newline che `tr -cs` convertiva in "-", e
# `sed 's/^-\|-$//g'` su BSD sed non e' alternanza, quindi il trattino restava.
# Ogni profilo di default ne ereditava uno ("mlr-3-", "gpt-x-").
echo "§11 sanitize_name"
# estraiamo la funzione dal sorgente senza eseguire main()
sed -n '/^sanitize_name()/,/^}/p' "$CONF_SH" > "$WORK/sn.sh"
sn() { ( . "$WORK/sn.sh"; sanitize_name "$1" ) 2>/dev/null; }
assert_eq_str() {
    local name="$1" actual; actual="$(sn "$2")"
    [[ "$actual" == "$3" ]] && ok "$name" || fail "$name" "$3" "${actual:-<vuoto>}"
}
assert_eq_str "gpt-x senza trattino finale"  "gpt-x"             "gpt-x"
assert_eq_str "MLR-3 minuscolo"             "MLR-3"             "mlr-3"
assert_eq_str "claude-sonnet-4-5 intatto"   "claude-sonnet-4-5" "claude-sonnet-4-5"
assert_eq_str "accento espulso, no trattino" "MLR-3é"            "mlr-3"
assert_eq_str "underscore -> trattino"       "a_b"               "a-b"
assert_eq_str "spazi -> trattini"            "a b"               "a-b"
assert_eq_str "vuoto -> stringa vuota"       "..."               ""

# il risultato deve sempre superare la validazione del profilo
for s in "gpt-x" "MLR-3" "MLR-3é" "claude sonnet 4.5" "a_b"; do
    r="$(sn "$s")"
    [[ -z "$r" || "$r" =~ ^[a-zA-Z0-9_-]+$ ]] \
        && ok "sanitize('$s') = '${r:-<vuoto>}' supera la validazione" \
        || fail "sanitize('$s') = '$r' supera la validazione" "solo [a-zA-Z0-9_-]" "$r"
done

echo

# --- §12 installer: install.sh ----------------------------------------------
# L'installer e' la via con cui si installa il tool su un host remoto, quindi
# viene testato come comportamento: cosa scrive, dove, e cosa rifiuta.
echo "§12 install.sh"
INSTALL_SH="$REPO_DIR/install.sh"
SUMS="$REPO_DIR/SHA256SUMS"

if [ ! -f "$INSTALL_SH" ]; then
    echo "  (install.sh assente, sezione saltata)"
else
    sh -n "$INSTALL_SH" && ok "sintassi POSIX sh valida" \
        || fail "sintassi POSIX sh valida" "sh -n pulito" "sh -n ha fallito"

    # lo script viene eseguito da /bin/sh: nessun costrutto solo-bash
    if grep -nE '\[\[|^[[:space:]]*local[[:space:]]|<<<|\$\{!|\+=|[[:space:]]&>|\|&|\bsource\b' \
        "$INSTALL_SH" > "$WORK/bashisms" 2>/dev/null; then
        fail "nessun costrutto bash-only" "sh compatibile" "$(head -2 "$WORK/bashisms")"
    else ok "nessun costrutto bash-only"; fi

    [ -x "$INSTALL_SH" ] && ok "install.sh eseguibile nel repo" \
        || fail "install.sh eseguibile nel repo" "bit x" "manca il bit x"

    "$INSTALL_SH" --help > "$WORK/out" 2>&1
    [ $? -eq 0 ] && grep -qi "curl" "$WORK/out" && ok "--help mostra la riga di installazione" \
        || fail "--help mostra la riga di installazione" "exit 0 con esempio curl" "exit $?"

    "$INSTALL_SH" --argomento-inesistente > "$WORK/out" 2>&1
    [ $? -ne 0 ] && ok "argomento ignoto rifiutato" || fail "argomento ignoto rifiutato" "exit != 0" "exit 0"

    # --dry-run non deve scrivere nulla
    D="$(mktemp -d)/prefix"
    ( cd "$REPO_DIR" && sh install.sh --prefix "$D" --dry-run ) > "$WORK/out" 2>&1
    [ -e "$D/pi-conf.sh" ] && fail "--dry-run non scrive" "prefix vuota" "file creato" \
        || ok "--dry-run non scrive"

    # installazione reale da checkout locale
    D="$(mktemp -d)/prefix"
    ( cd "$REPO_DIR" && sh install.sh --prefix "$D" ) > "$WORK/out" 2>&1
    [ -f "$D/pi-conf.sh" ] && ok "installa pi-conf.sh" || fail "installa pi-conf.sh" "$D/pi-conf.sh" "assente"
    [ -f "$D/pi-conf.ps1" ] && ok "installa pi-conf.ps1" || fail "installa pi-conf.ps1" "$D/pi-conf.ps1" "assente"
    [ -x "$D/pi-conf.sh" ] && ok "pi-conf.sh eseguibile" || fail "pi-conf.sh eseguibile" "bit x" "non eseguibile"

    # lo script installato deve funzionare: prova che i due percorsi concordino
    F="$WORK/s12-installed.json"
    if PI_CONF_FILE="$F" "$D/pi-conf.sh" add --endpoint https://api.server.example \
        --api anthropic --model MLR-3 --key-env K --yes >/dev/null 2>&1 \
        && [ "$(jq -r '.providers["mlr-3"].apiKey' "$F" 2>/dev/null)" = '$K' ]; then
        ok "lo script installato funziona"
    else fail "lo script installato funziona" "apiKey \$K" "vedi $WORK/out"; fi

    # checksum alterato => l'installer deve rifiutarsi
    if [ -f "$SUMS" ]; then
        SRC="$(mktemp -d)"
        cp "$REPO_DIR/install.sh" "$REPO_DIR/pi-conf.sh" "$REPO_DIR/pi-conf.ps1" "$SUMS" "$SRC/"
        printf '\n# alterato per il test\n' >> "$SRC/pi-conf.sh"
        D="$(mktemp -d)/prefix"
        ( cd "$SRC" && sh install.sh --prefix "$D" ) > "$WORK/out" 2>&1
        if [ $? -ne 0 ] && grep -qi "checksum" "$WORK/out"; then
            ok "checksum alterato => installazione rifiutata"
        else fail "checksum alterato => installazione rifiutata" "exit != 0 con messaggio checksum" "$(head -2 "$WORK/out")"; fi
        [ -e "$D/pi-conf.sh" ] && fail "niente installato dopo il rifiuto" "prefix vuota" "file creato" \
            || ok "niente installato dopo il rifiuto"

        # --no-verify deve lasciar passare
        D="$(mktemp -d)/prefix"
        ( cd "$SRC" && sh install.sh --prefix "$D" --no-verify ) > "$WORK/out" 2>&1
        [ -f "$D/pi-conf.sh" ] && ok "--no-verify e' un escape hatch" \
            || fail "--no-verify e' un escape hatch" "installa comunque" "non ha installato"
    else
        echo "  (SHA256SUMS assente: verifica non testata)"
    fi

    # passthrough: installa e configura nella stessa invocazione.
    # PI_CONF_FILE e' obbligatorio qui: senza, pi-conf.sh scriverebbe sul
    # models.json reale dell'utente.
    D="$(mktemp -d)/prefix"
    F="$WORK/s12-passthrough.json"
    ( cd "$REPO_DIR" && PI_CONF_FILE="$F" sh install.sh --prefix "$D" -- \
        --endpoint https://api.server.example --api anthropic \
        --model MLR-3 --key-env MLR_KEY --yes ) > "$WORK/out" 2>&1
    assert_jq "passthrough configura il provider" "$F" '.providers["mlr-3"].apiKey' '$MLR_KEY'
fi

echo

# --- guardia finale: la configurazione reale non deve essere cambiata -------
echo "§13 guardia configurazione reale"
REAL_CONF_AFTER="$(conf_sig)"
if [[ "$REAL_CONF_BEFORE" == "$REAL_CONF_AFTER" ]]; then
    ok "la configurazione reale non e' stata toccata ($REAL_CONF)"
else
    fail "la configurazione reale non e' stata toccata" "invariata" \
         "MODIFICATA: $REAL_CONF (prima $REAL_CONF_BEFORE, dopo $REAL_CONF_AFTER)"
fi
echo

# --- summary ----------------------------------------------------------------
echo "--------------------------------------------"
printf 'passati: %d   falliti: %d\n' "$PASS" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "RISULTATO: FALLITO"
    exit 1
fi
echo "RISULTATO: OK"
exit 0
