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
#>
param(
    [string]$Godot = $env:GODOT,
    [switch]$Window,
    [switch]$Export
)

$ErrorActionPreference = 'Stop'
if (-not $Godot) {
    $Godot = 'C:\Users\dsoares\Tools\Godot\4.7.2-voxel1.7\godot.windows.editor.x86_64.exe'
}
if (-not (Test-Path $Godot)) {
    throw "Editor Godot custom não encontrado em '$Godot'. Passe -Godot <godot.windows.editor.x86_64.exe> ou defina `$env:GODOT. Download: release v1.7 de https://github.com/Zylann/godot_voxel/releases (ver README)."
}

$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root 'docs\evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$results = [ordered]@{}

# Usa System.Diagnostics.Process em vez de `&`/`*>` porque: (1) o Windows PowerShell 5.1
# grava redirecionamentos em UTF-16; (2) o editor custom e o executável exportado são de
# subsistema GUI e `&` não espera eles terminarem, o que devolveria um exit code falso. Aqui
# sempre aguardamos o término e gravamos stdout seguido de stderr em UTF-8.
function Invoke-Native([string]$Exe, [string[]]$Arguments, [string]$Log) {
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
    [System.IO.File]::WriteAllText($Log, $text, (New-Object System.Text.UTF8Encoding $false))
    return $proc.ExitCode
}

function Invoke-Step([string]$Name, [string]$LogFile, [string]$Exe, [string[]]$Arguments) {
    Write-Host "==> $Name"
    $log = Join-Path $evidence $LogFile
    $code = Invoke-Native $Exe $Arguments $log
    $results[$Name] = $code
    Write-Host ("    exit={0}  log={1}" -f $code, $log)
}

Push-Location $root
try {
    # Bug B1 (docs/voxel_spike_results.md): o `--import` da Godot 4.7.2 pode cair no ENCERRAMENTO,
    # depois de concluir a importação (com o módulo: ~1/34 em cache vazio). Se cair, repete uma vez;
    # as duas tentativas ficam no log e o resumo informa quantas foram necessárias.
    Write-Host '==> import'
    $importLog = Join-Path $evidence '01_import.log'
    $code = Invoke-Native $Godot @('--headless', '--path', '.', '--import') $importLog
    $attempts = 1
    if ($code -ne 0) {
        Write-Host "    1ª tentativa exit=$code (bug B1 no encerramento); repetindo"
        Copy-Item $importLog (Join-Path $evidence '01_import_tentativa1.log') -Force
        $code = Invoke-Native $Godot @('--headless', '--path', '.', '--import') $importLog
        $attempts = 2
    }
    $results['import'] = $code
    Write-Host ("    exit={0}  tentativas={1}  log={2}" -f $code, $attempts, $importLog)

    Invoke-Step 'check_env' '02_check_env.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/check_env.gd')
    Invoke-Step 'probe_voxel_api' '03_probe_run.log' $Godot @('--headless', '--path', '.', '--script', 'res://tools/probe_voxel_api.gd')
    Invoke-Step 'selftest_headless' '05_selftest_headless.log' $Godot @('--headless', '--path', '.', 'res://scenes/main.tscn', '--', '--p0-selftest')

    if ($Window) {
        Remove-Item (Join-Path $evidence 'screens\*.png') -ErrorAction SilentlyContinue
        Invoke-Step 'selftest_window' '06_selftest_window.log' $Godot @('--path', '.', 'res://scenes/main.tscn', '--', '--p0-selftest', '--p0-screenshots')
    }

    if ($Export) {
        $preset = Get-Content (Join-Path $root 'export_presets.cfg') -Raw
        if ($preset -match 'custom_template/release="([^"]*)"' -and -not (Test-Path $Matches[1])) {
            throw "Template custom não encontrado: '$($Matches[1])'. Ajuste custom_template/release em export_presets.cfg (ver README)."
        }
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
    Write-Host ("  {0,-26} {1}" -f $k, $results[$k])
    if ($results[$k] -ne 0) { $failed = $true }
}
if ($failed) { exit 1 } else { exit 0 }
