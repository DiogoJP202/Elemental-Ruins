param([string]$Godot=$env:GODOT, [Parameter(Mandatory=$true)][string]$Template,
    [string]$EvidenceDirectory='docs/evidence/p36/t26_stabilization/full')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$root=Split-Path $PSScriptRoot
$evidence=if([System.IO.Path]::IsPathRooted($EvidenceDirectory)){$EvidenceDirectory}else{Join-Path $root $EvidenceDirectory}
$StepTimeoutSec=1200
$results=[ordered]@{}
$Godot=Resolve-Godot $Godot
if(-not (Test-Path -LiteralPath $Template)){throw 'Template custom ausente'}
New-Item -ItemType Directory -Force $evidence,(Join-Path $root 'build') | Out-Null
$ids=@(Get-SelftestIds 'p36')
$presetPath=Join-Path $root 'export_presets.cfg'
$originalPreset=[System.IO.File]::ReadAllBytes($presetPath)
Push-Location $root
try {
    [ordered]@{commit=(git rev-parse HEAD);changes=@(git status --porcelain);date=(Get-Date -Format o);
        expected_ids=$ids;runtime=$Godot;template=$Template;cpu=(Get-CimInstance Win32_Processor).Name;
        gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion);
        resolution='1600x900';renderer='Forward+';physics='Jolt Physics';frame_gates_ms=@{p95=20;p99=33;max=50};
        source_hashes=@(Get-ChildItem scripts -Filter '*.gd' -Recurse | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash)} |
        ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidence 'environment.json') -Encoding UTF8
    $import=Invoke-Import $Godot $evidence $root 180
    if($import.Code -ne 0){throw 'Import falhou'}
    $sceneArgs=@('--path','.','res://scenes/main.tscn','--','--p36-selftest')
    Invoke-SelftestStep 'editor_headless' 'editor_headless.log' $Godot (@('--headless')+$sceneArgs) (Join-Path $evidence 'editor_headless.json') $ids
    $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
    Invoke-SelftestStep 'editor_window' 'editor_window.log' $Godot $sceneArgs (Join-Path $evidence 'editor_window.json') $ids
    $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
    # Local override for this machine only. Always restore the tracked preset bytes.
    $localPreset=[System.Text.Encoding]::UTF8.GetString($originalPreset) -replace 'custom_template/release="[^"]*"',('custom_template/release="'+$Template.Replace([char]92,[char]47)+'"')
    [System.IO.File]::WriteAllText($presetPath,$localPreset,[System.Text.UTF8Encoding]::new($false))
    $results['export']=Invoke-Native $Godot @('--headless','--path','.','--export-release','Windows Desktop','build/elemental_ruins.exe') (Join-Path $evidence 'export.log') $root 180
    if($results['export'] -ne 0){throw 'Export falhou'}
    $exe=Join-Path $root 'build/elemental_ruins.exe'
    Invoke-SelftestStep 'export_headless' 'export_headless.log' $exe @('--headless','--','--p36-selftest') (Join-Path $evidence 'export_headless.json') $ids
    $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
    Invoke-SelftestStep 'export_window' 'export_window.log' $exe @('--','--p36-selftest') (Join-Path $evidence 'export_window.json') $ids
    $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
    # The inherited persistence test has a fixed expected-state filename. Preserve
    # its prior bytes and copy this run's fixture into the new evidence directory.
    foreach($runtimeMode in @('editor','export')) {
        $expectedPath=if($runtimeMode -eq 'editor'){Join-Path $root 'docs/evidence/p36/final/p1_persist_expected.json'}else{Join-Path $env:APPDATA 'Godot/app_userdata/ELEMENTAL -- RUINS/p1_persist_expected.json'}
        $expectedExisted=Test-Path -LiteralPath $expectedPath
        $expectedBytes=if($expectedExisted){[System.IO.File]::ReadAllBytes($expectedPath)}else{$null}
        try {
            foreach($phase in @('write','read')) {
                $name=$runtimeMode+'_persist_'+$phase
                $persistExe=if($runtimeMode -eq 'editor'){$Godot}else{$exe}
                $persistArgs=if($runtimeMode -eq 'editor'){@('--headless','--path','.','res://scenes/main.tscn','--','--p36-selftest',('--p1-persist='+$phase))}else{@('--headless','--','--p36-selftest',('--p1-persist='+$phase))}
                Invoke-SelftestStep $name ($name+'.log') $persistExe $persistArgs (Join-Path $evidence ($name+'.json')) @(Get-SelftestIds ('persist_'+$phase))
                if($phase -eq 'write' -and (Test-Path -LiteralPath $expectedPath)){Copy-Item -LiteralPath $expectedPath -Destination (Join-Path $evidence ($runtimeMode+'_persist_expected.json'))}
                $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
            }
        } finally {
            if($expectedExisted){[System.IO.File]::WriteAllBytes($expectedPath,$expectedBytes)}elseif(Test-Path -LiteralPath $expectedPath){Remove-Item -LiteralPath $expectedPath}
        }
    }
    if(@($results.Values | Where-Object {$_ -ne 0}).Count){exit 1}
} finally {
    [System.IO.File]::WriteAllBytes($presetPath,$originalPreset)
    Pop-Location
}
