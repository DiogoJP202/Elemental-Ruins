param([string]$Godot=$env:GODOT, [int]$Count=8, [string]$Label='baseline_t26')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$root=Split-Path $PSScriptRoot
$evidence=Join-Path $root ('docs/evidence/p36/t26_stabilization/'+$Label)
New-Item -ItemType Directory -Force $evidence | Out-Null
$Godot=Resolve-Godot $Godot
$summary=@()
foreach($repeatIndex in 1..$Count) {
    $trialName='trial_{0:d2}' -f $repeatIndex
    $reportPath=(Join-Path $evidence ($trialName+'.json')).Replace([char]92,[char]47)
    $exitValue=Invoke-Native $Godot @('--headless','--path',$root,'res://scenes/main.tscn','--','--p36-selftest','--only=T14,T26',('--run-id='+$Label+'-'+$trialName),('--report='+$reportPath)) (Join-Path $evidence ($trialName+'.log')) $root 180
    if(-not (Test-Path -LiteralPath $reportPath)) {throw ('Relatorio ausente: '+$reportPath)}
    $reportData=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $caseResult=$reportData.resultados | Where-Object {$_.id -eq 'T26'}
    if(-not $caseResult) {throw ('T26 ausente: '+$reportPath)}
    $caseData=$caseResult.detalhes.A_salvar_com_torre_caida
    $entry=[ordered]@{trial=$repeatIndex;exit=$exitValue;status=$caseResult.status;max_shift_m=$caseData.maior_deslocamento_m;worst=$caseData.pior_peca;control_m=$caseData.controle_sem_save_2s_m;errors=$reportData.erros_motor;warnings=$reportData.avisos_motor}
    $summary+=$entry
    $entry | ConvertTo-Json -Depth 8 -Compress | Write-Output
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
}
