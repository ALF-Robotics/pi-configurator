#!/usr/bin/env pwsh
# install-provider.ps1 - installa pi-configurator E configura un provider,
# con una sola invocazione e senza separatori da ricordare.
#
# Questo e' il punto d'ingresso per il provisioning: i parametri del provider
# sono parametri di primo livello, quindi non serve il separatore `--` che
# install.ps1 usa per passare argomenti a pi-conf.ps1.
#
#   irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install-provider.ps1 | iex
#
# Con i parametri del provider, usando l'array -Args:
#
#   irm .../main/install-provider.ps1 | iex -args @(
#       '-Ref','v0.2.0',
#       '-Endpoint','https://api.server.example',
#       '-Api','anthropic',
#       '-Model','MLR-3',
#       '-KeyEnv','MLR_API_KEY'
#   )
#
# Come install.ps1: l'installazione e' delegata a install.ps1 allo stesso ref,
# cosi' download e verifica SHA256 esistono in un solo posto. Prima di eseguirlo
# questo script ne verifica l'hash: un installer delegato e' codice che si sta
# per eseguire.
#
# Compatibile con Windows PowerShell 5.1 e PowerShell 7+.

[CmdletBinding()]
param(
    [string]$Ref = $(if ($env:PI_CONF_REF) { $env:PI_CONF_REF } else { 'main' }),
    [string]$Prefix = $(if ($env:PI_CONF_PREFIX) { $env:PI_CONF_PREFIX }
                        else { Join-Path $env:USERPROFILE '.pi-configurator' }),
    [switch]$NoVerify,
    [switch]$DryRun,

    # parametri del provider, passati a pi-conf.ps1 add
    [string]$Endpoint,
    [string]$Api = 'anthropic',
    [string]$Model,
    [string]$Profile,
    [string]$Key,
    [string]$KeyEnv,
    [switch]$NoReasoning,
    [string]$Context,
    [string]$MaxTokens,
    [string]$FromFile,
    [string]$Config,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$Owner = 'ALF-Robotics'
$Repo  = 'pi-configurator'
$Raw   = "https://raw.githubusercontent.com/$Owner/$Repo/$Ref"

function Write-Step { param($m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Info { param($m) Write-Host "  $m" }
function Fail       { param($m) Write-Host "install-provider.ps1: $m" -ForegroundColor Red; exit 1 }

# --- validazione ------------------------------------------------------------

if (-not $Endpoint) { Fail 'manca -Endpoint (obbligatorio)' }
if (-not $Model)    { Fail 'manca -Model (obbligatorio)' }

# Ricostruisce gli argomenti per pi-conf.ps1, perche' un semplice
# & pi-conf.ps1 add non accetta parametri che iniziano con --.
$providerArgs = @('add', '--endpoint', $Endpoint, '--api', $Api, '--model', $Model)
if ($Profile)                          { $providerArgs += @('--profile', $Profile) }
if ($Key)                              { $providerArgs += @('--key', $Key) }
if ($KeyEnv)                           { $providerArgs += @('--key-env', $KeyEnv) }
if ($NoReasoning)                      { $providerArgs += '--no-reasoning' }
if ($Context)                          { $providerArgs += @('--context', $Context) }
if ($MaxTokens)                        { $providerArgs += @('--max-tokens', $MaxTokens) }
if ($FromFile)                         { $providerArgs += @('--from-file', $FromFile) }
if ($Config)                           { $providerArgs += @('--config', $Config) }
if ($Yes)                              { $providerArgs += '--yes' }
if ($Key -and $KeyEnv)                 { Fail '-Key e -KeyEnv sono incompatibili: scegline uno' }

# --- installer delegato: download e verifica ---------------------------------

Write-Step 'pi-configurator - installazione e configurazione'
Write-Info "ref:     $Ref$(if ($Ref -eq 'main') { '  (NON pinnata)' } else { '  (pinnata)' })"
Write-Info "prefix:  $Prefix"
Write-Info "provider: $($providerArgs -join ' ')"

if ($Ref -eq 'main') {
    Write-Host ''
    Write-Host '  ATTENZIONE: stai installando da "main", che puo'' cambiare in' -ForegroundColor Yellow
    Write-Host '  qualsiasi momento. Usa un tag.' -ForegroundColor Yellow
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pi-confp-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$cleanup = { if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue } }

try {
    $delegate = Join-Path $tmp 'install.ps1'
    Write-Step 'Installer delegato: download'
    Write-Info "$Raw/install.ps1"
    Invoke-WebRequest -Uri "$Raw/install.ps1" -OutFile $delegate -UseBasicParsing

    if (-not $NoVerify) {
        $sumsPath = Join-Path $tmp 'SHA256SUMS'
        try {
            Invoke-WebRequest -Uri "$Raw/SHA256SUMS" -OutFile $sumsPath -UseBasicParsing -ErrorAction Stop
            $want = $null
            foreach ($line in (Get-Content $sumsPath)) {
                if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?install\.ps1\s*$') { $want = $Matches[1] }
            }
            if ($want) {
                Write-Step 'Verifica sha256 di install.ps1'
                $got = (Get-FileHash -Path $delegate -Algorithm SHA256).Hash.ToLower()
                if ($got -eq $want.ToLower()) { Write-Info 'install.ps1  OK' }
                else {
                    Fail "checksum non corrispondente per install.ps1`n  atteso:  $want`n  ottenuto: $got`n  Il codice che sto per eseguire non e' quello dichiarato. Non proseguo."
                }
            } else {
                Write-Info 'nessun hash per install.ps1 in SHA256SUMS, salto'
            }
        } catch {
            Write-Info 'SHA256SUMS non raggiungibile: la verifica non verra'' eseguita'
        }
    }

    # --- installazione, delegata --------------------------------------------
    $installerArgs = @('-Ref', $Ref, '-Prefix', $Prefix)
    if ($NoVerify) { $installerArgs += '-NoVerify' }
    if ($DryRun)   { $installerArgs += '-DryRun' }
    & $delegate @installerArgs

    if ($DryRun) {
        Write-Step 'Dry run: nessuna scrittura'
        Write-Info "poi sarebbe stato eseguito: pi-conf.ps1 $($providerArgs -join ' ')"
        exit 0
    }

    # --- configurazione -------------------------------------------------------
    Write-Step 'Configurazione del provider'
    & (Join-Path $Prefix 'pi-conf.ps1') @providerArgs

    Write-Step 'Fatto'
    Write-Host "  Tool:   $Prefix\pi-conf.ps1"
    Write-Host ""
    Write-Host "  Se hai usato -KeyEnv, la variabile deve essere impostata nella shell da cui"
    Write-Host "  lanci pi, altrimenti il provider risultera' non autenticato."
} finally {
    & $cleanup
}
