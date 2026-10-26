<#
.SYNOPSIS
  Executa a bateria de verificação do P1 (inclui a regressão do P0) e grava logs em docs/evidence/p1/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/run_p1_tests.ps1
  powershell -ExecutionPolicy Bypass -File tools/run_p1_tests.ps1 -Window -Export

.NOTES
  Passos headless: import (com 1 repetição se a Godot cair no encerramento, B1), check_env,
  probe da API, spike da API P1, selftest P0 (regressão, 12 testes), selftest P1 (P0 + T8–T17)
  e persistência entre processos (--p1-persist=write num processo, =read em outro).
  -Window : também roda o selftest P1 em janela, com capturas em docs/evidence/p1/screens/
            (tempo de quadro e FPS só são significativos neste modo)
  -Export : exporta build/elemental_ruins.exe (template custom do preset) e roda nele o selftest P1
            e a persistência entre processos (headless; com -Window, também o selftest em janela)
  Passos de selftest só contam como OK com exit 0 E um relatório JSON novo desta execução (run_id), completo,
  com a contagem de testes esperada e todos PASS; senão saem com exit 3 (RELATÓRIO INVÁLIDO). Ex.: fechar a janela
  da Godot no meio do selftest encerra o processo com exit 0, mas sem relatório: o passo falha (P3.6).
  -StepTimeoutSec : limite de cada passo, em segundos (padrão 600; 0 = sem limite). Estourou: o processo é
            encerrado, o log ganha uma linha TIMEOUT e o passo sai com exit 124. O passo mais longo medido
            (selftest P1 em janela) levou ~90 s.
  Feche o editor deste projeto antes de rodar.
#>
param(
    [string]$Godot = $env:GODOT,
    [switch]$Window,
    [switch]$Export,
    [int]$StepTimeoutSec = 600
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$Godot = Resolve-Godot $Godot

$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root 'docs\evidence\p1'
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
    Invoke-Step 'spike_p1_api' '04_spike_api.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/spike_p1_api.gd')
    Invoke-SelftestStep 'p0_regressao_headless' '05_p0_regressao_headless.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p0-selftest') (Report 'p0_regressao_headless.json') 12
    Invoke-SelftestStep 'p1_selftest_headless' '06_p1_selftest_headless.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p1-selftest') (Report 'p1_selftest_headless.json') 23
    Invoke-SelftestStep 'p1_persist_write' '07_persist_write.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p1-persist=write') (Report 'p1_persist_write_headless.json') 2
    Invoke-SelftestStep 'p1_persist_read' '08_persist_read.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p1-persist=read') (Report 'p1_persist_read_headless.json') 2

    if ($Window) {
        Remove-Item (Join-Path $evidence 'screens\*.png') -ErrorAction SilentlyContinue
        Invoke-SelftestStep 'p1_selftest_window' '09_p1_selftest_window.log' $Godot @('--path', '.', $scene, '--', '--p1-selftest', '--p1-screenshots') (Report 'p1_selftest_window.json') 23
    }

    if ($Export) {
        Assert-ExportTemplate $root
        New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
        Invoke-Step 'export_release' '10_export_release.log' $Godot @('--headless', '--path', '.', '--export-release', 'Windows Desktop', 'build/elemental_ruins.exe')
        $exe = Join-Path $root 'build\elemental_ruins.exe'
        Invoke-SelftestStep 'export_p1_headless' '11_export_p1_headless.log' $exe @('--headless', '--', '--p1-selftest') (Report 'p1_selftest_export_headless.json') 23
        Invoke-SelftestStep 'export_persist_write' '12_export_persist_write.log' $exe @('--headless', '--', '--p1-persist=write') (Report 'p1_persist_write_export.json') 2
        Invoke-SelftestStep 'export_persist_read' '13_export_persist_read.log' $exe @('--headless', '--', '--p1-persist=read') (Report 'p1_persist_read_export.json') 2
        if ($Window) {
            Invoke-SelftestStep 'export_p1_window' '14_export_p1_window.log' $exe @('--', '--p1-selftest') (Report 'p1_selftest_export_window.json') 23
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
    Write-Host ("  {0,-26} {1}{2}" -f $k, $results[$k], $(if ($results[$k] -eq $script:TimeoutExitCode) { ' TIMEOUT' } elseif ($results[$k] -eq $script:InvalidReportExitCode) { ' RELATÓRIO INVÁLIDO' } else { '' }))
    if ($results[$k] -ne 0) { $failed = $true }
}
if ($failed) { exit 1 } else { exit 0 }
