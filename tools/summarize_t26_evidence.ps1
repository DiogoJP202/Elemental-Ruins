<#
Consolida SOMENTE evidencias existentes; nao inicia Godot nem modifica fontes/relatorios.
Todos os casos de cada summary entram no CSV, inclusive FAIL e series interrompidas.
Ausencia ou JSON ainda sendo gravado permanece PENDING, nunca PASS implicito.
O runner continua sendo o responsavel pelo run_id novo e frescor por execucao.
#>
param(
    [string]$EvidenceDirectory = (Join-Path (Split-Path $PSScriptRoot) 'docs/evidence/p36/t26_stabilization')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib_selftest_contract.ps1')
$evidenceRoot = [System.IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

function Get-Field($SourceObject, [string]$Path, $Default = $null) {
    $value = $SourceObject
    foreach ($part in $Path.Split('.')) {
        if ($null -eq $value) { return $Default }
        if ($value -is [System.Collections.IDictionary]) {
            if (-not $value.Contains($part)) { return $Default }
            $value = $value[$part]
        } else {
            $property = $value.PSObject.Properties[$part]
            if ($null -eq $property) { return $Default }
            $value = $property.Value
        }
    }
    if ($null -eq $value) { return $Default }
    return $value
}

function Get-FirstField($SourceObject, [string[]]$Paths) {
    foreach ($path in $Paths) {
        $value = Get-Field $SourceObject $path
        if ($null -ne $value) { return $value }
    }
    return $null
}

function Read-JsonSnapshot([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ state = 'PENDING'; data = $null; reason = 'file absent'; path = $Path }
    }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            $json = [System.IO.File]::ReadAllText($Path)
            if ([string]::IsNullOrWhiteSpace($json)) { throw 'empty file' }
            $data = $json | ConvertFrom-Json
            if ($null -eq $data) { throw 'null JSON root' }
            return [pscustomobject]@{ state = 'AVAILABLE'; data = $data; reason = ''; path = $Path }
        } catch {
            $lastReason = $_.Exception.Message
            if ($attempt -lt 2) { Start-Sleep -Milliseconds 40 }
        }
    }
    return [pscustomobject]@{ state = 'PENDING'; data = $null; reason = ('unreadable/in progress: ' + $lastReason); path = $Path }
}

function Get-LogSnapshot([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ available = $false; errors = $null; warnings = $null; reason = 'log absent' }
    }
    $logText = [System.IO.File]::ReadAllText($Path)
    return [pscustomobject]@{
        available = $true
        errors = [regex]::Matches($logText, '(?m)^(SCRIPT ERROR|ERROR):').Count
        warnings = [regex]::Matches($logText, '(?m)^WARNING:').Count
        reason = (Test-GodotLog $Path)
    }
}

function Get-Benchmark($Report, [string]$Id, [bool]$WindowMode) {
    $test = @((Get-Field $Report 'resultados') | Where-Object { $_.id -ceq $Id })
    if ($test.Count -ne 1) {
        return [pscustomobject]@{ id = $Id; status = 'PENDING'; criterio_fps_aplicado = $null; reason = 'test absent/duplicate' }
    }
    $details = $test[0].detalhes
    $applied = Get-Field $details 'criterio_fps_aplicado'
    $p95 = Get-Field $details 'intervalo_entre_quadros_ms.p95'
    $p99 = Get-Field $details 'intervalo_entre_quadros_ms.p99'
    $max = Get-Field $details 'intervalo_entre_quadros_ms.max'
    $policyOk = ($applied -is [bool]) -and ($applied -eq $WindowMode)
    $measured = ($null -ne $p95) -and ($null -ne $p99) -and ($null -ne $max)
    $within = $null
    if ($WindowMode -and $measured) {
        $within = [double]$p95 -le 20.0 -and [double]$p99 -le 33.0 -and [double]$max -le 50.0
    }
    $valid = $policyOk -and (-not $WindowMode -or ($measured -and $within))
    return [pscustomobject]@{
        id = $Id; status = $(if ($valid) { 'PASS' } else { 'FAIL' })
        criterio_fps_aplicado = $applied; p95_ms = $p95; p99_ms = $p99; max_ms = $max
        limits_ms = @{ p95 = 20.0; p99 = 33.0; max = 50.0 }
        within_window_limits = $within; flag_matches_mode = $policyOk
        reason = $(if ($valid) { '' } else { 'benchmark flag or unchanged 20/33/50 ms gate failed' })
    }
}

$seriesSpecifications = @(
    @{ name = 'causal_v1'; expected = 16; role = 'historical causal groups; failures retained' },
    @{ name = 'contacts'; expected = 2; role = 'historical contacts diagnostic' },
    @{ name = 'post_fix_30'; expected = 60; role = 'first expanded series; includes its FAIL' },
    @{ name = 'stationary_post_fix_30'; expected = 30; role = 'prospective natural-rest series; required' },
    @{ name = 'baseline_t26'; expected = 8; role = 'baseline reference' },
    @{ name = 'candidate_smoke'; expected = 2; role = 'candidate smoke' },
    @{ name = 'original_post_fix_30'; expected = 30; role = 'interrupted legacy protocol; partial stays partial' },
    @{ name = 'corrected_t26_smoke'; expected = 1; role = 'natural-rest protocol smoke' }
)
$rows = [System.Collections.Generic.List[object]]::new()
$seriesSummary = [System.Collections.Generic.List[object]]::new()
foreach ($spec in $seriesSpecifications) {
    $summaryPath = Join-Path $evidenceRoot ($spec.name + '/summary.json')
    $snapshot = Read-JsonSnapshot $summaryPath
    $entries = @()
    if ($snapshot.state -eq 'AVAILABLE') { $entries = @($snapshot.data) }
    $seriesRows = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $entries) {
        $repeat = Get-FirstField $entry @('repetition', 'trial', 'details.repeat')
        $sourceReport = Get-Field $entry 'report'
        if ([string]::IsNullOrWhiteSpace($sourceReport) -and $null -ne $repeat) {
            $sourceReport = Join-Path (Split-Path $summaryPath) ('trial_{0:d2}.json' -f [int]$repeat)
        }
        $reportSnapshot = Read-JsonSnapshot $sourceReport
        $report = $reportSnapshot.data
        $t26 = @((Get-Field $report 'resultados') | Where-Object { $_.id -ceq 'T26' })
        $t26Details = $null
        if ($t26.Count -eq 1) { $t26Details = Get-Field $t26[0] 'detalhes.A_salvar_com_torre_caida' }
        $setup = Get-Field $entry 'details.setup_status'
        if ($null -eq $setup) {
            $settled = Get-Field $entry 'details.settled'
            if ($null -eq $settled) { $settled = Get-Field $t26Details 'cena_parada_antes' }
            if ($null -ne $settled) { $setup = $(if ($settled) { 'SETTLED_REPORTED' } else { 'NOT_SETTLED_REPORTED' }) }
        }
        $endpoint = Get-FirstField $entry @('details.after_1_5s.max_m', 'max_shift_m')
        $control = Get-FirstField $entry @('details.control_without_save_2s.max_m', 'control_m')
        $immediate = Get-FirstField $entry @('details.immediate_shift.max_m', 'worst.mudou_durante_save_m')
        $peak = Get-Field $entry 'details.peak_after_1_5s.max_m'
        $errors = Get-Field $report 'erros_motor' (Get-Field $entry 'errors')
        $warnings = Get-Field $report 'avisos_motor' (Get-Field $entry 'warnings')
        $row = [pscustomobject][ordered]@{
            series = $spec.name
            layout = (Get-Field $entry 'layout' 'tower')
            scenario = (Get-Field $entry 'scenario' 'T26')
            repetition = $repeat
            case_name = (Get-Field $entry 'name' ('trial_{0:d2}' -f [int]$repeat))
            status = (Get-Field $entry 'status' 'PENDING')
            setup = $setup
            control_m = $control
            immediate_m = $immediate
            endpoint_m = $endpoint
            peak_m = $peak
            threshold_m = 0.1
            endpoint_below_threshold = $(if ($null -ne $endpoint) { [double]$endpoint -lt 0.1 } else { $null })
            peak_below_threshold = $(if ($null -ne $peak) { [double]$peak -lt 0.1 } else { $null })
            control_natural_rest_ok = (Get-Field $entry 'details.natural_control.stable')
            exit_code = (Get-FirstField $entry @('exit_code', 'exit'))
            errors = $errors
            warnings = $warnings
            run_id = (Get-Field $report 'run_id')
            source_report_state = $reportSnapshot.state
            source_report = $sourceReport
            source_summary = $summaryPath
        }
        $rows.Add($row)
        $seriesRows.Add($row)
    }
    $passed = @($seriesRows | Where-Object status -ceq 'PASS').Count
    $failed = @($seriesRows | Where-Object status -ceq 'FAIL').Count
    $observed = $seriesRows.Count
    $state = 'COMPLETE'
    if ($snapshot.state -ne 'AVAILABLE' -or $observed -lt $spec.expected) { $state = 'PARTIAL_OR_PENDING' }
    if ($observed -gt $spec.expected) { $state = 'UNEXPECTED_EXTRA_CASES' }
    $seriesSummary.Add([pscustomobject]@{
        name = $spec.name; role = $spec.role; status = $state; expected = $spec.expected; observed = $observed
        passed = $passed; failed = $failed; other = $observed - $passed - $failed
        max_endpoint_m = $(if (@($seriesRows | Where-Object { $null -ne $_.endpoint_m }).Count) {
            ($seriesRows | Measure-Object -Property endpoint_m -Maximum).Maximum } else { $null })
        max_peak_m = $(if (@($seriesRows | Where-Object { $null -ne $_.peak_m }).Count) {
            ($seriesRows | Measure-Object -Property peak_m -Maximum).Maximum } else { $null })
        source = $summaryPath; read_state = $snapshot.state; reason = $snapshot.reason
    })
}

$fullDirectory = Join-Path $evidenceRoot 'full'
$stepsSnapshot = Read-JsonSnapshot (Join-Path $fullDirectory 'steps.json')
$fullModes = [System.Collections.Generic.List[object]]::new()
$persistence = [System.Collections.Generic.List[object]]::new()
$reportSpecifications = @(
    @{ name = 'editor_headless'; suite = 'p36'; window = $false },
    @{ name = 'editor_window'; suite = 'p36'; window = $true },
    @{ name = 'export_headless'; suite = 'p36'; window = $false },
    @{ name = 'export_window'; suite = 'p36'; window = $true },
    @{ name = 'editor_persist_write'; suite = 'persist_write'; window = $false },
    @{ name = 'editor_persist_read'; suite = 'persist_read'; window = $false },
    @{ name = 'export_persist_write'; suite = 'persist_write'; window = $false },
    @{ name = 'export_persist_read'; suite = 'persist_read'; window = $false }
)
foreach ($spec in $reportSpecifications) {
    $reportPath = Join-Path $fullDirectory ($spec.name + '.json')
    $snapshot = Read-JsonSnapshot $reportPath
    $report = $snapshot.data
    $expectedIds = @(Get-SelftestIds $spec.suite)
    $logSnapshot = Get-LogSnapshot (Join-Path $fullDirectory ($spec.name + '.log'))
    $exitCode = Get-Field $stepsSnapshot.data $spec.name
    $status = 'PENDING'
    $reason = $snapshot.reason
    $contractReason = $null
    $benchmarks = @()
    if ($snapshot.state -eq 'AVAILABLE') {
        # Static consolidation checks the explicit ID contract. Freshness/run-id generation
        # were checked against t0 by Invoke-SelftestStep, reflected by its recorded exit code.
        $contractReason = Test-SelftestReport $reportPath ([string](Get-Field $report 'run_id')) $expectedIds ([datetime]::MinValue)
        if ($spec.suite -eq 'p36') {
            $benchmarks = @((Get-Benchmark $report 'T27' $spec.window), (Get-Benchmark $report 'T37' $spec.window))
        }
        $benchmarkFailure = @($benchmarks | Where-Object status -cne 'PASS').Count -gt 0
        if ($contractReason -ne '' -or $logSnapshot.reason -ne '' -and $logSnapshot.available -or
            $benchmarkFailure -or ($null -ne $exitCode -and $exitCode -ne 0)) {
            $status = 'FAIL'
            $reason = @($contractReason, $logSnapshot.reason,
                $(if ($benchmarkFailure) { 'benchmark policy/limits failed' }),
                $(if ($null -ne $exitCode -and $exitCode -ne 0) { 'runner exit=' + $exitCode })) |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $reason = $reason -join '; '
        } elseif ($null -eq $exitCode -or -not $logSnapshot.available) {
            $reason = 'awaiting runner steps entry or log'
        } else {
            $status = 'PASS'
            $reason = ''
        }
    }
    $t26 = @((Get-Field $report 'resultados') | Where-Object { $_.id -ceq 'T26' })
    $t26Maximum = $null
    if ($t26.Count -eq 1) { $t26Maximum = Get-Field $t26[0] 'detalhes.A_salvar_com_torre_caida.maior_deslocamento_m' }
    $item = [pscustomobject]@{
        name = $spec.name; status = $status; reason = $reason; run_id = (Get-Field $report 'run_id')
        report_date = (Get-Field $report 'data'); complete = (Get-Field $report 'completo')
        expected_count = $expectedIds.Count; total = (Get-Field $report 'testes_total')
        passed_count = (Get-Field $report 'testes_pass')
        individual_count = $(if ($snapshot.state -eq 'AVAILABLE') { @($report.resultados).Count } else { 0 })
        t26_max_m = $t26Maximum; errors = (Get-Field $report 'erros_motor'); warnings = (Get-Field $report 'avisos_motor')
        log_errors = $logSnapshot.errors; log_warnings = $logSnapshot.warnings; runner_exit_code = $exitCode
        contract_validation = $contractReason; freshness_validation = 'owned by runner Invoke-SelftestStep(t0, run_id)'
        benchmarks = $benchmarks; report = $reportPath
    }
    if ($spec.suite -eq 'p36') { $fullModes.Add($item) } else { $persistence.Add($item) }
}

$edgePath = Join-Path $evidenceRoot 'edge_save_7.json'
$edgeSnapshot = Read-JsonSnapshot $edgePath
$edgeLog = Get-LogSnapshot (Join-Path $evidenceRoot 'edge_save_7.log')
$edge = [ordered]@{ status = 'PENDING'; report = $edgePath; total = $null; failed = $null; log_errors = $edgeLog.errors; log_warnings = $edgeLog.warnings }
if ($edgeSnapshot.state -eq 'AVAILABLE') {
    $edgeIds = @($edgeSnapshot.data.tests | ForEach-Object { $_.id })
    $edgeExpected = @('E1','E2','E3','E4','E5','E6','E7')
    $edgeOk = $edgeSnapshot.data.passed -eq $true -and $edgeSnapshot.data.failed -eq 0 -and $edgeSnapshot.data.total -eq 7 `
        -and $edgeIds.Count -eq 7 -and @($edgeIds | Select-Object -Unique).Count -eq 7 `
        -and @($edgeExpected | Where-Object { $edgeIds -cnotcontains $_ }).Count -eq 0 `
        -and @($edgeSnapshot.data.tests | Where-Object { $_.passed -ne $true }).Count -eq 0
    $edge.status = $(if (-not $edgeOk -or ($edgeLog.available -and $edgeLog.reason -ne '')) { 'FAIL' }
        elseif (-not $edgeLog.available) { 'PENDING' } else { 'PASS' })
    $edge.total = $edgeSnapshot.data.total
    $edge.failed = $edgeSnapshot.data.failed
    $edge['ids'] = $edgeIds
}

$wakePath = Join-Path $evidenceRoot 'wake_pose_final.json'
$wakeSnapshot = Read-JsonSnapshot $wakePath
$wakeLog = Get-LogSnapshot (Join-Path $evidenceRoot 'wake_pose_final.log')
$wake = [ordered]@{ status = 'PENDING'; role = 'diagnostic experiment, not a gameplay gate'; report = $wakePath }
if ($wakeSnapshot.state -eq 'AVAILABLE') {
    $wakeData = $wakeSnapshot.data
    $wakeOk = $wakeData.experiment_valid -eq $true -and $wakeData.hypothesis_supported -eq $true `
        -and $wakeData.errors_warnings.errors -eq 0 -and $wakeData.errors_warnings.warnings -eq 0
    $wake.status = $(if (-not $wakeOk -or ($wakeLog.available -and $wakeLog.reason -ne '')) { 'FAIL' }
        elseif (-not $wakeLog.available) { 'PENDING' } else { 'PASS' })
    $wake['experiment_valid'] = $wakeData.experiment_valid
    $wake['hypothesis_supported'] = $wakeData.hypothesis_supported
    $wake['errors_warnings'] = $wakeData.errors_warnings
    $wake['cases'] = @($wakeData.results | Select-Object intervention,initial_state_ok,elapsed_physics_frames,final_shift_m,peak_shift_m,moved_over_t26_limit)
}

$requiredReports = @($fullModes.ToArray()) + @($persistence.ToArray())
$fullStatus = 'PASS'
if (@($requiredReports | Where-Object status -ceq 'FAIL').Count) { $fullStatus = 'FAIL' }
elseif (@($requiredReports | Where-Object status -cne 'PASS').Count) { $fullStatus = 'PENDING' }
$naturalSeries = @($seriesSummary | Where-Object name -ceq 'stationary_post_fix_30')[0]
$naturalStatus = 'PENDING'
if ($naturalSeries.failed -gt 0 -or $naturalSeries.status -eq 'UNEXPECTED_EXTRA_CASES') { $naturalStatus = 'FAIL' }
elseif ($naturalSeries.observed -eq 30 -and $naturalSeries.passed -eq 30 -and $naturalSeries.status -eq 'COMPLETE') { $naturalStatus = 'PASS' }
$requiredStatuses = @($fullStatus, $naturalStatus, $edge.status, $wake.status)
$overallStatus = 'PASS'
if ($requiredStatuses -ccontains 'FAIL') { $overallStatus = 'FAIL' }
elseif (@($requiredStatuses | Where-Object { $_ -cne 'PASS' }).Count) { $overallStatus = 'PENDING' }
$consolidated = [ordered]@{
    generated_utc = [datetime]::UtcNow.ToString('o')
    evidence_directory = $evidenceRoot
    overall_status = $overallStatus
    passed = $overallStatus -ceq 'PASS'
    overall_scope = 'four full modes + four persistence phases + prospective natural-rest 30 + E1-E7 + wake diagnostic validity'
    historical_failures_are_retained = $true
    historical_or_interrupted_series_are_not_reclassified_by_later_passes = $true
    thresholds = @{ displacement_m = 0.1; window_frame_ms = @{ p95 = 20; p99 = 33; max = 50 } }
    repetition_rows = $rows.Count
    series = $seriesSummary.ToArray()
    prospective_natural_rest_status = $naturalStatus
    full_gate_status = $fullStatus
    full_modes = $fullModes.ToArray()
    persistence = $persistence.ToArray()
    edge_cases = $edge
    wake_diagnostic = $wake
    source_steps_state = $stepsSnapshot.state
    note = 'Absent/in-progress outputs remain PENDING. Null CSV metrics were not measured in that source. Static report validation does not replace runner freshness validation.'
}

$csvPath = Join-Path $evidenceRoot 'repetition_maxima.csv'
$jsonPath = Join-Path $evidenceRoot 'fullsummary.json'
$rows.ToArray() | Export-Csv -LiteralPath ($csvPath + '.tmp') -NoTypeInformation -Encoding UTF8
Move-Item -LiteralPath ($csvPath + '.tmp') -Destination $csvPath -Force
$consolidated | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath ($jsonPath + '.tmp') -Encoding UTF8
Move-Item -LiteralPath ($jsonPath + '.tmp') -Destination $jsonPath -Force
Write-Output ('Consolidated {0} repetition cases; full={1}; prospective30={2}; overall={3}' -f $rows.Count,$fullStatus,$naturalStatus,$overallStatus)
Write-Output $csvPath
Write-Output $jsonPath
