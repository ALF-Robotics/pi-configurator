#!/usr/bin/env pwsh
# install.ps1 - installa pi-configurator su Windows.
#
# Pensato per essere eseguito direttamente dalla rete:
#
#   irm https://raw.githubusercontent.com/ALF-Robotics/pi-configurator/main/install.ps1 | iex
#
# Con un ref pinnato (tag o commit), che e' cio' che rende l'installazione
# riproducibile e l'URL immutabile:
#
#   irm .../main/install.ps1 | iex -args @('-Ref','v0.2.0')
#
# Installando e configurando un provider nella stessa invocazione:
#
#   irm .../main/install.ps1 | iex -args @('-Ref','v0.2.0','--',
#       '--endpoint','https://api.server.example','--api','anthropic',
#       '--model','MLR-3','--key-env','MLR_API_KEY')
#
# Compatibile con Windows PowerShell 5.1 e PowerShell 7+.
#
# Nota: da PowerShell si puo' eseguire anche:
#   .\install.ps1 -Ref v0.2.0

[CmdletBinding()]
param(
    [string]$Ref = $(if ($env:PI_CONF_REF) { $env:PI_CONF_REF } else { 'main' }),
    [string]$Prefix = $(if ($env:PI_CONF_PREFIX) { $env:PI_CONF_PREFIX }
                        else { Join-Path $env:USERPROFILE '.pi-configurator' }),
    [switch]$NoVerify,
    [switch]$DryRun,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$Owner = 'ALF-Robotics'
$Repo  = 'pi-configurator'
$Raw   = "https://raw.githubusercontent.com/$Owner/$Repo/$Ref"
$Files = @('pi-conf.sh', 'pi-conf.ps1')

function Write-Step  { param($m) Write-Host ''; Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Info  { param($m) Write-Host "  $m" }
function Fail        { param($m) Write-Host "install.ps1: $m" -ForegroundColor Red; exit 1 }

# --- passthrough al configuratore -------------------------------------------
# Tutto cio' che segue '--' viene passato a pi-conf.ps1.
$Passthrough = @()
if ($Rest) {
    $idx = [Array]::IndexOf($Rest, '--')
    if ($idx -ge 0) { $Passthrough = $Rest[($idx + 1)..($Rest.Count - 1)] }
    elseif ($Rest.Count -gt 0) { $Passthrough = $Rest }
}

# --- pianificazione ---------------------------------------------------------

Write-Step 'pi-configurator - installazione'
Write-Info "ref:     $Ref$(if ($Ref -eq 'main') { '  (NON pinnata)' } else { '  (pinnata)' })"
Write-Info "prefix:  $Prefix"
Write-Info "sorgente: $Raw"

if ($Ref -eq 'main') {
    Write-Host ''
    Write-Host '  ATTENZIONE: stai installando da "main", che puo'' cambiare in' -ForegroundColor Yellow
    Write-Host '  qualsiasi momento. Per un''installazione riproducibile usa un tag:' -ForegroundColor Yellow
    Write-Host '      irm .../main/install.ps1 | iex -args @(''-Ref'',''v0.2.0'')' -ForegroundColor Yellow
}

# --- download ---------------------------------------------------------------

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pi-conf-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$cleanup = { if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue } }

Write-Step 'Download'
try {
    foreach ($f in $Files) {
        Write-Info "$Raw/$f"
        $dest = Join-Path $tmp $f
        Invoke-WebRequest -Uri "$Raw/$f" -OutFile $dest -UseBasicParsing
    }

    # --- verifica integrita' -------------------------------------------------
    $sumsPath = Join-Path $tmp 'SHA256SUMS'
    if (-not $NoVerify) {
        try {
            Invoke-WebRequest -Uri "$Raw/SHA256SUMS" -OutFile $sumsPath -UseBasicParsing -ErrorAction Stop
            Write-Step 'Verifica sha256'
            $sums = @{}
            foreach ($line in (Get-Content $sumsPath)) {
                if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') { $sums[$Matches[2]] = $Matches[1] }
            }
            foreach ($f in $Files) {
                if (-not $sums.ContainsKey($f)) { Write-Info "$f : nessun hash in SHA256SUMS, salto"; continue }
                $got = (Get-FileHash -Path (Join-Path $tmp $f) -Algorithm SHA256).Hash.ToLower()
                if ($got -eq $sums[$f].ToLower()) { Write-Info "$f  OK" }
                else {
                    & $cleanup
                    Fail "checksum non corrispondente per $f`n  atteso:  $($sums[$f])`n  ottenuto: $got`n  Il file scaricato e' diverso da quello dichiarato. Non proseguo."
                }
            }
        } catch {
            Write-Info 'SHA256SUMS non raggiungibile: la verifica non verra'' eseguita'
        }
    }

    # --- installazione -------------------------------------------------------
    if ($DryRun) {
        Write-Step 'Dry run: nessuna scrittura'
        Write-Info "verrebbe installato: $(Join-Path $Prefix 'pi-conf.sh'), $(Join-Path $Prefix 'pi-conf.ps1')"
        if ($Passthrough.Count -gt 0) { Write-Info "poi: pi-conf.ps1 add $($Passthrough -join ' ')" }
        & $cleanup; exit 0
    }

    Write-Step "Installazione in $Prefix"
    if (-not (Test-Path $Prefix)) { New-Item -ItemType Directory -Path $Prefix -Force | Out-Null }
    foreach ($f in $Files) {
        Copy-Item -Path (Join-Path $tmp $f) -Destination (Join-Path $Prefix $f) -Force
        Write-Info $f
    }

    # --- configurazione opzionale -------------------------------------------
    if ($Passthrough.Count -gt 0) {
        Write-Step 'Configurazione del provider'
        & (Join-Path $Prefix 'pi-conf.ps1') @Passthrough
    }

    Write-Step 'Fatto'
    Write-Host "  Verifica con:"
    Write-Host "      $Prefix\pi-conf.ps1 -Help"
    Write-Host ""
    Write-Host "  Crea un profilo in modo interattivo:"
    Write-Host "      $Prefix\pi-conf.ps1"
} finally {
    & $cleanup
}
