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
    [switch]$Help,
    # Tutto il resto della riga di comando, per la modalita' non interattiva.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
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
  7. Context window (default 512000)
  8. Max output tokens (default 32768)

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

function Merge-Model {
    # Un modello esistente viene aggiornato campo per campo. Il `cost` viene
    # mantenuto: lo script scrive sempre zero, che azzererebbero un prezzo
    # configurato a mano.
    param($Old, $New)
    $res = [ordered]@{}
    foreach ($p in $Old.PSObject.Properties) { $res[$p.Name] = $p.Value }
    foreach ($k in $New.Keys)             { $res[$k] = $New[$k] }
    if ($Old.PSObject.Properties.Name -contains 'cost') { $res['cost'] = $Old.cost }
    return ($res | ConvertFrom-Json)
}

function Merge-Provider {
    # Merge non distruttivo: i campi assenti in $New restano quelli di $Old
    # (apiKey, promptCache, headers, compat), i modelli sono uniti per id in
    # posizione, quindi un id nuovo non cancella gli altri.
    param($Old, $New)
    $merged = [ordered]@{}
    if ($Old) {
        foreach ($p in $Old.PSObject.Properties) { $merged[$p.Name] = $p.Value }
    }
    foreach ($k in $New.Keys) { $merged[$k] = $New[$k] }

    $oldModels = @()
    if ($Old -and ($Old.PSObject.Properties.Name -contains 'models') -and $Old.models) {
        $oldModels = @($Old.models)
    }
    $newModel = $New['models'][0]
    $newId    = $newModel['id']

    $outModels = @()
    $found = $false
    foreach ($m in $oldModels) {
        if ($m.id -eq $newId) {
            $outModels += ,(Merge-Model -Old $m -New $newModel)
            $found = $true
        } else {
            $outModels += ,$m
        }
    }
    if (-not $found) { $outModels += ,($newModel | ConvertFrom-Json) }

    $merged['models'] = $outModels
    return $merged
}

function Mask-ApiKey {
    # Copia con apiKey mascherata, per l'anteprima. Il valore in chiaro resta
    # solo nel file scritto.
    param($Provider)
    if ($null -eq $Provider) { return $null }
    $copy = $Provider | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    if (($copy.PSObject.Properties.Name -contains 'apiKey') -and $copy.apiKey) {
        $k = [string]$copy.apiKey
        $copy.apiKey = if ($k.Length -le 4) { '••••' } else { '••••••••' + $k.Substring($k.Length - 4) }
    }
    return $copy
}

function Save-ConfigBackup {
    # Copia della versione corrente prima di ogni scrittura. $false se il file
    # non esiste (niente da conservare) o se la copia fallisce.
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $true }
    try {
        Copy-Item -Path $Path -Destination "$Path.bak" -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "Errore: impossibile creare il backup in $Path.bak" -ForegroundColor Red
        return $false
    }
}

function Show-AddUsage {
    @"
pi-conf.ps1 add - scrive un profilo provider senza porre domande

Uso:
  .\pi-conf.ps1 add -Endpoint <url> -Model <id> [opzioni]
  .\pi-conf.ps1      -Endpoint <url> -Model <id> [opzioni]   # 'add' implicito

Opzioni:
  -Endpoint <url>       endpoint base (obbligatorio, salvo -FromFile)
  -Api <nome>           anthropic|openai|responses|google|mistral|bedrock|
                        vertex|codex|azure|<raw>        (default: anthropic)
  -Model <id>           model id, es. MLR-3              (obbligatorio, salvo -FromFile)
  -Profile <nome>       nome provider in pi (default: model id sanitizzato)
  -Key <valore>         chiave in chiaro (sconsigliato)
  -KeyEnv <NOME>        scrive "apiKey": "`$NOME": pi la risolve a richiesta
  -Reasoning            reasoning esteso (default)
  -NoReasoning          disattiva il reasoning
  -Context <n>          context window      (default: 512000)
  -MaxTokens <n>        max output tokens   (default: 32768)
  -FromFile <json>      valori mancanti da un JSON
  -Config <path>        models.json da scrivere
  -DryRun               stampa l'anteprima e non scrive
  -PrintConfig          stampa la configurazione risultante su stdout

Esempio:
  .\pi-conf.ps1 add -Endpoint https://api.server.example -Api anthropic `
    -Model MLR-3 -KeyEnv MLR_API_KEY
"@
}

function Get-AddOptions {
    # Parsing della riga di comando non interattiva.
    # Restituisce un hashtable, oppure `$null` se non serve la modalita' add.
    # Accetta sia le forme lunghe GNU (`--endpoint URL`) sia quelle corte
    # PowerShell (`-Endpoint URL`).
    $triggers = @('add','--endpoint','-endpoint','--api','-api','--model','-model',
                  '--profile','-profile','--key','-key','--key-env','-keyenv',
                  '--reasoning','--no-reasoning','-noreasoning',
                  '--context','-context','--max-tokens','-maxtokens',
                  '--from-file','-fromfile','--config','-config',
                  '--dry-run','--print-config','-printconfig','--yes','-y')
    $long = @('--endpoint','--api','--model','--profile','--key','--key-env',
              '--context','--max-tokens','--from-file','--config')

    $isAdd = $false
    foreach ($a in $Args) {
        if ($triggers -contains $a) { $isAdd = $true; break }
        $name = ($a -split '=', 2)[0]
        if ($triggers -contains $name) { $isAdd = $true; break }
    }
    if (-not $isAdd) { return $null }

    # normalizza "-Endpoint URL" / "--endpoint URL" in "-Endpoint=URL"
    $norm = @()
    $i = 0
    while ($i -lt $Args.Count) {
        $a = $Args[$i]
        $isFlag = $false
        foreach ($t in $triggers) { if ($a -eq $t) { $isFlag = $true } }
        if ($isFlag) { $norm += $a; $i++; continue }
        if ($a -match '^--?[A-Za-z-]+$' -and ($i + 1) -lt $Args.Count) {
            $norm += "$a=$($Args[$i + 1])"; $i += 2; continue
        }
        $norm += $a; $i++
    }

    $o = @{
        endpoint = $null; api = 'anthropic'; model = $null; profile = $null
        key = $null;     keyEnv = $null; reasoning = 'y'
        context = $null; maxTokens = $null
        fromFile = $null; config = $null
        dryRun = $false; printConfig = $false
    }

    foreach ($a in $norm) {
        $k = $a; $v = $null
        if ($a -match '^(.+?)=(.*)$') { $k = $Matches[1]; $v = $Matches[2] }
        switch ($k.ToLower()) {
            'add'            { }
            '--reasoning'    { $o.reasoning = 'y' }
            '--no-reasoning' { $o.reasoning = 'n' }
            '--dry-run'      { $o.dryRun = $true }
            '--print-config' { $o.printConfig = $true }
            '--yes'          { }
            '--endpoint'     { $o.endpoint   = $v }
            '--api'          { $o.api        = $v }
            '--model'        { $o.model      = $v }
            '--profile'      { $o.profile    = $v }
            '--key'          { $o.key        = $v }
            '--key-env'      { $o.keyEnv     = $v }
            '--context'      { $o.context    = $v }
            '--max-tokens'   { $o.maxTokens  = $v }
            '--from-file'    { $o.fromFile   = $v }
            '--config'       { $o.config     = $v }
            default {
                Write-Host "Errore: argomento sconosciuto: $k" -ForegroundColor Red
                Show-AddUsage | Out-Null
                return $null
            }
        }
    }
    return $o
}

function Invoke-Add {
    param([hashtable]$O)

    if ($O.fromFile) {
        if (-not (Test-Path $O.fromFile)) {
            Write-Host "Errore: --from-file '$($O.fromFile)' non esiste" -ForegroundColor Red
            return 1
        }
        try { $f = Get-Content $O.fromFile -Raw | ConvertFrom-Json }
        catch {
            Write-Host "Errore: --from-file '$($O.fromFile)' non e' JSON valido" -ForegroundColor Red
            return 1
        }
        if (-not $O.endpoint)   { $O.endpoint   = $f.endpoint }
        if ($O.api -eq 'anthropic' -and $f.PSObject.Properties.Name -contains 'api') { $O.api = $f.api }
        if (-not $O.model)     { $O.model      = $f.model }
        if (-not $O.profile)   { $O.profile    = $f.profile }
        if (-not $O.keyEnv)    { $O.keyEnv     = $f.keyEnv }
        if (-not $O.context)   { $O.context    = $f.context }
        if (-not $O.maxTokens) { $O.maxTokens  = $f.maxTokens }
        if (($f.PSObject.Properties.Name -contains 'reasoning') -and $f.reasoning -eq $false -and $O.reasoning -eq 'y') {
            $O.reasoning = 'n'
        }
    }

    if (-not $O.endpoint) {
        Write-Host "Errore: manca --endpoint (obbligatorio)" -ForegroundColor Red
        return 1
    }
    if ($O.endpoint -notmatch '^https?://') {
        Write-Host "Errore: endpoint non valido: deve iniziare con http:// o https://" -ForegroundColor Red
        return 1
    }
    if (-not $O.model) {
        Write-Host "Errore: manca --model (obbligatorio)" -ForegroundColor Red
        return 1
    }
    if ($O.key -and $O.keyEnv) {
        Write-Host "Errore: --key e --key-env sono incompatibili: scegline uno" -ForegroundColor Red
        return 1
    }

    $profile = $O.profile
    if (-not $profile) {
        $profile = Get-SanitizedName $O.model
        if (-not $profile) { $profile = 'custom-provider' }
    }
    if ($profile -notmatch '^[a-zA-Z0-9_-]+$') {
        Write-Host "Errore: nome profilo '$profile' non valido (usa solo [a-zA-Z0-9_-])" -ForegroundColor Red
        return 1
    }

    $ctx = if ($O.context)   { $O.context }   else { '512000' }
    $max = if ($O.maxTokens) { $O.maxTokens } else { '32768' }
    if ("$ctx" -notmatch '^\d+$') {
        Write-Host "Errore: --context deve essere un intero" -ForegroundColor Red
        return 1
    }
    if ("$max" -notmatch '^\d+$') {
        Write-Host "Errore: --max-tokens deve essere un intero" -ForegroundColor Red
        return 1
    }

    # -KeyEnv scrive il riferimento "$NOME": pi interpola l'env var a richiesta,
    # quindi la chiave non finisce mai in chiaro nel file.
    $apiKey = ''
    if ($O.keyEnv) {
        if ($O.keyEnv -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            Write-Host "Errore: --key-env '$($O.keyEnv)' non e' un nome di variabile valido" -ForegroundColor Red
            return 1
        }
        $apiKey = '$' + $O.keyEnv
    } elseif ($O.key) {
        $apiKey = $O.key
    }

    $reasoningBool = if ($O.reasoning -eq 'y') { $true } else { $false }

    $provider = [ordered]@{
        baseUrl = $O.endpoint
        api     = (Map-Standard $O.api)
    }
    if ($apiKey -ne '') { $provider['apiKey'] = $apiKey }
    $provider['models'] = @([ordered]@{
        id            = $O.model
        name          = $O.model
        reasoning     = $reasoningBool
        input         = @('text')
        contextWindow = [int]$ctx
        maxTokens     = [int]$max
        cost          = [ordered]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
    })
    $pjson = $provider | ConvertTo-Json -Depth 10

    if ($O.dryRun) {
        Write-Host "ANTEPRIMA (dry-run, nulla scritto in $PiConfFile)"
        (Mask-ApiKey -Provider ($pjson | ConvertFrom-Json)) | ConvertTo-Json -Depth 10
        return 0
    }

    if ($O.printConfig) {
        $base = [PSCustomObject]@{ providers = [PSCustomObject]@{} }
        if (Test-Path $PiConfFile) { $base = Get-Content $PiConfFile -Raw -Encoding UTF8 | ConvertFrom-Json }
        $oldProvider = $null
        if (($base.PSObject.Properties.Name -contains 'providers') -and $base.providers -and
            ($base.providers.PSObject.Properties.Name -contains $profile)) {
            $oldProvider = $base.providers.$profile
        }
        $merged = Merge-Provider -Old $oldProvider -New $provider
        $providers = [ordered]@{}
        if ($base.providers) {
            foreach ($pr in $base.providers.PSObject.Properties) { $providers[$pr.Name] = $pr.Value }
        }
        $providers[$profile] = ($merged | ConvertFrom-Json)
        [PSCustomObject]@{ providers = $providers } | ConvertTo-Json -Depth 10
        return 0
    }

    # Carica esistente: se il file non e' parsabile si abortisce senza scrivere,
    # stesso comportamento di pi-conf.sh.
    $existingObj = [PSCustomObject]@{ providers = [PSCustomObject]@{} }
    if (Test-Path $PiConfFile) {
        try {
            $raw = Get-Content $PiConfFile -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                if (($parsed.PSObject.Properties.Name -contains 'providers') -and $parsed.providers) {
                    $existingObj = $parsed
                }
            }
        } catch {
            Write-Host "Errore: $PiConfFile non parsabile - $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Nessuna scrittura effettuata. Correggi o sposta il file, poi rilancia." -ForegroundColor Red
            return 1
        }
    }

    if (-not (Save-ConfigBackup -Path $PiConfFile)) { return 1 }

    if (-not ($existingObj.PSObject.Properties.Name -contains 'providers')) {
        $existingObj | Add-Member -NotePropertyName 'providers' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if (-not $existingObj.providers) { $existingObj.providers = [PSCustomObject]@{} }

    $oldProvider = $null
    if ($existingObj.providers.PSObject.Properties.Name -contains $profile) {
        $oldProvider = $existingObj.providers.$profile
    }
    $merged = Merge-Provider -Old $oldProvider -New $provider

    if ($existingObj.providers.PSObject.Properties.Name -contains $profile) {
        $existingObj.providers.$profile = ($merged | ConvertFrom-Json)
    } else {
        $existingObj.providers | Add-Member -NotePropertyName $profile -NotePropertyValue ($merged | ConvertFrom-Json) -Force
    }

    $existingObj | ConvertTo-Json -Depth 10 | Set-Content -Path $PiConfFile -Encoding UTF8

    Write-Host ""
    Write-Host "OK - provider '$profile' salvato in $PiConfFile"
    if ($O.keyEnv) {
        Write-Host "     apiKey: letta dall'env var $($O.keyEnv) (non scritta in chiaro)"
    }
    return 0
}

# --- Main -------------------------------------------------------------------

if ($Help) {
    Show-Usage
    exit 0
}

Write-Host "pi-conf.ps1 — creazione profilo provider per pi-code"
Write-Host "=================================================="

# Percorso non interattivo: richiesto esplicitamente o implicito da un flag.
$addOpts = Get-AddOptions -Args $Rest
if ($addOpts) {
    if ($addOpts.config) { $PiConfFile = $addOpts.config }
    exit (Invoke-Add -O $addOpts)
}

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
$ContextWindowStr = Get-PromptInput "7/8  Context window (tokens)" "512000"
if ($ContextWindowStr -notmatch '^\d+$') {
    Write-Host "Errore: deve essere un intero" -ForegroundColor Red
    exit 1
}
$ContextWindow = [int]$ContextWindowStr

# 8. Max output tokens
Write-Host ""
$MaxTokensStr = Get-PromptInput "8/8  Max output tokens" "32768"
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
(Mask-ApiKey -Provider ($provider | ConvertTo-Json -Depth 10 | ConvertFrom-Json)) | ConvertTo-Json -Depth 10
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
        # Non ripartire da vuoto: sovrascrivere un file non parsabile
        # cancellerebbe tutto il suo contenuto. Stesso comportamento di bash.
        Write-Host "Errore: $PiConfFile non parsabile - $_.Exception.Message" -ForegroundColor Red
        Write-Host "Nessuna scrittura effettuata. Correggi o sposta il file, poi rilancia." -ForegroundColor Red
        exit 1
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
    Write-Host "(!) Esiste gia' un provider '$ProfileName' - verra' aggiornato" -ForegroundColor Yellow
    Write-Host "    I campi che lo script non gestisce (apiKey, promptCache, headers, compat,"
    Write-Host "    cost personalizzati) e gli eventuali modelli aggiuntivi vengono conservati."
    Write-Host "    Viene creato un backup in $PiConfFile.bak"
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

# Backup della versione corrente prima di scrivere
if (-not (Save-ConfigBackup -Path $PiConfFile)) { exit 1 }

# Merge: aggiungi o aggiorna il provider senza perdere i campi non gestiti
if (-not ($existingObj.PSObject.Properties.Name -contains 'providers')) {
    $existingObj | Add-Member -NotePropertyName 'providers' -NotePropertyValue ([PSCustomObject]@{}) -Force
}
if (-not $existingObj.providers) {
    $existingObj.providers = [PSCustomObject]@{}
}

$oldProvider = $null
if ($existingObj.providers.PSObject.Properties.Name -contains $ProfileName) {
    $oldProvider = $existingObj.providers.$ProfileName
}
$mergedProvider = Merge-Provider -Old $oldProvider -New $provider

if ($existingObj.providers.PSObject.Properties.Name -contains $ProfileName) {
    $existingObj.providers.$ProfileName = ($mergedProvider | ConvertFrom-Json)
} else {
    $existingObj.providers | Add-Member -NotePropertyName $ProfileName -NotePropertyValue ($mergedProvider | ConvertFrom-Json) -Force
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
