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
if grep -q 'providers\.\$ProfileName = \$providerObj' "$CONF_PS1"; then
    fail "sovrascrittura grezza rimossa" "assente" "presente: providers.\$ProfileName = \$providerObj"
else ok "sovrascrittura grezza rimossa"; fi
if grep -q 'function Merge-Provider' "$CONF_PS1"; then ok "helper Merge-Provider presente"
else fail "helper Merge-Provider presente" "function Merge-Provider" "assente"; fi
if grep -q 'function Mask-ApiKey' "$CONF_PS1"; then ok "helper Mask-ApiKey presente"
else fail "helper Mask-ApiKey presente" "function Mask-ApiKey" "assente"; fi
if grep -q 'function Save-ConfigBackup' "$CONF_PS1"; then ok "helper Save-ConfigBackup presente"
else fail "helper Save-ConfigBackup presente" "function Save-ConfigBackup" "assente"; fi
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
