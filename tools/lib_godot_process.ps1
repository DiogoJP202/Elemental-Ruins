<#
.SYNOPSIS
  Funções comuns dos runners de teste (run_p0_tests.ps1, run_p1_tests.ps1). Carregar com dot-source.
#>

# Exit code devolvido quando um passo estoura o limite de tempo (mesma convenção do `timeout` do GNU).
$script:TimeoutExitCode = 124

# Usa System.Diagnostics.Process em vez de `&`/`*>` porque: (1) o Windows PowerShell 5.1
# grava redirecionamentos em UTF-16; (2) o editor custom e o executável exportado são de
# subsistema GUI e `&` não espera eles terminarem, o que devolveria um exit code falso. Aqui
# sempre aguardamos o término e gravamos stdout seguido de stderr em UTF-8.
# Se o processo passar de $TimeoutSec (0 = sem limite), a árvore dele é encerrada com
# taskkill /T /F, o log ganha uma linha TIMEOUT e o retorno é $script:TimeoutExitCode.
# Motivo: um script GDScript que não compila deixa a cena rodando sem o selftest, e o
# watchdog do selftest nunca chega a existir; sem limite, o runner esperaria para sempre.
function Invoke-Native([string]$Exe, [string[]]$Arguments, [string]$Log, [string]$WorkingDirectory, [int]$TimeoutSec = 600) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    $timedOut = $false
    if ($TimeoutSec -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            & taskkill.exe /PID $proc.Id /T /F 2>&1 | Out-Null
            [void]$proc.WaitForExit(15000)
        }
    }
    else {
        $proc.WaitForExit()
    }
    # Depois de um kill, os pipes fecham com o processo; o limite evita bloquear se algum
    # filho herdou o handle.
    [void]$stdout.Wait(15000)
    [void]$stderr.Wait(15000)
    $text = if ($stdout.IsCompleted) { $stdout.Result } else { '' }
    if ($stderr.IsCompleted -and $stderr.Result) { $text += "`n----- stderr -----`n" + $stderr.Result }
    if ($timedOut) {
        $text += "`n----- TIMEOUT: processo encerrado após $TimeoutSec s (taskkill /T /F); exit=$($script:TimeoutExitCode) -----`n"
    }
    [System.IO.File]::WriteAllText($Log, $text, (New-Object System.Text.UTF8Encoding $false))
    if ($timedOut) { return $script:TimeoutExitCode }
    return $proc.ExitCode
}

# Bug B1 (docs/voxel_spike_results.md): o `--import` da Godot 4.7.2 pode cair no ENCERRAMENTO,
# depois de concluir a importação (com o módulo: 1/50 em cache vazio). Se cair, repete uma vez;
# as duas tentativas ficam no log e o retorno informa quantas foram necessárias.
# Um timeout NÃO é o B1 (o B1 cai no fim, não trava): nesse caso não repete.
function Invoke-Import([string]$Godot, [string]$Evidence, [string]$Root, [int]$TimeoutSec = 600) {
    $importLog = Join-Path $Evidence '01_import.log'
    $code = Invoke-Native $Godot @('--headless', '--path', '.', '--import') $importLog $Root $TimeoutSec
    $attempts = 1
    if ($code -ne 0 -and $code -ne $script:TimeoutExitCode) {
        Write-Host "    1ª tentativa exit=$code (bug B1 no encerramento); repetindo"
        Copy-Item $importLog (Join-Path $Evidence '01_import_tentativa1.log') -Force
        $code = Invoke-Native $Godot @('--headless', '--path', '.', '--import') $importLog $Root $TimeoutSec
        $attempts = 2
    }
    return @{ Code = $code; Attempts = $attempts; Log = $importLog }
}

function Resolve-Godot([string]$Godot) {
    if (-not $Godot) {
        $Godot = 'C:\Users\dsoares\Tools\Godot\4.7.2-voxel1.7\godot.windows.editor.x86_64.exe'
    }
    if (-not (Test-Path $Godot)) {
        throw "Editor Godot custom não encontrado em '$Godot'. Passe -Godot <godot.windows.editor.x86_64.exe> ou defina `$env:GODOT. Download: release v1.7 de https://github.com/Zylann/godot_voxel/releases (ver README)."
    }
    return $Godot
}

function Assert-ExportTemplate([string]$Root) {
    $preset = Get-Content (Join-Path $Root 'export_presets.cfg') -Raw
    if ($preset -match 'custom_template/release="([^"]*)"' -and -not (Test-Path $Matches[1])) {
        throw "Template custom não encontrado: '$($Matches[1])'. Ajuste custom_template/release em export_presets.cfg (ver README)."
    }
}
