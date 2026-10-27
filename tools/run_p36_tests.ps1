param([string]$Godot=$env:GODOT, [string]$Stage='final', [string]$TestIds='', [switch]$Window, [switch]$Export)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
if($Stage -notin @('m1','m2','m3','final')) { throw 'Stage inválido' }
$root=Split-Path $PSScriptRoot
$evidence=Join-Path $root ('docs/evidence/p36/'+$Stage)
$results=[ordered]@{}
$StepTimeoutSec=1200
$Godot=Resolve-Godot $Godot
New-Item -ItemType Directory -Force $evidence | Out-Null
$ids=@(Get-SelftestIds 'p36')
$userArgs=@('--p36-selftest',"--evidence-stage=$Stage")
if($TestIds){
    $selected=@($TestIds.Split(',') | ForEach-Object {if($_ -eq 'T3') {'T3a';'T3b'} else {$_}})
    foreach($id in $selected){if($ids -cnotcontains $id){throw "ID fora do contrato: $id"}}
    $ids=@(@('T1')+$selected | Select-Object -Unique)
    $userArgs += "--only=$TestIds"
}
function Report([string]$Name){return ((Join-Path $evidence $Name) -replace '\\','/')}
Push-Location $root
try {
    [ordered]@{commit=(git rev-parse HEAD);changes=@(git status --porcelain);date=(Get-Date -Format o);
        stage=$Stage;expected_ids=$ids;cpu=(Get-CimInstance Win32_Processor).Name;
        gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion);
        resolution='1600x900 configured';renderer='Forward+';physics='Jolt Physics';
        frame_gates_ms=@{p95=20;p99=33;max=50};human_playtest='NAO TESTADO'} |
        ConvertTo-Json -Depth 6 | Set-Content (Join-Path $evidence 'environment.json') -Encoding UTF8
    $imp=Invoke-Import $Godot $evidence $root 180
    if($imp.Code -ne 0){throw 'Import falhou'}
    Invoke-SelftestStep 'editor_headless' 'editor_headless.log' $Godot (@('--headless','--path','.','res://scenes/main.tscn','--')+$userArgs) (Report 'editor_headless.json') $ids
    if($Window){Invoke-SelftestStep 'editor_window' 'editor_window.log' $Godot (@('--path','.','res://scenes/main.tscn','--')+$userArgs+@('--p36-screenshots')) (Report 'editor_window.json') $ids}
    if($Export){
        Assert-ExportTemplate $root
        $exportCode=Invoke-Native $Godot @('--headless','--path','.','--export-release','Windows Desktop','build/elemental_ruins.exe') (Join-Path $evidence 'export.log') $root 180
        $results['export']=$exportCode
        if($exportCode -ne 0){throw 'Export falhou'}
        $exe=Join-Path $root 'build/elemental_ruins.exe'
        Invoke-SelftestStep 'export_headless' 'export_headless.log' $exe (@('--headless','--')+$userArgs) (Report 'export_headless.json') $ids
        if($Window){Invoke-SelftestStep 'export_window' 'export_window.log' $exe (@('--')+$userArgs+@('--p36-screenshots')) (Report 'export_window.json') $ids}
    }
    $results | ConvertTo-Json | Set-Content (Join-Path $evidence 'steps.json') -Encoding UTF8
    if(@($results.Values | Where-Object {$_ -ne 0}).Count){exit 1}
} finally {Pop-Location}
