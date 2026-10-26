param([string]$Godot=$env:GODOT, [string]$EvidenceFolder='docs/evidence/p36/baseline')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$Godot=Resolve-Godot $Godot
$root=Split-Path $PSScriptRoot
$evidence=Join-Path $root $EvidenceFolder
$results=[ordered]@{}
$StepTimeoutSec=900
New-Item -ItemType Directory -Force $evidence | Out-Null
Push-Location $root
try {
    $metadata=[ordered]@{commit=(git rev-parse HEAD);git_status=@(git status --porcelain);date=(Get-Date -Format o);
        cpu=(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors);
        gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion);
        os=(Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,TotalVisibleMemorySize);
        resolution='1600x900';renderer='Forward+';physics='Jolt Physics';vsync='project default (enabled)';
        scenario='P0-P3.5 full suite: T27 collapse, T37 collapse + 12 fires + four abilities';
        methodology='Sequential processes; real physics ticks; window frame intervals sampled during T27/T37; headless not a rendering gate';
        gates_ms=@{p95=20;p99=33;max=50};
        existing_godot_processes=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'godot|elemental_ruins'} | Select-Object ProcessId,CommandLine)}
    $metadata | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence 'environment.json') -Encoding UTF8
    $imp=Invoke-Import $Godot $evidence $root 180
    if($imp.Code -ne 0){throw 'Import falhou'}
    Assert-ExportTemplate $root
    $exportCode=Invoke-Native $Godot @('--headless','--path','.','--export-release','Windows Desktop','build/elemental_ruins.exe') (Join-Path $evidence 'export.log') $root 180
    if($exportCode -ne 0){throw 'Export falhou'}
    $exe=Join-Path $root 'build/elemental_ruins.exe'
    $ids=Get-SelftestIds 'p35'
    Invoke-SelftestStep 'editor_headless' 'editor_headless.log' $Godot @('--headless','--path','.','res://scenes/main.tscn','--','--p35-selftest') ((Join-Path $evidence 'editor_headless.json') -replace '\\','/') $ids
    Invoke-SelftestStep 'editor_window' 'editor_window.log' $Godot @('--path','.','res://scenes/main.tscn','--','--p35-selftest') ((Join-Path $evidence 'editor_window.json') -replace '\\','/') $ids
    Invoke-SelftestStep 'export_headless' 'export_headless.log' $exe @('--headless','--','--p35-selftest') ((Join-Path $evidence 'export_headless.json') -replace '\\','/') $ids
    Invoke-SelftestStep 'export_window' 'export_window.log' $exe @('--','--p35-selftest') ((Join-Path $evidence 'export_window.json') -replace '\\','/') $ids
    $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
    if(@($results.Values | Where-Object {$_ -ne 0}).Count){exit 1}
} finally {Pop-Location}
