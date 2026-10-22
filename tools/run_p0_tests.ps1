<#
.SYNOPSIS
  Executa a bateria de verificação do P0 e grava logs em docs/evidence/.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1
  powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Window -Export
  powershell -ExecutionPolicy Bypass -File tools/run_p0_tests.ps1 -Godot "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"

.NOTES
  -Godot  : caminho do executável *_console.exe da Godot 4.7.2 (padrão: $env:GODOT ou o caminho desta máquina)
  -Window : também roda o selftest em janela, com capturas PNG em docs/evidence/screens/
  -Export : também exporta build/elemental_ruins.exe (release) e roda o selftest nele
#>
param(
    [string]$Godot = $env:GODOT,
    [switch]$Window,
    [switch]$Export
)

$ErrorActionPreference = 'Stop'
if (-not $Godot) {
    $Godot = 'C:\Users\dsoares\Tools\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path $Godot)) {
    throw "Godot não encontrada em '$Godot'. Passe -Godot <caminho do *_console.exe> ou defina `$env:GODOT."
}

$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root 'docs\evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$results = [ordered]@{}

# Usa System.Diagnostics.Process em vez de `&`/`*>` porque: (1) o Windows PowerShell 5.1
# grava redirecionamentos em UTF-16; (2) o executável exportado é de subsistema GUI e `&`
# não espera ele terminar, o que devolveria um exit code falso. Aqui sempre aguardamos o
# término e gravamos stdout seguido de stderr em UTF-8.
function Invoke-Step([string]$Name, [string]$LogFile, [string]$Exe, [string[]]$Arguments) {
    Write-Host "==> $Name"
    $log = Join-Path $evidence $LogFile
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $text = $stdout.Result
    if ($stderr.Result) { $text += "`n----- stderr -----`n" + $stderr.Result }
    [System.IO.File]::WriteAllText($log, $text, (New-Object System.Text.UTF8Encoding $false))
    $results[$Name] = $proc.ExitCode
    Write-Host ("    exit={0}  log={1}" -f $proc.ExitCode, $log)
}

# Bug B4 (docs/voxel_spike_results.md): com outra Godot aberta neste projeto (editor ou jogo via F5),
# a cópia temporária ~libvoxel…dll que a Godot carrega fica travada; a extensão não carrega e o import
# termina em crash (0xC0000005). Se a cópia estiver travada, aborta antes de tocar nas evidências.
$tempDll = Join-Path $root 'addons\zylann.voxel\bin\~libvoxel.windows.editor.x86_64.dll'
if (Test-Path $tempDll) {
    try {
        $fs = [System.IO.File]::Open($tempDll, 'Open', 'ReadWrite', 'None')
        $fs.Close()
    }
    catch {
        Write-Host 'ERRO: outra instância da Godot está usando este projeto (a DLL temporária do Voxel Tools está travada).'
        Write-Host '      Feche o editor e o jogo deste projeto e rode de novo. Ver bug B4 em docs/voxel_spike_results.md.'
        exit 2
    }
}

Push-Location $root
try {
    # Mitigação do bug B1 (docs/voxel_spike_results.md): numa importação com cache vazio a extensão
    # é registrada no meio da sessão e a Godot fecha com segfault de forma intermitente (10/17).
    # Pré-registrar a extensão fez 11/11 importações limpas terminarem bem. A Godot regenera este arquivo.
    $extList = Join-Path $root '.godot\extension_list.cfg'
    if (-not (Test-Path $extList)) {
        New-Item -ItemType Directory -Force (Split-Path $extList) | Out-Null
        [System.IO.File]::WriteAllText($extList, "res://addons/zylann.voxel/voxel.gdextension`n")
        Write-Host '    (pré-registrada a extensão em .godot/extension_list.cfg)'
    }
    Invoke-Step 'import' '01_import.log' $Godot @('--headless', '--path', '.', '--import')
    Invoke-Step 'check_env' '02_check_env.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/check_env.gd')
    Invoke-Step 'probe_voxel_api' '03_probe_run.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/probe_voxel_api.gd')
    Invoke-Step 'selftest_headless' '05_selftest_headless.log' $Godot @('--headless', '--path', '.', 'res://scenes/main.tscn', '--', '--p0-selftest')

    if ($Window) {
        Remove-Item (Join-Path $evidence 'screens\*.png') -ErrorAction SilentlyContinue
        Invoke-Step 'selftest_window' '06_selftest_window.log' $Godot @('--path', '.', 'res://scenes/main.tscn', '--', '--p0-selftest', '--p0-screenshots')
    }

    if ($Export) {
        New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
        Invoke-Step 'export_release' '07_export_release.log' $Godot @('--headless', '--path', '.', '--export-release', 'Windows Desktop', 'build/elemental_ruins.exe')
        $exe = Join-Path $root 'build\elemental_ruins.exe'
        $report = (Join-Path $evidence 'p0_selftest_export_headless.json') -replace '\\', '/'
        Invoke-Step 'export_selftest_headless' '08_export_selftest_headless.log' $exe @('--headless', '--', '--p0-selftest', "--report=$report")
    }
}
finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Resumo (exit code 0 = OK):'
$failed = $false
foreach ($k in $results.Keys) {
    Write-Host ("  {0,-26} {1}" -f $k, $results[$k])
    if ($results[$k] -ne 0) { $failed = $true }
}
if ($failed) { exit 1 } else { exit 0 }
