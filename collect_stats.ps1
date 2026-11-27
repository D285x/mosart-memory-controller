$root = "C:\MemCtrl"
$out  = Join-Path $root "results\all_stats.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
$script:L = New-Object System.Collections.Generic.List[string]
function W($s) { $script:L.Add([string]$s) }

function Row($file, $pattern) {
    $m = Select-String -Path $file -Pattern $pattern | Select-Object -First 1
    if ($m) {
        $c = $m.Line.Split('|') | ForEach-Object { $_.Trim() }
        return ("{0}: used {1}, available {2}, {3}%" -f $c[1], $c[2], $c[5], $c[6])
    }
    return "$pattern : not found"
}

function PowerRow($file, $label) {
    $m = Select-String -Path $file -SimpleMatch $label | Select-Object -First 1
    if ($m) {
        $c = $m.Line.Split('|') | ForEach-Object { $_.Trim() }
        return ("{0}: {1}" -f $c[1], $c[2])
    }
    return "$label : not found"
}

function First($file, $pattern) {
    $m = Select-String -Path $file -Pattern $pattern | Select-Object -First 1
    if ($m) { return $m.Line.Trim() }
    return "$pattern : not found"
}

$fmaxEst = [ordered]@{}
foreach ($d in @("selftest", "latency")) {
    $dir = Join-Path $root "build\$d"
    W ""
    W "=================== $d ==================="

    W ""
    W "--- Utilization (xc7a35t) ---"
    $u = Join-Path $dir "utilization.rpt"
    W (Row $u '^\|\s*Slice LUTs\*?\s*\|')
    W (Row $u '^\|\s*Slice Registers\s*\|')
    W (Row $u '^\|\s*Slice\s*\|')
    W (Row $u '^\|\s*Block RAM Tile\s*\|')
    W (Row $u '^\|\s*DSPs\s*\|')

    W ""
    W "--- Timing (50 MHz target, 20 ns period) ---"
    $tf = Join-Path $dir "timing_summary.rpt"
    $t = Get-Content $tf
    $hit = $t | Select-String 'WNS\(ns\)' | Select-Object -First 1
    if ($hit) {
        $v = ($t[$hit.LineNumber + 1].Trim() -split '\s+')
        if ($v.Count -ge 12) {
            W ("Setup  WNS {0} ns, TNS {1} ns, failing {2} of {3} endpoints" -f $v[0], $v[1], $v[2], $v[3])
            W ("Hold   WHS {0} ns, THS {1} ns, failing {2} of {3} endpoints" -f $v[4], $v[5], $v[6], $v[7])
            W ("Pulse  WPWS {0} ns, TPWS {1} ns, failing {2} of {3} endpoints" -f $v[8], $v[9], $v[10], $v[11])
            $fmax = [math]::Round(1000 / (20.0 - [double]$v[0]), 1)
            W ("Estimated Fmax from slack: {0} MHz (estimate only)" -f $fmax)
            $fmaxEst[$d] = $fmax
        } else {
            W ("Could not parse timing row: " + $t[$hit.LineNumber + 1])
        }
    } else {
        W "WNS header not found"
    }
    if (Select-String -Path $tf -Pattern 'All user specified timing constraints are met' -Quiet) {
        W "Constraints: all met"
    } else {
        W "Constraints: NOT confirmed met, check timing_summary.rpt"
    }

    W ""
    W "--- Power (Vivado estimate) ---"
    $p = Join-Path $dir "power.rpt"
    W (PowerRow $p "Total On-Chip Power (W)")
    W (PowerRow $p "Dynamic (W)")
    W (PowerRow $p "Device Static (W)")
    W (PowerRow $p "Junction Temperature (C)")
    W (PowerRow $p "Confidence Level")

    W ""
    W "--- Critical path (worst setup path) ---"
    $cp = Join-Path $dir "critical_paths.rpt"
    W (First $cp 'Slack\s*\(')
    W (First $cp 'Source:')
    W (First $cp 'Destination:')
    W (First $cp 'Data Path Delay:')
    W (First $cp 'Logic Levels:')

    W ""
    W "--- Design rule check (drc.rpt, first 40 lines) ---"
    Get-Content (Join-Path $dir "drc.rpt") | Select-Object -First 40 | ForEach-Object { W $_ }

    W ""
    W "--- Utilization by hierarchy ---"
    $h = Get-Content (Join-Path $dir "utilization_hier.rpt")
    $idx = 0
    $m = $h | Select-String 'Utilization by Hierarchy' | Select-Object -First 1
    if ($m) { $idx = $m.LineNumber - 1 }
    $h | Select-Object -Skip $idx -First 40 | ForEach-Object { W $_ }
}

foreach ($f in @("build\run_summary.txt", "results\sweep\sweep_tables.md", "results\sweep\sweep_data.csv", "results\verification_summary.md")) {
    $p = Join-Path $root $f
    W ""
    W "=================== $f ==================="
    if (Test-Path $p) { Get-Content $p | ForEach-Object { W $_ } } else { W "file not found" }
}


W ""
W "=================== Fmax summary ==================="
foreach ($k in $fmaxEst.Keys) {
    W ("{0}: {1} MHz (estimate from slack at the 50 MHz target)" -f $k, $fmaxEst[$k])
}
$sw = Join-Path $root "results\sweep\sweep_data.csv"
if (Test-Path $sw) {
    $rows = @(Import-Csv $sw | Where-Object { $_.tag -eq 'clk' })
    if ($rows.Count -gt 0) {
        $cols = @($rows[0].PSObject.Properties.Name)
        W ("sweep_data.csv columns: " + ($cols -join ", "))
        $tc = $cols | Where-Object { $_ -match 'target|freq|mhz|period|clk' } | Select-Object -First 1
        $sc = $cols | Where-Object { $_ -match 'wns|slack' } | Select-Object -First 1
        if ($tc -and $sc) {
            W "Using target column '$tc' and slack column '$sc'"
            $inMHz = ($tc -match 'mhz|freq')
            $res = @()
            foreach ($r in $rows) {
                $tv = 0.0; $sv = 0.0
                if ([double]::TryParse([string]$r.$tc, [ref]$tv) -and [double]::TryParse([string]$r.$sc, [ref]$sv) -and $tv -gt 0) {
                    if ($inMHz) { $per = 1000.0 / $tv; $tm = $tv } else { $per = $tv; $tm = 1000.0 / $tv }
                    if (($per - $sv) -gt 0) {
                        $res += [pscustomobject]@{ TargetMHz = [math]::Round($tm, 1); WNS = $sv; FmaxEst = [math]::Round(1000.0 / ($per - $sv), 1) }
                    }
                }
            }
            $met  = @($res | Where-Object { $_.WNS -ge 0 })
            $fail = @($res | Where-Object { $_.WNS -lt 0 })
            W ("Sweep runs parsed: {0} (met timing: {1}, failed: {2})" -f $res.Count, $met.Count, $fail.Count)
            if ($met.Count -gt 0) {
                W ("Highest target that met timing: {0} MHz" -f (($met | Measure-Object TargetMHz -Maximum).Maximum))
                W ("Best slack-based Fmax among passing runs: {0} MHz" -f (($met | Measure-Object FmaxEst -Maximum).Maximum))
            }
            if ($fail.Count -gt 0) {
                W ("Lowest target that failed timing: {0} MHz" -f (($fail | Measure-Object TargetMHz -Minimum).Minimum))
            }
            W "Note: clock-sweep rows only (tag = clk). The configuration sweep runs at a fixed 4.0 ns target, so its slack-based Fmax values are estimates, not tested limits."
        } else {
            W "Could not identify target and slack columns, send the column list above."
        }
    }
} else {
    W "sweep_data.csv not found"
}

$script:L | Set-Content -Path $out -Encoding UTF8
Write-Host "Wrote $out"
