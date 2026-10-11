<#
.SYNOPSIS
    M35: runs the Freisassen profession-choice benchmark over seeds x strategies.

.DESCRIPTION
    Profession choice decides whether the food chain staffs itself or the roster freezes. Judging a
    change to it from a single turbo run has already misled once: during M34 the inspected seed
    turned out to be the WORST of five for the change under test, so the single-seed read suggested
    a regression that the 5-seed mean contradicted. This script exists so candidates are compared on
    numbers instead.

    Each run appends a row to user://runs/bench.csv (see RunRecorder.append_bench_row). At the end
    the script reads that file back and prints a per-strategy summary.

    Ranking, per the agreed fitness definition: rank on final POPULATION, with cumulative DEATHS as
    the penalty. prof_entropy and avg_hunger are printed alongside as DIAGNOSTICS - do not optimise
    for them directly. There is deliberately no single composite score.

.PARAMETER Seeds
    Seeds to run. Each is passed as --turbo-seed. Runs are bit-reproducible per seed.

.PARAMETER Strategies
    Strategy names, passed as --turbo-strategy. Must match a name EconomyManager._make_strategy
    knows; an unknown one makes the run exit 2 rather than silently falling back.

.PARAMETER Days
    Simulated days per run (--turbo).

.PARAMETER Fresh
    Delete bench.csv before starting. Default is to append, so several sweeps accumulate.

.EXAMPLE
    .\tools\bench.ps1
    .\tools\bench.ps1 -Days 150 -Seeds 1,2,3 -Strategies urgency,mycandidate
#>
[CmdletBinding()]
param(
    [int[]]$Seeds = @(42, 7, 123, 999, 2024),
    [string[]]$Strategies = @('urgency'),
    [int]$Days = 300,
    [string]$Godot = "$env:USERPROFILE\.godot_tools\Godot_v4.6.3-stable_win64_console.exe",
    [string]$Project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [switch]$Fresh,
    [switch]$Force,
    # Skip the runs and just re-print the summary for rows already in bench.csv. A full sweep takes
    # the better part of an hour, so re-reading its result must not mean re-running it.
    [switch]$SummaryOnly
)

$ErrorActionPreference = 'Stop'

$UserData = Join-Path $env:APPDATA 'Godot\app_userdata\Freisassen'
$RunsDir  = Join-Path $UserData 'runs'
$BenchCsv = Join-Path $RunsDir 'bench.csv'
$SavePath = Join-Path $UserData 'savegame.json'

if (-not (Test-Path $Godot))   { throw "Godot executable not found: $Godot  (pass -Godot <path>)" }
if (-not (Test-Path $Project)) { throw "Project folder not found: $Project" }

# The GUI build has no console attached, so when it is launched from PowerShell it produces no
# stdout AND the run does not actually execute (verified: no RESULT line and no bench.csv row).
# Only the _console variant works here. Auto-correct rather than fail, since the GUI path is the
# obvious thing to pass by hand.
if ($Godot -notmatch '_console\.exe$') {
    $console = $Godot -replace '\.exe$', '_console.exe'
    if (Test-Path $console) {
        Write-Host "Using the console build: $console" -ForegroundColor DarkGray
        $Godot = $console
    } else {
        Write-Warning "$Godot is not the _console build; runs may produce no output. Expected $console"
    }
}

# --- Savegame protection -------------------------------------------------------------------------
# Layer 1 lives in the engine: SaveLoadManager skips its auto-save timer when --turbo= is present,
# so a turbo run no longer writes a save at all (M35).
# Layer 2 is here: a LIVE instance of the game rewrites savegame.json every AUTO_SAVE_INTERVAL from
# its own in-memory state. Restoring a backup over that would silently roll the player's session
# back, so refuse to run instead of "protecting" the file into an older state.
$live = @(Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'freepeople' -and $_.CommandLine -notmatch '--headless' })
if ($live.Count -gt 0 -and -not $SummaryOnly) {
    $pids = ($live | ForEach-Object { $_.ProcessId }) -join ', '
    $msg = "A non-headless Godot instance of this project is running (PID $pids). It rewrites " +
           "savegame.json on a timer, and it competes for CPU with the benchmark."
    if (-not $Force) {
        throw "$msg`nClose it, or re-run with -Force to benchmark anyway."
    }
    Write-Warning $msg
}

# Layer 3: a timestamped copy, restored in the finally block so an interrupted sweep (Ctrl-C) still
# leaves the save as it found it.
# NOT taken while a live instance is running: that process owns savegame.json and keeps rewriting it
# from its own in-memory state, so restoring our copy afterwards would roll the player's session
# back to whatever it looked like when the sweep started. Leaving the file alone is strictly safer
# than "protecting" it into an older state.
$backup = $null
if ((Test-Path $SavePath) -and ($live.Count -eq 0) -and (-not $SummaryOnly)) {
    $backup = Join-Path $env:TEMP ("freepeople_savegame_{0}.bak" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Copy-Item $SavePath $backup -Force
    Write-Host "Backed up savegame.json -> $backup" -ForegroundColor DarkGray
} elseif ($live.Count -gt 0 -and -not $SummaryOnly) {
    Write-Host "Leaving savegame.json alone - the live instance owns it." -ForegroundColor DarkGray
}

if ($Fresh -and (Test-Path $BenchCsv)) {
    Remove-Item $BenchCsv -Force
    Write-Host "Removed existing bench.csv (-Fresh)" -ForegroundColor DarkGray
}

$total = $Seeds.Count * $Strategies.Count
$index = 0
$startedAt = Get-Date

if ($SummaryOnly) { $total = 0 }

try {
    if ($SummaryOnly) { Write-Host "-SummaryOnly: re-reading bench.csv, not running anything." -ForegroundColor DarkGray }
    foreach ($strategy in ($Strategies | Where-Object { -not $SummaryOnly })) {
        foreach ($seed in $Seeds) {
            $index++
            # Sequential on purpose: RunRecorder names its per-run files from a second-resolution
            # timestamp, so two runs starting in the same second would collide on the metrics file.
            Write-Host ("[{0}/{1}] strategy={2} seed={3} days={4} ... " -f $index, $total, $strategy, $seed, $Days) -NoNewline
            $runStart = Get-Date
            # 2>&1 so Godot's shutdown noise ("ObjectDB instances leaked at exit", "N resources
            # still in use") is captured instead of scrolling past the progress line. It is normal
            # for a --quit and says nothing about the run.
            $output = & $Godot --headless --path $Project -- `
                --turbo=$Days --turbo-step=1.0 --turbo-seed=$seed --turbo-strategy=$strategy 2>&1
            $code = $LASTEXITCODE
            $elapsed = (Get-Date) - $runStart

            $result = ($output | Select-String -Pattern 'RESULT=' | Select-Object -First 1)
            if ($code -eq 2) {
                throw "Invalid invocation (exit 2). Is '$strategy' a strategy EconomyManager knows?`n$output"
            }
            if ($result) {
                Write-Host ("{0}  ({1:n0}s)" -f $result.ToString().Trim(), $elapsed.TotalSeconds)
            } else {
                Write-Host ("no RESULT line, exit {0}  ({1:n0}s)" -f $code, $elapsed.TotalSeconds) -ForegroundColor Yellow
            }
        }
    }
}
finally {
    if ($backup -and (Test-Path $backup)) {
        Copy-Item $backup $SavePath -Force
        Write-Host "Restored savegame.json from $backup" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host ("Sweep finished in {0:n1} min" -f ((Get-Date) - $startedAt).TotalMinutes) -ForegroundColor DarkGray

# --- Summary -------------------------------------------------------------------------------------
if (-not (Test-Path $BenchCsv)) {
    Write-Warning "No bench.csv at $BenchCsv - nothing to summarise."
    return
}

$rows = Import-Csv $BenchCsv | Where-Object { $Strategies -contains $_.strategy -and [int]$_.days -eq $Days }
if ($rows.Count -eq 0) {
    Write-Warning "bench.csv has no rows matching this sweep."
    return
}

function Get-Stats {
    param([double[]]$Values)
    $n = $Values.Count
    if ($n -eq 0) { return @{ Mean = 0.0; Sd = 0.0 } }
    $mean = ($Values | Measure-Object -Average).Average
    if ($n -lt 2) { return @{ Mean = $mean; Sd = 0.0 } }
    # Sample standard deviation (n-1): we are estimating spread from a handful of seeds.
    $ss = 0.0
    foreach ($v in $Values) { $ss += [Math]::Pow($v - $mean, 2) }
    return @{ Mean = $mean; Sd = [Math]::Sqrt($ss / ($n - 1)) }
}

Write-Host ""
Write-Host "Per-run rows ($Days days):" -ForegroundColor Cyan
$rows | Sort-Object strategy, { [int]$_.seed } |
    Format-Table @{L='strategy';E={$_.strategy}},
                 @{L='seed';E={$_.seed};A='right'},
                 @{L='surv';E={$_.survived};A='right'},
                 @{L='pop';E={$_.population};A='right'},
                 @{L='deaths';E={$_.deaths};A='right'},
                 @{L='hunger';E={$_.avg_hunger};A='right'},
                 @{L='inh_gold';E={$_.inhabitants_gold};A='right'},
                 @{L='crown_gold';E={$_.crown_gold};A='right'},
                 @{L='entropy';E={$_.prof_entropy};A='right'} -AutoSize |
    Out-String -Width 200 | Write-Host

Write-Host "Per-strategy summary - rank on population, deaths is the penalty;" -ForegroundColor Cyan
Write-Host "entropy and hunger are diagnostics, not targets. sd = sample stddev over seeds." -ForegroundColor DarkGray

$summary = foreach ($group in ($rows | Group-Object strategy)) {
    $pop     = Get-Stats ($group.Group | ForEach-Object { [double]$_.population })
    $deaths  = Get-Stats ($group.Group | ForEach-Object { [double]$_.deaths })
    $entropy = Get-Stats ($group.Group | ForEach-Object { [double]$_.prof_entropy })
    $hunger  = Get-Stats ($group.Group | ForEach-Object { [double]$_.avg_hunger })
    [pscustomobject]@{
        strategy   = $group.Name
        runs       = $group.Count
        survived   = (($group.Group | Where-Object { $_.survived -eq '1' }).Count).ToString() + '/' + $group.Count
        pop_mean   = '{0:n2}' -f $pop.Mean
        pop_sd     = '{0:n2}' -f $pop.Sd
        death_mean = '{0:n2}' -f $deaths.Mean
        death_sd   = '{0:n2}' -f $deaths.Sd
        ent_mean   = '{0:n3}' -f $entropy.Mean
        ent_sd     = '{0:n3}' -f $entropy.Sd
        hunger     = '{0:n3}' -f $hunger.Mean
        _sortPop   = $pop.Mean
        _sortDeath = $deaths.Mean
    }
}

$summary | Sort-Object @{E='_sortPop';Descending=$true}, @{E='_sortDeath';Descending=$false} |
    Format-Table strategy, runs, survived, pop_mean, pop_sd, death_mean, death_sd, ent_mean, ent_sd, hunger -AutoSize |
    Out-String -Width 200 | Write-Host

Write-Host "bench.csv: $BenchCsv" -ForegroundColor DarkGray
