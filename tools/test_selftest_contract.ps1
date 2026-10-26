param([string]$EvidenceDirectory = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib_selftest_contract.ps1')
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path (Split-Path $PSScriptRoot) 'docs/evidence/p36/preparation/contracts' }
New-Item -ItemType Directory -Force $EvidenceDirectory | Out-Null
$fixture = Join-Path $EvidenceDirectory 'fixture.tmp'
$ids = Get-SelftestIds 'p0'
$checks = [System.Collections.Generic.List[object]]::new()
function Check([string]$Name, [scriptblock]$Mutate, [bool]$ExpectedValid = $false) {
    $r = [pscustomobject]@{run_id='contract-test';completo=$true;testes_total=12;testes_pass=12;
        resultado_geral='PASS';erros_motor=0;avisos_motor=0;testes_ids=@($ids);
        resultados=@($ids | ForEach-Object { [pscustomobject]@{id=$_;status='PASS'} })}
    & $Mutate $r
    $r | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fixture -Encoding UTF8
    $since = (Get-Date).AddSeconds(-2)
    if ($Name -eq 'antigo') { (Get-Item -LiteralPath $fixture).LastWriteTime = (Get-Date).AddMinutes(-5) }
    if ($Name -eq 'json_invalido') { Set-Content -LiteralPath $fixture -Value '{' }
    $reason = Test-SelftestReport $fixture 'contract-test' $ids $since
    $ok = ($reason -eq '') -eq $ExpectedValid
    $checks.Add([pscustomobject]@{case=$Name;passed=$ok;reason=$reason})
    Write-Host "$Name : $ok $reason"
}
Check 'valido' {} $true
Check 'erro_motor' {param($r) $r.erros_motor=1}
Check 'aviso_motor' {param($r) $r.avisos_motor=1}
Check 'contador_ausente' {param($r) $r.PSObject.Properties.Remove('erros_motor')}
Check 'contador_texto' {param($r) $r.erros_motor='0'}
Check 'contador_negativo' {param($r) $r.avisos_motor=-1}
Check 'contador_fracionario' {param($r) $r.testes_total=12.1}
Check 'execucao_errada' {param($r) $r.run_id='outra'}
Check 'incompleto' {param($r) $r.completo=$false}
Check 'booleano_texto' {param($r) $r.completo='true'}
Check 'total_errado' {param($r) $r.testes_total=13}
Check 'resumo_falso' {param($r) $r.testes_pass=11}
Check 'resultado_individual_fail' {param($r) $r.resultados[5].status='FAIL'}
Check 'resultado_individual_sem_status' {param($r) $r.resultados[5].PSObject.Properties.Remove('status')}
Check 'id_duplicado' {param($r) $r.resultados[5].id=$r.resultados[4].id}
Check 'id_inesperado' {param($r) $r.resultados[5].id='T999'}
Check 'id_case_errado' {param($r) $r.resultados[5].id='t3b'}
Check 'id_omitido' {param($r) $r.resultados=@($r.resultados | Select-Object -Skip 1)}
Check 'lista_ids_falsa' {param($r) $r.testes_ids[3]='T999'}
Check 'sem_resultados' {param($r) $r.resultados=$null}
Check 'antigo' {}
Check 'json_invalido' {}
$missing = Test-SelftestReport (Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString()+'.json')) 'contract-test' $ids (Get-Date)
$checks.Add([pscustomobject]@{case='ausente';passed=($missing -ne '');reason=$missing})
foreach ($header in @('ERROR: shutdown failure','WARNING: startup warning','SCRIPT ERROR: parse failure')) {
    Set-Content -LiteralPath $fixture -Value $header -Encoding UTF8
    $checks.Add([pscustomobject]@{case=$header;passed=((Test-GodotLog $fixture) -ne '');reason='log rejects motor diagnostic'})
}
$checks | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $EvidenceDirectory 'results.json') -Encoding UTF8
if (@($checks | Where-Object { -not $_.passed }).Count) { exit 1 }
Write-Host "PASS $($checks.Count)/$($checks.Count)"
