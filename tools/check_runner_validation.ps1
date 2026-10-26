<#
.SYNOPSIS
  Prova que a validação de relatório dos runners (Invoke-SelftestStep, P3.6) não aceita falso sucesso.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/check_runner_validation.ps1

.NOTES
  Três casos reais, com o selftest do P0 (12 testes), gravando em docs/evidence/p36/runner_validation/:
    A) execução normal                                   → precisa sair 0 (12/12 PASS)
    B) a Godot encerra cedo com exit 0 (--quit-after 90,  → precisa sair 3 (RELATÓRIO INVÁLIDO): é o que acontece
       o mesmo efeito de fechar a janela no meio)            quando a janela é fechada no meio do selftest
    C) contagem esperada errada (13)                      → precisa sair 3
  Exit 0 = os três casos se comportaram como esperado.
#>
param(
    [string]$Godot = $env:GODOT,
    [int]$StepTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$Godot = Resolve-Godot $Godot
$root = Split-Path -Parent $PSScriptRoot
$evidence = Join-Path $root 'docs\evidence\p36\runner_validation'
New-Item -ItemType Directory -Force $evidence | Out-Null
$results = [ordered]@{}
$scene = 'res://scenes/main.tscn'
function Report([string]$Name) { return (Join-Path $evidence $Name) -replace '\\', '/' }

Push-Location $root
try {
    Invoke-SelftestStep 'A_normal' 'A_normal.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p0-selftest') (Report 'A_normal.json') 12
    Invoke-SelftestStep 'B_encerra_cedo' 'B_encerra_cedo.log' $Godot @('--headless', '--path', '.', $scene, '--quit-after', '90', '--', '--p0-selftest') (Report 'B_encerra_cedo.json') 12
    Invoke-SelftestStep 'C_contagem_errada' 'C_contagem_errada.log' $Godot @('--headless', '--path', '.', $scene, '--', '--p0-selftest') (Report 'C_contagem_errada.json') 13
}
finally {
    Pop-Location
}

$expected = [ordered]@{ 'A_normal' = 0; 'B_encerra_cedo' = $script:InvalidReportExitCode; 'C_contagem_errada' = $script:InvalidReportExitCode }
$ok = $true
Write-Host ''
foreach ($k in $expected.Keys) {
    $match = $results[$k] -eq $expected[$k]
    if (-not $match) { $ok = $false }
    Write-Host ("  {0,-20} exit={1} esperado={2} {3}" -f $k, $results[$k], $expected[$k], $(if ($match) { 'OK' } else { 'FALHOU' }))
}
if ($ok) { Write-Host 'Validação dos runners: OK'; exit 0 } else { Write-Host 'Validação dos runners: FALHOU'; exit 1 }
