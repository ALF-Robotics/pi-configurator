#!/usr/bin/env pwsh
# tests/pi-conf-ps1-test.ps1 — behavioural tests for pi-conf.ps1
#
# These tests EXECUTE pi-conf.ps1. Until v0.4.1 the PowerShell script was
# only covered by static tripwires, so a broken argument parser (every
# non-interactive form failed with "argomento sconosciuto") and a lost
# `input` field went unnoticed.
#
# Run: pwsh -NoProfile -File tests/pi-conf-ps1-test.ps1
# Exit code 0 = all green, 1 = at least one failure.
#
# Every test runs the script in a child process with PI_CONF_FILE pointing to
# a throwaway file: the real ~/.pi/agent/models.json is never touched.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$Script  = Join-Path $RepoDir 'pi-conf.ps1'
$Pwsh    = (Get-Process -Id $PID).Path

if (-not (Test-Path $Script)) {
    Write-Host "pi-conf.ps1 non trovato in $Script"
    exit 1
}

$script:Pass = 0
$script:Fail = 0

function ok   { $script:Pass++; Write-Host "  ok   $args" }
function fail {
    $script:Fail++
    Write-Host "  FAIL $args[0]"
    Write-Host "         atteso: $args[1]"
    Write-Host "         attuale: $args[2]"
}

# assert_match <nome> <testo> <regex atteso>
function assert_match {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) { ok $Name } else { fail $Name $Pattern ($Text -replace '\s+', ' ').Substring(0, [Math]::Min(400, ($Text -replace '\s+', ' ').Length)) }
}

# assert_not_match <nome> <testo> <regex NON atteso>
function assert_not_match {
    param([string]$Name, [string]$Text, [string]$Pattern)
    if ($Text -notmatch $Pattern) { ok $Name } else { fail $Name "NON $Pattern" ($Text -replace '\s+', ' ').Substring(0, [Math]::Min(400, ($Text -replace '\s+', ' ').Length)) }
}

# assert_eq <nome> <atteso> <attuale>
function assert_eq {
    param([string]$Name, $Expected, $Actual)
    if ("$Expected" -eq "$Actual") { ok $Name } else { fail $Name $Expected $Actual }
}

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("pi-conf-ps1-test-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $Work -Force | Out-Null

function Remove-Work {
    if (Test-Path $Work) { Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue }
}
trap { Remove-Work; break }

# Esegue pi-conf.ps1 in un processo figlio e restituisce output + exit code.
# Il timeout e' essenziale: se lo script ripartisce in modalita' interattiva
# per errore, bloccherebbe la suite per sempre su Read-Host.
#
# Gli argomenti vengono scritti dentro un runner temporaneo e non passati con
# -File: con -File PowerShell divide '--flag=https://...' su ':' e la forma
# con uguale si perde. Con un blocco script la forma resta intera, ed e'
# esattamente la forma della one-liner documentata.
function Invoke-PSConf {
    param([string[]]$ConfArgs, [string]$ConfigFile, [int]$TimeoutMs = 10000)
    $env:PI_CONF_FILE = $ConfigFile
    # PI_BIN inesistente: lo script salta il 'pi auth check' invece di
    # invocare il binario reale.
    $env:PI_BIN = Join-Path $Work 'pi-does-not-exist'

    $quoted = @()
    foreach ($a in $ConfArgs) {
        if ($a -match "[\s']") { $quoted += ("'" + $a.Replace("'", "''") + "'") }
        else { $quoted += $a }
    }

    $runner = Join-Path $Work ("runner-" + [System.IO.Path]::GetRandomFileName() + '.ps1')
    $runnerBody = @"
`$sb = [scriptblock]::Create((Get-Content -Raw '$Script'))
& `$sb $($quoted -join ' ')
exit `$LASTEXITCODE
"@
    Set-Content -Path $runner -Value $runnerBody -Encoding UTF8

    $outFile = Join-Path $Work ("stdout-" + [System.IO.Path]::GetRandomFileName())
    $errFile = Join-Path $Work ("stderr-" + [System.IO.Path]::GetRandomFileName())
    $inFile  = Join-Path $Work 'stdin-empty'
    if (-not (Test-Path $inFile)) { Set-Content -Path $inFile -Value '' -NoNewline }

    $p = Start-Process -FilePath $Pwsh -ArgumentList @('-NoProfile', '-File', $runner) -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile -RedirectStandardInput $inFile
    if (-not $p.WaitForExit($TimeoutMs)) {
        try { $p.Kill() } catch { }
        $text = ((Get-Content $outFile -Raw -ErrorAction SilentlyContinue) + (Get-Content $errFile -Raw -ErrorAction SilentlyContinue))
        return @{ Code = -1; Out = "$text`n[TIMEOUT ${TimeoutMs}ms]" }
    }
    $text = ((Get-Content $outFile -Raw -ErrorAction SilentlyContinue) + (Get-Content $errFile -Raw -ErrorAction SilentlyContinue))
    return @{ Code = $p.ExitCode; Out = $text }
}

function New-ConfFile {
    param([string]$Name)
    $p = Join-Path $Work $Name
    if (Test-Path $p) { Remove-Item -Force $p }
    return $p
}

Write-Host "§A argomenti non interattivi: forme accettate"

# --- A1: forma GNU a doppio trattino -----------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--api', 'anthropic',
    '--model', 'MLR-3', '--key-env', 'MLR_API_KEY', '--yes', '--dry-run'
) -ConfigFile (New-ConfFile 'a1.json')
assert_eq 'A1 GNU: exit code 0' 0 $r.Code
assert_match 'A1 GNU: anteprima' $r.Out 'ANTEPRIMA'
assert_match 'A1 GNU: baseUrl' $r.Out 'https://api\.server\.example'
assert_match 'A1 GNU: api mappata' $r.Out 'anthropic-messages'
assert_match 'A1 GNU: apiKey mascherata' $r.Out '_KEY'
assert_not_match 'A1 GNU: apiKey non in chiaro' $r.Out 'MLR_API_KEY'
assert_match 'A1 GNU: modello' $r.Out 'MLR-3'

# --- A2: forma PowerShell a trattino singolo ---------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '-Endpoint', 'https://api.server.example', '-Api', 'anthropic',
    '-Model', 'MLR-3', '-KeyEnv', 'MLR_API_KEY', '-Yes', '-DryRun'
) -ConfigFile (New-ConfFile 'a2.json')
assert_eq 'A2 PowerShell: exit code 0' 0 $r.Code
assert_match 'A2 PowerShell: baseUrl' $r.Out 'https://api\.server\.example'
assert_match 'A2 PowerShell: apiKey mascherata' $r.Out '_KEY'
assert_not_match 'A2 PowerShell: apiKey non in chiaro' $r.Out 'MLR_API_KEY'

# --- A3: forma con uguale ----------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint=https://api.server.example', '--model=MLR-3', '--dry-run'
) -ConfigFile (New-ConfFile 'a3.json')
assert_eq 'A3 uguale: exit code 0' 0 $r.Code
assert_match 'A3 uguale: baseUrl' $r.Out 'https://api\.server\.example'
assert_match 'A3 uguale: modello' $r.Out 'MLR-3'

# --- A4: la modalita' add e' implicita senza il trigger 'add' ---------------
$r = Invoke-PSConf -ConfArgs @(
    '--endpoint', 'https://api.server.example', '--model', 'MLR-3', '--dry-run'
) -ConfigFile (New-ConfFile 'a4.json')
assert_eq 'A4 implicito: exit code 0' 0 $r.Code
assert_match 'A4 implicito: anteprima' $r.Out 'ANTEPRIMA'

Write-Host "§B errori: devono fermarsi, non ripartire in modalita' interattiva"

# --- B1: argomento sconosciuto -----------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--bogus', 'x', '--dry-run'
) -ConfigFile (New-ConfFile 'b1.json')
assert_match 'B1 sconosciuto: errore' $r.Out 'sconosciuto'
assert_not_match 'B1 sconosciuto: nessuna ripartenza interattiva' $r.Out '1/9'
if ($r.Code -ne 0) { ok 'B1 sconosciuto: exit code non zero' } else { fail 'B1 sconosciuto: exit code non zero' 'diverso da 0' $r.Code }

# --- B2: flag senza valore ----------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--model', 'MLR-3', '--endpoint'
) -ConfigFile (New-ConfFile 'b2.json')
assert_match 'B2 valore mancante: errore' $r.Out 'manca il valore'
assert_not_match 'B2 valore mancante: nessuna ripartenza interattiva' $r.Out '1/9'

# --- B3: endpoint assente -----------------------------------------------------
$r = Invoke-PSConf -ConfArgs @('add', '--model', 'MLR-3', '--dry-run') -ConfigFile (New-ConfFile 'b3.json')
assert_match 'B3 endpoint assente: errore' $r.Out 'manca --endpoint'

# --- B4: model assente --------------------------------------------------------
$r = Invoke-PSConf -ConfArgs @('add', '--endpoint', 'https://api.server.example', '--dry-run') -ConfigFile (New-ConfFile 'b4.json')
assert_match 'B4 model assente: errore' $r.Out 'manca --model'

Write-Host "§C parita' con pi-conf.sh sul campo input"

# --- C1: default multimodale --------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3', '--dry-run'
) -ConfigFile (New-ConfFile 'c1.json')
assert_match 'C1 default: input text' $r.Out '"text"'
assert_match 'C1 default: input image' $r.Out '"image"'

# --- C2: --input text ---------------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--input', 'text', '--dry-run'
) -ConfigFile (New-ConfFile 'c2.json')
assert_match 'C2 solo text: input text' $r.Out '"text"'
assert_not_match 'C2 solo text: niente image' $r.Out '"image"'

# --- C3: --input text,image ---------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--input', 'text,image', '--dry-run'
) -ConfigFile (New-ConfFile 'c3.json')
assert_match 'C3 text,image: input text' $r.Out '"text"'
assert_match 'C3 text,image: input image' $r.Out '"image"'

# --- C4: --input non valido ---------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--input', 'audio', '--dry-run'
) -ConfigFile (New-ConfFile 'c4.json')
assert_match 'C4 input non valido: errore' $r.Out 'accetta solo text e image'

Write-Host "§D valori e scrittura"

# --- D1: --no-reasoning -------------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--no-reasoning', '--dry-run'
) -ConfigFile (New-ConfFile 'd1.json')
assert_match 'D1 no-reasoning: reasoning false' $r.Out '"reasoning":\s*false'

# --- D2: context e max tokens -------------------------------------------------
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--context', '1000000', '--max-tokens', '65536', '--dry-run'
) -ConfigFile (New-ConfFile 'd2.json')
assert_match 'D2 context window' $r.Out '"contextWindow":\s*1000000'
assert_match 'D2 max tokens' $r.Out '"maxTokens":\s*65536'

# --- D3: scrittura reale ------------------------------------------------------
$conf = New-ConfFile 'd3.json'
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--api', 'anthropic',
    '--model', 'MLR-3', '--key-env', 'MLR_API_KEY', '--yes'
) -ConfigFile $conf
assert_eq 'D3 scrittura: exit code 0' 0 $r.Code
if (Test-Path $conf) { ok 'D3 scrittura: file creato' } else { fail 'D3 scrittura: file creato' 'file presente' 'assente' }
if (Test-Path $conf) {
    $w = Get-Content $conf -Raw | ConvertFrom-Json
    assert_eq 'D3 scrittura: provider' 'https://api.server.example' $w.providers.'mlr-3'.baseUrl
    assert_eq 'D3 scrittura: api' 'anthropic-messages' $w.providers.'mlr-3'.api
    assert_eq 'D3 scrittura: apiKey' '$MLR_API_KEY' $w.providers.'mlr-3'.apiKey
    assert_eq 'D3 scrittura: input text' 'text' $w.providers.'mlr-3'.models[0].input[0]
    assert_eq 'D3 scrittura: input image' 'image' $w.providers.'mlr-3'.models[0].input[1]
}

# --- D4: il merge non distruttivo su un provider esistente -------------------
$conf = New-ConfFile 'd4.json'
Set-Content -Path $conf -Encoding UTF8 -Value (@{
    providers = @{
        'mlr-3' = @{
            baseUrl = 'https://api.server.example'
            api = 'anthropic-messages'
            apiKey = '$MLR_API_KEY'
            promptCache = @{ enabled = $true }
            models = @(
                @{ id = 'MLR-3'; name = 'MLR-3'; input = @('text','image'); contextWindow = 1000000; maxTokens = 32768 }
                @{ id = 'altro-modello'; name = 'altro-modello'; input = @('text') }
            )
        }
    }
} | ConvertTo-Json -Depth 10)
$r = Invoke-PSConf -ConfArgs @(
    'add', '--endpoint', 'https://api.server.example', '--model', 'MLR-3',
    '--context', '1000000', '--yes'
) -ConfigFile $conf
assert_eq 'D4 merge: exit code 0' 0 $r.Code
if (Test-Path $conf) {
    $w = Get-Content $conf -Raw | ConvertFrom-Json
    assert_eq 'D4 merge: promptCache conservato' 'True' "$($w.providers.'mlr-3'.promptCache.enabled)"
    assert_eq 'D4 merge: modelli conservati' '2' "$(@($w.providers.'mlr-3'.models).Count)"
    assert_eq 'D4 merge: input esistente conservato' 'text,image' ($w.providers.'mlr-3'.models[0].input -join ',')
}

Remove-Work

Write-Host ""
Write-Host ("passati: {0}   falliti: {1}" -f $script:Pass, $script:Fail)
if ($script:Fail -eq 0) {
    Write-Host 'RISULTATO: OK'
    exit 0
} else {
    Write-Host 'RISULTATO: FALLITO'
    exit 1
}
