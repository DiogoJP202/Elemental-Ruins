<#
.SYNOPSIS
  Executa a bateria de verificação do P3.5 (Terra polida; inclui as regressões do P0 ao P3) e grava logs em docs/evidence/p35/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/run_p35_tests.ps1
  powershell -ExecutionPolicy Bypass -File tools/run_p35_tests.ps1 -Window -Export

.NOTES
  Passos headless: import (com 1 repetição se a Godot cair no encerramento, B1), check_env, probe da
  API, spike da Terra polida (00_spike_p35.txt), selftest P0 sozinho (12 testes), selftest P3.5 (P0–P3 + T39–T45) e a
  persistência entre processos rodada pelo selftest P3.5 (grava em docs/evidence/p35/).
  -Window : também roda o selftest P3.5 em janela, com capturas em docs/evidence/p35/screens/ (inclui as fases da Terra, T45)
            (tempo de quadro, FPS e os critérios do T27 e do T37 só valem neste modo)
  -Export : exporta build/elemental_ruins.exe (template custom do preset) e roda nele o selftest P3.5
            e a persistência entre processos (headless; com -Window, também o selftest em janela)
  -StepTimeoutSec : limite de cada passo, em segundos (padrão 900; 0 = sem limite). Estourou: o processo é
            encerrado, o log ganha uma linha TIMEOUT e o passo sai com exit 124.
  Feche o editor deste projeto antes de rodar.
#>
param(
    [string]$Godot = $env:GODOT,
    [switch]$Window,
    [switch]$Export,
    [int]$StepTimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$Godot = Resolve-Godot $Godot

$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root 'docs\evidence\p35'
New-Item -ItemType Directory -Force $evidence | Out-Null
$results = [ordered]@{}

function Invoke-Step([string]$Name, [string]$LogFile, [string]$Exe, [string[]]$Arguments) {
    Write-Host "==> $Name"
    $log = Join-Path $evidence $LogFile
    $t0 = Get-Date
    $code = Invoke-Native $Exe $Arguments $log $root $StepTimeoutSec
    $results[$Name] = $code
    Write-Host ("    exit={0}{1}  {2:N1} s  log={3}" -f $code, $(if ($code -eq $script:TimeoutExitCode) { ' (TIMEOUT)' } else { '' }),
        ((Get-Date) - $t0).TotalSeconds, $log)
}

function Report([string]$Name) {
    return (Join-Path $evidence $Name) -replace '\\', '/'
}

Push-Location $root
try {
    Write-Host '==> import'
    $imp = Invoke-Import $Godot $evidence $root $StepTimeoutSec
    $results['import'] = $imp.Code
    Write-Host ("    exit={0}  tentativas={1}  log={2}" -f $imp.Code, $imp.Attempts, $imp.Log)

    $scene = 'res://scenes/main.tscn'
    Invoke-Step 'check_env' '02_check_env.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/check_env.gd')
    Invoke-Step 'probe_voxel_api' '03_probe_run.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/probe_voxel_api.gd')
    Invoke-Step 'spike_p35_earth' '04_spike_p35_earth.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/spike_p35_earth.gd')
    Invoke-Step 'p0_regressao_headless' '05_p0_regressao_headless.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p0-selftest', "--report=$(Report 'p0_regressao_headless.json')")
    Invoke-Step 'p35_selftest_headless' '06_p35_selftest_headless.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p35-selftest', "--report=$(Report 'p35_selftest_headless.json')")
    Invoke-Step 'persist_write' '07_persist_write.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p35-selftest', '--p1-persist=write', "--report=$(Report 'persist_write_headless.json')")
    Invoke-Step 'persist_read' '08_persist_read.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p35-selftest', '--p1-persist=read', "--report=$(Report 'persist_read_headless.json')")

    if ($Window) {
        Remove-Item (Join-Path $evidence 'screens\*.png') -ErrorAction SilentlyContinue
        Invoke-Step 'p35_selftest_window' '09_p35_selftest_window.log' $Godot @('--path', '.', $scene, '--', '--p35-selftest', '--p35-screenshots', "--report=$(Report 'p35_selftest_window.json')")
    }

    if ($Export) {
        Assert-ExportTemplate $root
        New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
        Invoke-Step 'export_release' '10_export_release.log' $Godot @('--headless', '--path', '.', '--export-release', 'Windows Desktop', 'build/elemental_ruins.exe')
        $exe = Join-Path $root 'build\elemental_ruins.exe'
        Invoke-Step 'export_p35_headless' '11_export_p35_headless.log' $exe @('--headless', '--', '--p35-selftest', "--report=$(Report 'p35_selftest_export_headless.json')")
        Invoke-Step 'export_persist_write' '12_export_persist_write.log' $exe @('--headless', '--', '--p35-selftest', '--p1-persist=write', "--report=$(Report 'persist_write_export.json')")
        Invoke-Step 'export_persist_read' '13_export_persist_read.log' $exe @('--headless', '--', '--p35-selftest', '--p1-persist=read', "--report=$(Report 'persist_read_export.json')")
        if ($Window) {
            Invoke-Step 'export_p35_window' '14_export_p35_window.log' $exe @('--', '--p35-selftest', "--report=$(Report 'p35_selftest_export_window.json')")
        }
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Resumo (exit code 0 = OK):'
$failed = $false
foreach ($k in $results.Keys) {
    Write-Host ("  {0,-26} {1}{2}" -f $k, $results[$k], $(if ($results[$k] -eq $script:TimeoutExitCode) { ' TIMEOUT' } else { '' }))
    if ($results[$k] -ne 0) { $failed = $true }
}
if ($failed) { exit 1 } else { exit 0 }
