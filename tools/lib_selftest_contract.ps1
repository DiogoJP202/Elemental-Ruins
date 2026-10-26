# Contratos explícitos dos gates. Não derivar IDs do relatório sob teste.
function Get-SelftestIds([string]$Suite) {
    $p0 = @('T1','T0','T1b','T2','T3a','T3b','T4','T5','T5b','T6','T7','T7b')
    $p1 = $p0 + @('T8','T8b','T9','T10','T11','T12','T13','T14','T15','T16','T17')
    $p2 = $p1 + @('T18','T19','T20','T21','T22','T23','T24','T25','T26','T27')
    $p3 = $p2 + @('T38','T28','T29','T30','T31','T32','T33','T34','T35','T36','T37')
    $p35 = $p3 + @('T39','T40','T41','T42','T43','T44','T45')
    switch -CaseSensitive ($Suite) {
        'p0' { return $p0 }
        'p1' { return $p1 }
        'p2' { return $p2 }
        'p3' { return $p3 }
        'p35' { return $p35 }
        'p36' { return ($p35 + @('T46','T47','T48','T49','T50','T51','T52','T53','T54','T56','T57')) }
        'persist_write' { return @('T1','T14x-write') }
        'persist_read' { return @('T1','T14x-read') }
        default { throw "Bateria sem contrato: $Suite" }
    }
}

function Test-GodotLog([string]$LogPath) {
    $content = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
    if ($content -match '(?m)^(SCRIPT ERROR|ERROR|WARNING):') { return 'erro/aviso do motor no log do processo' }
    return ''
}

# Sem allowlist ativa: todo erro/aviso invalida o gate. Uma exceção futura exige
# identificação exata e justificativa versionada; não há filtro por substring.
function Test-SelftestReport([string]$ReportPath, [string]$RunId, [string[]]$ExpectedIds, [datetime]$NotBefore) {
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { return "relatório não foi gravado ($ReportPath)" }
    if ((Get-Item -LiteralPath $ReportPath).LastWriteTime -lt $NotBefore) { return 'relatório é anterior a esta execução' }
    try { $r = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return "relatório ilegível: $($_.Exception.Message)" }
    if ($null -eq $r -or $r -is [array]) { return 'raiz do relatório inválida' }
    if ($ExpectedIds.Count -eq 0 -or @($ExpectedIds | Select-Object -Unique).Count -ne $ExpectedIds.Count) { return 'contrato vazio ou duplicado' }
    foreach ($field in @('run_id','completo','testes_total','testes_pass','resultado_geral','erros_motor','avisos_motor','resultados','testes_ids')) {
        if ($null -eq $r.PSObject.Properties[$field]) { return "campo obrigatório ausente: $field" }
    }
    if ($r.run_id -isnot [string] -or $r.run_id -cne $RunId) { return 'run_id não corresponde à execução atual' }
    if ($r.completo -isnot [bool] -or $r.completo -ne $true) { return 'execução incompleta' }
    foreach ($field in @('testes_total','testes_pass','erros_motor','avisos_motor')) {
        $v = $r.$field
        if (($v -isnot [int] -and $v -isnot [long]) -or $v -lt 0) { return "contador inválido: $field" }
    }
    if ($r.erros_motor -ne 0 -or $r.avisos_motor -ne 0) { return "motor: $($r.erros_motor) erros, $($r.avisos_motor) avisos (gate exige zero)" }
    if ($r.resultado_geral -cne 'PASS') { return 'resultado geral não aprovado' }
    if ($r.testes_total -ne $ExpectedIds.Count -or $r.testes_pass -ne $ExpectedIds.Count) { return 'contagem do resumo difere do contrato' }
    if ($r.resultados -isnot [array] -or $r.testes_ids -isnot [array]) { return 'resultados e testes_ids devem ser arrays' }
    if ($r.resultados.Count -ne $ExpectedIds.Count -or $r.testes_ids.Count -ne $ExpectedIds.Count) { return 'quantidade de resultados individuais inválida' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $r.resultados) {
        if ($entry.id -isnot [string] -or $entry.status -cne 'PASS') { return 'resultado individual inválido ou diferente de PASS' }
        if (-not $seen.Add($entry.id)) { return "ID duplicado: $($entry.id)" }
        if ($ExpectedIds -cnotcontains $entry.id) { return "ID inesperado: $($entry.id)" }
    }
    foreach ($id in $ExpectedIds) { if (-not $seen.Contains($id)) { return "ID omitido: $id" } }
    for ($i = 0; $i -lt $r.resultados.Count; $i++) {
        if ($r.testes_ids[$i] -isnot [string] -or $r.testes_ids[$i] -cne $r.resultados[$i].id) { return 'testes_ids não corresponde aos resultados individuais' }
    }
    return ''
}
