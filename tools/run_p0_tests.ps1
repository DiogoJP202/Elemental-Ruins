<#
.SYNOPSIS
  Executa a bateria de verificação do P0 e grava logs em docs/evidence/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1
  powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Window -Export
  powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Godot "D:\Godot\godot.windows.editor.x86_64.exe"

.NOTES
  -Godot  : editor Godot 4.7.2 custom com Voxel Tools 1.7 embutido (módulo).
            Padrão: $env:GODOT ou o caminho desta máquina. A Godot oficial NÃO serve: ela não
            tem as classes Voxel desde que o projeto trocou a GDExtension pelo módulo (D13).
  -Window : também roda o selftest em janela, com capturas PNG em docs/evidence/screens/
  -Export : também exporta build/elemental_ruins.exe (release, template custom do preset) e roda o
            selftest nele (headless; com -Window, também em janela)
  -StepTimeoutSec : limite de cada passo, em segundos (padrão 600; 0 = sem limite). Estourou: o processo é
            encerrado, o log ganha uma linha TIMEOUT e o passo sai com exit 124.
  A bateria do P1 (que inclui estes 12 testes) é tools/run_p1_tests.ps1.
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
$evidence = Join-Path $root 'docs\evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$results = [ordered]@{}

function Invoke-Step([string]$Name, [string]$LogFile, [string]$Exe, [string[]]$Arguments) {
    Write-Host "==> $Name"
    $log = Join-Path $evidence $LogFile
    $code = Invoke-Native $Exe $Arguments $log $root $StepTimeoutSec
    $results[$Name] = $code
    Write-Host ("    exit={0}{1}  log={2}" -f $code, $(if ($code -eq $script:TimeoutExitCode) { ' (TIMEOUT)' } else { '' }), $log)
}

Push-Location $root
try {
    Write-Host '==> import'
    $imp = Invoke-Import $Godot $evidence $root $StepTimeoutSec
    $results['import'] = $imp.Code
    Write-Host ("    exit={0}  tentativas={1}  log={2}" -f $imp.Code, $imp.Attempts, $imp.Log)

    Invoke-Step 'check_env' '02_check_env.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/check_env.gd')
    Invoke-Step 'probe_voxel_api' '03_probe_run.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/probe_voxel_api.gd')
    Invoke-Step 'selftest_headless' '05_selftest_headless.log' $Godot @('--headless', '--path', '.', 'res://scenes/main.tscn', '--', '--p0-selftest')

    if ($Window) {
        Remove-Item (Join-Path $evidence 'screens\*.png') -ErrorAction SilentlyContinue
        Invoke-Step 'selftest_window' '06_selftest_window.log' $Godot @('--path', '.', 'res://scenes/main.tscn', '--', '--p0-selftest', '--p0-screenshots')
    }

    if ($Export) {
        Assert-ExportTemplate $root
        New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
        Invoke-Step 'export_release' '07_export_release.log' $Godot @('--headless', '--path', '.', '--export-release', 'Windows Desktop', 'build/elemental_ruins.exe')
        $exe = Join-Path $root 'build\elemental_ruins.exe'
        $report = (Join-Path $evidence 'p0_selftest_export_headless.json') -replace '\\', '/'
        Invoke-Step 'export_selftest_headless' '08_export_selftest_headless.log' $exe @('--headless', '--', '--p0-selftest', "--report=$report")
        if ($Window) {
            $reportWin = (Join-Path $evidence 'p0_selftest_export_window.json') -replace '\\', '/'
            Invoke-Step 'export_selftest_window' '09_export_selftest_window.log' $exe @('--', '--p0-selftest', "--report=$reportWin")
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
