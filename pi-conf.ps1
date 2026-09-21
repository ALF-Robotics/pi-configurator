#!/usr/bin/env pwsh
# pi-conf.ps1 — versione Windows PowerShell di pi-configurator.
# Crea un profilo provider custom per pi-code (pi-coding-agent).
#
# Uso:  .\pi-conf.ps1           (interattivo)
#       .\pi-conf.ps1 -Help
#
# Compatibile con PowerShell 5.1 (Windows PowerShell, default su Win10/11)
# e PowerShell 7+ (pwsh).

[CmdletBinding()]
param(
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# --- Config -----------------------------------------------------------------

# Path del file di configurazione di pi.
# Override con env PI_CONF_FILE oppure PI_CODING_AGENT_DIR.
$PiConfFile = $env:PI_CONF_FILE
if (-not $PiConfFile) {
    if ($env:PI_CODING_AGENT_DIR) {
        $PiConfFile = Join-Path $env:PI_CODING_AGENT_DIR 'models.json'
    } else {
        $PiConfFile = Join-Path $env:USERPROFILE '.pi\agent\models.json'
    }
}

# Path del binario pi (per auth check finale).
$PiBin = $env:PI_BIN
if (-not $PiBin) {
    $piCmd = Get-Command pi -ErrorAction SilentlyContinue
    if ($piCmd) {
        $PiBin = $piCmd.Path
    } else {
        $PiBin = 'pi'
    }
}

# --- Helpers ----------------------------------------------------------------

function Show-Usage {
    @"
pi-conf.ps1 (Windows) — crea un profilo provider custom per pi-code

Uso:
  .\pi-conf.ps1 [-Help]

Senza argomenti, lo script e' interattivo e chiede in ordine:
  1. Endpoint URL              (es. https://api.server.example)
  2. Standard API              (anthropic, openai, google, mistral, ...)
  3. Model ID                  (es. MLR-3, claude-sonnet-4-5)
  4. Nome del profilo          (provider name in pi)
  5. API key                   (opzionale: vuoto = configura dopo con /login)
  6. Reasoning? (y/N)
  7. Context window (default 200000)
  8. Max output tokens (default 16384)

Scrive/aggiorna: $PiConfFile (merge con eventuali provider esistenti).

Per usarlo dopo:
  pi --provider <nome> --model <modello>
oppure in TUI: /model

NOTE Windows:
  - NTFS gestisce gli ACL per-file: il file models.json sara' accessibile
    solo al tuo utente per default.
  - pi su Windows cerca automaticamente pi.cmd/pi.exe; stesso comportamento
    su entrambi i binary.
"@
}

function Map-Standard {
    param([string]$Input_)
    switch -Regex ($Input_) {
        '^(anthropic|claude)$'        { return 'anthropic-messages' }
        '^(openai|gpt)$'              { return 'openai-completions' }
        '^(responses|openai-responses)$' { return 'openai-responses' }
        '^(google|gemini)$'           { return 'google-generative-ai' }
        '^mistral$'                   { return 'mistral-conversations' }
        '^bedrock$'                   { return 'bedrock-converse-stream' }
        '^vertex$'                    { return 'google-vertex' }
        '^codex$'                     { return 'openai-codex-responses' }
        '^azure$'                     { return 'azure-openai-responses' }
        default                       { return $Input_ }
    }
}

function Get-PromptInput {
    param(
        [string]$Label,
        [string]$Default = ''
    )
    if ($Default) {
        Write-Host -NoNewline ("$Label [$Default]: ")
        $value = Read-Host
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
    } else {
        while ($true) {
            Write-Host -NoNewline "$Label`: "
            $value = Read-Host
            if (-not [string]::IsNullOrWhiteSpace($value)) { break }
            Write-Host "  (!) richiesto" -ForegroundColor Yellow
        }
    }
    return $value
}

# Legge un secret mostrando '*' per ogni carattere (anche durante paste).
# Usa [Console]::ReadKey per controllo char-by-char.
function Read-SecretWithStars {
    param([string]$Prompt)
    Write-Host -NoNewline $Prompt
    $value = ''
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        if ($key.Key -eq 'Enter') {
            Write-Host ''
            break
        }
        if ($key.Key -eq 'Backspace') {
            if ($value.Length -gt 0) {
                $value = $value.Substring(0, $value.Length - 1)
                Write-Host -NoNewline "`b `b"
            }
            continue
        }
        # Ignora altri tasti di controllo
        if ($key.Character -lt ([char]32)) { continue }
        $value += $key.Character
        Write-Host -NoNewline '*'
    }
    return $value
}

function Get-PromptYN {
    param(
        [string]$Label,
        [string]$Default = 'y'
    )
    $suffix = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-Host -NoNewline "$Label $suffix`: "
        $value = Read-Host
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        switch ($value.ToLower().Trim()) {
            'y'     { return 'y' }
            'yes'   { return 'y' }
            'n'     { return 'n' }
            'no'    { return 'n' }
            default { Write-Host "  (!) rispondi y o n" -ForegroundColor Yellow }
        }
    }
}

function Get-SanitizedName {
    param([string]$Name)
    $lower = $Name.ToLower()
    $cleaned = [regex]::Replace($lower, '[^a-z0-9-]+', '-')
    $trimmed = [regex]::Replace($cleaned, '^-+|-+$', '')
    if ([string]::IsNullOrEmpty($trimmed)) { return 'custom-provider' }
    return $trimmed
}

# --- Main -------------------------------------------------------------------

if ($Help) {
    Show-Usage
    exit 0
}

Write-Host "pi-conf.ps1 — creazione profilo provider per pi-code"
Write-Host "=================================================="
Write-Host "Config: $PiConfFile"
Write-Host "Binario pi: $PiBin"
Write-Host ""

# 1. Endpoint
$Endpoint = Get-PromptInput "1/8  Endpoint URL (es. https://api.server.example)"
if ($Endpoint -notmatch '^https?://') {
    Write-Host "Errore: endpoint non valido (deve iniziare con http:// o https://)" -ForegroundColor Red
    exit 1
}

# 2. Standard
Write-Host ""
Write-Host "2/8  Standard API - scegli tra:"
Write-Host "      anthropic  -> anthropic-messages   (Claude, modelli Anthropic-compat)"
Write-Host "      openai     -> openai-completions    (GPT-4, /v1/chat/completions)"
Write-Host "      responses  -> openai-responses      (OpenAI Responses API)"
Write-Host "      google     -> google-generative-ai  (Gemini)"
Write-Host "      mistral    -> mistral-conversations"
Write-Host "      bedrock    -> bedrock-converse-stream (AWS Bedrock)"
Write-Host "      vertex     -> google-vertex         (GCP Vertex)"
Write-Host "      codex      -> openai-codex-responses"
Write-Host "      azure      -> azure-openai-responses"
Write-Host "      <raw>      -> nome API pi passato tal quale"
$StandardInput = Get-PromptInput "      Standard" "anthropic"
$StandardApi = Map-Standard $StandardInput
Write-Host "      -> mappato a: $StandardApi"

# 3. Modello
Write-Host ""
$ModelId = Get-PromptInput "3/8  Model ID (es. MLR-3, claude-sonnet-4-5)"

# 4. Nome profilo
$Suggested = Get-SanitizedName $ModelId
Write-Host ""
$ProfileName = Get-PromptInput "4/8  Nome del profilo (provider name in pi)" $Suggested
if ($ProfileName -notmatch '^[a-zA-Z0-9_-]+$') {
    Write-Host "Errore: nome '$ProfileName' non valido (usa solo [a-zA-Z0-9_-])" -ForegroundColor Red
    exit 1
}

# 5. API key (con stelle in tempo reale)
Write-Host ""
$ApiKey = Read-SecretWithStars "5/8  API key (vuoto = salta, configura dopo con /login): "
if ([string]::IsNullOrEmpty($ApiKey)) {
    Write-Host "      (saltata - configura dopo con: /login $ProfileName, oppure imposta env var, oppure edita $PiConfFile)"
}

# 6. Reasoning
Write-Host ""
$ReasoningChoice = Get-PromptYN "6/8  Modello con reasoning esteso?" "y"
$ReasoningBool = if ($ReasoningChoice -eq 'y') { $true } else { $false }

# 7. Context window
Write-Host ""
$ContextWindowStr = Get-PromptInput "7/8  Context window (tokens)" "200000"
if ($ContextWindowStr -notmatch '^\d+$') {
    Write-Host "Errore: deve essere un intero" -ForegroundColor Red
    exit 1
}
$ContextWindow = [int]$ContextWindowStr

# 8. Max output tokens
Write-Host ""
$MaxTokensStr = Get-PromptInput "8/8  Max output tokens" "16384"
if ($MaxTokensStr -notmatch '^\d+$') {
    Write-Host "Errore: deve essere un intero" -ForegroundColor Red
    exit 1
}
$MaxTokens = [int]$MaxTokensStr

# Costruisci provider come PSCustomObject (ordinato)
$provider = [ordered]@{
    baseUrl = $Endpoint
    api     = $StandardApi
}
if (-not [string]::IsNullOrEmpty($ApiKey)) {
    $provider.apiKey = $ApiKey
}

$cost = [ordered]@{
    input      = 0
    output     = 0
    cacheRead  = 0
    cacheWrite = 0
}

$model = [ordered]@{
    id            = $ModelId
    name          = $ModelId
    reasoning     = $ReasoningBool
    input         = @('text')
    contextWindow = $ContextWindow
    maxTokens     = $MaxTokens
    cost          = $cost
}
$provider.models = @($model)

$ProviderJson = $provider | ConvertTo-Json -Depth 10

# Preview
Write-Host ""
Write-Host "----------------------------------------------------------"
Write-Host "ANTEPRIMA - verra' scritto in $PiConfFile"
Write-Host "----------------------------------------------------------"
Write-Host "Profilo: $ProfileName"
$provider | ConvertTo-Json -Depth 10
Write-Host "----------------------------------------------------------"

# Crea directory se non esiste
$confDir = Split-Path -Parent $PiConfFile
if (-not (Test-Path $confDir)) {
    New-Item -ItemType Directory -Path $confDir -Force | Out-Null
}

# Carica esistente (o vuoto)
$existingObj = [PSCustomObject]@{ providers = [PSCustomObject]@{} }
if (Test-Path $PiConfFile) {
    try {
        $raw = Get-Content $PiConfFile -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.PSObject.Properties.Name -contains 'providers') {
                if ($parsed.providers) {
                    $existingObj = $parsed
                }
            }
        }
    } catch {
        Write-Host "Avviso: $PiConfFile non parsabile, parto da vuoto" -ForegroundColor Yellow
    }
}

# Check esistente
$providerExists = $false
if ($existingObj.PSObject.Properties.Name -contains 'providers' -and $existingObj.providers) {
    if ($existingObj.providers.PSObject.Properties.Name -contains $ProfileName) {
        $providerExists = $true
    }
}

if ($providerExists) {
    Write-Host ""
    Write-Host "(!) Esiste gia' un provider '$ProfileName' - verra' sovrascritto" -ForegroundColor Yellow
    $overwrite = Get-PromptYN "     Procedere?" "n"
    if ($overwrite -ne 'y') {
        Write-Host "Annullato."
        exit 0
    }
}

# Conferma finale
Write-Host ""
$confirm = Get-PromptYN "Confermi scrittura?" "y"
if ($confirm -ne 'y') {
    Write-Host "Annullato."
    exit 0
}

# Merge: aggiungi il nuovo provider al dict providers
if (-not ($existingObj.PSObject.Properties.Name -contains 'providers')) {
    $existingObj | Add-Member -NotePropertyName 'providers' -NotePropertyValue ([PSCustomObject]@{}) -Force
}
if (-not $existingObj.providers) {
    $existingObj.providers = [PSCustomObject]@{}
}

# Converti provider PSCustomObject per l'assegnazione
$providerObj = $provider | ConvertFrom-Json

if ($existingObj.providers.PSObject.Properties.Name -contains $ProfileName) {
    $existingObj.providers.$ProfileName = $providerObj
} else {
    $existingObj.providers | Add-Member -NotePropertyName $ProfileName -NotePropertyValue $providerObj -Force
}

# Salva
$existingObj | ConvertTo-Json -Depth 10 | Set-Content -Path $PiConfFile -Encoding UTF8

Write-Host ""
Write-Host "OK - provider '$ProfileName' salvato"
Write-Host "     File: $PiConfFile"
Write-Host ""
Write-Host "Per usarlo:"
Write-Host "  pi --provider '$ProfileName' --model '$ModelId'"
Write-Host "oppure in TUI: /model"

# Verifica
Write-Host ""
Write-Host "Verifica auth:"
$piAvailable = $false
try {
    $cmd = Get-Command $PiBin -ErrorAction Stop
    $piAvailable = $true
} catch {
    $piAvailable = $false
}
if ($piAvailable) {
    try {
        & $PiBin auth check --provider $ProfileName --json 2>&1 | Out-Host
    } catch {
        Write-Host "(auth check fallito - verifica manualmente con: pi auth check --provider $ProfileName)" -ForegroundColor Yellow
    }
} else {
    Write-Host "(binario pi non trovato in $PiBin - verifica saltata)" -ForegroundColor Yellow
}
