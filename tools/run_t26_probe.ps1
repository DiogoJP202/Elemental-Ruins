param(
    [string]$Godot = $env:GODOT,
    [ValidateRange(1, 30)][int]$Repetitions = 30,
    [ValidateSet('A','B','C','D')][string[]]$Scenarios = @('A','B','C'),
    [ValidateSet('tower','stack')][string[]]$Layouts = @('tower','stack'),
    [ValidateRange(1, 600)][int]$PauseFrames = 15,
    [switch]$RestoreState,
    [switch]$Contacts,
    [switch]$Trace = $true,
    [switch]$KeepRawTrace,
    [switch]$NaturalRest,
    [switch]$ArchiveOnly,
    [switch]$Window,
    [switch]$SkipImport,
    [string]$OutputDirectory = '',
    [int]$StepTimeoutSec = 240
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib_godot_process.ps1')
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) {
    if ($ArchiveOnly) { throw '-ArchiveOnly requires an explicit existing -OutputDirectory' }
    $tag = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputDirectory = Join-Path $root "docs/evidence/p36/t26_stabilization/probe_$tag"
}
$evidence = [System.IO.Path]::GetFullPath($OutputDirectory)
if ($ArchiveOnly) {
    if (-not (Test-Path -LiteralPath $evidence -PathType Container)) { throw "Evidence directory missing: $evidence" }
} else {
    New-Item -ItemType Directory -Force -Path $evidence | Out-Null
}
$results = [ordered]@{}
$summary = [System.Collections.Generic.List[object]]::new()
$archiveMap = [System.Collections.Generic.List[object]]::new()
$expectedIds = @('T1','PROBE')
$mode = if ($Window) { 'window' } else { 'headless' }

function Compress-ProbeTrace([string]$ReportPath) {
    $rawName = [System.IO.Path]::GetFileNameWithoutExtension($ReportPath) + '_trace.json'
    $rawPath = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetDirectoryName($ReportPath)) $rawName))
    $archivePath = [System.IO.Path]::ChangeExtension($rawPath, '.zip')
    $boundary = $evidence.TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $rawPath.StartsWith($boundary, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $archivePath.StartsWith($boundary, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Trace must stay inside this experiment's evidence directory: $rawPath"
    }
    if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) { throw "Expected trace is missing: $rawPath" }
    $rawSize = (Get-Item -LiteralPath $rawPath).Length
    $rawHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $rawPath).Hash
    Compress-Archive -LiteralPath $rawPath -DestinationPath $archivePath -CompressionLevel Optimal -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entry = $archive.GetEntry([System.IO.Path]::GetFileName($rawPath))
        if ($null -eq $entry -or $entry.Length -ne $rawSize -or $archive.Entries.Count -ne 1) {
            throw "Archive does not contain exactly the expected complete trace: $archivePath"
        }
        $entryStream = $entry.Open()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $archivedHash = [System.BitConverter]::ToString($sha.ComputeHash($entryStream)).Replace('-','') }
        finally { $sha.Dispose(); $entryStream.Dispose() }
        if ($archivedHash -cne $rawHash) { throw "Archived trace SHA256 differs: $archivePath" }
    } finally { $archive.Dispose() }
    # Exact checked path only. Delete the raw artifact only after full decompression/hash verification.
    if (-not $KeepRawTrace) { Remove-Item -LiteralPath $rawPath }
    return [pscustomobject]@{ original_trace_path = $rawPath; archive_path = $archivePath;
        original_bytes = $rawSize; archive_bytes = (Get-Item -LiteralPath $archivePath).Length;
        original_sha256 = $rawHash; verified = $true; raw_retained = $KeepRawTrace.IsPresent }
}

if ($ArchiveOnly) {
    # This mode reads/writes trace artifacts and their map only. It neither starts
    # Godot nor rewrites original reports, summary, environment or step results.
    $mapPath = Join-Path $evidence 'trace_archives.json'
    if (Test-Path -LiteralPath $mapPath) {
        foreach ($priorMap in @(Get-Content -LiteralPath $mapPath -Raw -Encoding UTF8 | ConvertFrom-Json)) {
            if ($null -ne $priorMap) { $archiveMap.Add($priorMap) }
        }
    }
    foreach ($rawTrace in @(Get-ChildItem -LiteralPath $evidence -File -Filter '*_trace.json')) {
        $reportName = $rawTrace.Name -replace '_trace\.json$', '.json'
        $mapping = Compress-ProbeTrace (Join-Path $evidence $reportName)
        $alreadyMapped = @($archiveMap | Where-Object archive_path -eq $mapping.archive_path).Count -gt 0
        if (-not $alreadyMapped) { $archiveMap.Add($mapping) }
        ConvertTo-Json -InputObject @($archiveMap.ToArray()) -Depth 6 |
            Set-Content -LiteralPath $mapPath -Encoding UTF8
        Write-Output ("Verified trace archive: {0}" -f $mapping.archive_path)
    }
    exit 0
}

$Godot = Resolve-Godot $Godot
Push-Location $root
try {
    [ordered]@{ commit = (git rev-parse HEAD); changes = @(git status --porcelain); date = (Get-Date -Format o);
        runtime = $Godot; repetitions = $Repetitions; scenarios = $Scenarios; layouts = $Layouts; mode = $mode;
        restore_sleeping_and_velocities_in_B = $RestoreState.IsPresent; contacts_enabled = $Contacts.IsPresent; pause_frames = $PauseFrames;
        trace_enabled = $Trace.IsPresent; compress_traces = $Trace.IsPresent; keep_raw_traces = $KeepRawTrace.IsPresent;
        prospective_natural_rest = $NaturalRest.IsPresent;
        natural_rest_protocol = if ($NaturalRest) { '60 consecutive natural solver-sleep ticks within30s; 2s control with per-tick peak/wakes; no layout retry; setup instability FAIL; intervention measured immediately+90ticks' } else { 'legacy unchanged' };
        independent_process_per_intervention = $true;
        source_hashes = @(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $root 'scripts/main.gd'),
            (Join-Path $root 'scripts/structures/structure_service.gd'), (Join-Path $root 'scripts/world/terrain_service.gd'),
            (Join-Path $root 'scripts/world/terrain_save_files.gd'), (Join-Path $root 'scripts/dev/t26_physics_probe.gd'),
            (Join-Path $root 'tools/run_t26_probe.ps1') |
            Select-Object Path,Hash) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'environment.json') -Encoding UTF8
    if (-not $SkipImport) {
        $import = Invoke-Import $Godot $evidence $root $StepTimeoutSec
        if ($import.Code -ne 0) { throw "Import failed: $($import.Code)" }
    }
    # Sequential processes: concurrent Godot instances would alter the experiment's load.
    # Loop order interleaves A/B/C to avoid attributing machine drift to one intervention.
    for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
        foreach ($layout in $Layouts) {
            foreach ($scenario in $Scenarios) {
                $restore = $RestoreState.IsPresent -and $scenario -eq 'B'
                $name = '{0}_{1}_{2}_{3:D3}' -f $mode,$layout,$scenario,$iteration
                $reportPath = Join-Path $evidence "$name.json"
                $arguments = @('--path','.', 'res://scenes/main.tscn','--','--t26-probe',
                    "--probe-scenario=$scenario", "--probe-layout=$layout", "--probe-repeat=$iteration",
                    "--probe-pause-frames=$PauseFrames", "--probe-restore-state=$($restore.ToString().ToLowerInvariant())",
                    "--probe-contacts=$($Contacts.IsPresent.ToString().ToLowerInvariant())",
                    "--probe-trace=$($Trace.IsPresent.ToString().ToLowerInvariant())")
                if (-not $Window) { $arguments = @('--headless') + $arguments }
                if ($NaturalRest) { $arguments += '--probe-natural-rest' }
                Invoke-SelftestStep $name "$name.log" $Godot $arguments $reportPath $expectedIds
                $row = [ordered]@{ name = $name; repetition = $iteration; layout = $layout; scenario = $scenario;
                    restore_state = $restore; contacts_enabled = $Contacts.IsPresent; natural_rest = $NaturalRest.IsPresent;
                    exit_code = $results[$name]; report = $reportPath }
                if (Test-Path -LiteralPath $reportPath) {
                    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    $probe = @($report.resultados | Where-Object id -eq 'PROBE')
                    if ($probe.Count -eq 1) {
                        $row.status = $probe[0].status
                        $row.details = $probe[0].detalhes
                        if ($Trace -and $probe[0].detalhes.trace_written) {
                            try {
                                $row.trace_archive = Compress-ProbeTrace $reportPath
                                $archiveMap.Add($row.trace_archive)
                            } catch {
                                $row.trace_archive_error = $_.Exception.Message
                                if ($results[$name] -eq 0) { $results[$name] = $script:InvalidReportExitCode }
                                $row.exit_code = $results[$name]
                                Add-Content -LiteralPath (Join-Path $evidence "$name.log") -Encoding UTF8 -Value "TRACE ARCHIVE ERROR: $($_.Exception.Message)"
                            }
                        }
                    }
                }
                $summary.Add([pscustomobject]$row)
                # Preserve progress even when later runs fail or the operator interrupts.
                $summary.ToArray() | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
                $results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'steps.json') -Encoding UTF8
                ConvertTo-Json -InputObject @($archiveMap.ToArray()) -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'trace_archives.json') -Encoding UTF8
            }
        }
    }
    $groups = @($summary | Group-Object layout,scenario,restore_state | ForEach-Object {
        $shifts = @($_.Group | ForEach-Object { if ($_.details) { $_.details.after_1_5s.max_m } })
        $peaks = @($_.Group | ForEach-Object { if ($_.details) { $_.details.peak_after_1_5s.max_m } })
        [pscustomobject]@{ group = $_.Name; runs = $_.Count; pass = @($_.Group | Where-Object exit_code -eq 0).Count;
            setup_unstable = @($_.Group | Where-Object { $_.details.setup_status -eq 'SETUP_UNSTABLE' }).Count;
            interventions_executed = @($_.Group | Where-Object { $_.details.intervention_executed -eq $true }).Count;
            max_shift_m = ($shifts | Measure-Object -Maximum).Maximum;
            max_peak_shift_m = ($peaks | Measure-Object -Maximum).Maximum;
            mean_shift_m = ($shifts | Measure-Object -Average).Average }
    })
    $groups | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidence 'aggregate.json') -Encoding UTF8
    $groups | Format-Table -AutoSize | Out-Host
    if (@($results.Values | Where-Object { $_ -ne 0 }).Count) { exit 1 }
} finally { Pop-Location }
