# Turns results\sweep\sweep_data.csv into markdown tables (results\sweep\sweep_tables.md).
$root = Split-Path -Parent $PSScriptRoot
$csv  = Join-Path $root 'results\sweep\sweep_data.csv'
$out  = Join-Path $root 'results\sweep\sweep_tables.md'
if (-not (Test-Path $csv)) { Write-Host 'sweep_data.csv not found'; exit 1 }
$rows = Import-Csv $csv
foreach ($r in $rows) { if (-not $r.directive) { $r | Add-Member -NotePropertyName directive -NotePropertyValue 'Default' -Force } }
$md = @()
$md += '# Sweep results (xc7a35tftg256-1, Vivado out-of-context, internal register-to-register timing)'
$md += ''
$md += '## Configuration sweep, 4.0 ns clock target, post-route'
$md += ''
$md += '| DATA_W | ADDR_W | Words | Memory bits | LUTs | of which LUT as memory | FFs | BRAM | WNS (ns) | Estimated Fmax (MHz) | Power total (W) |'
$md += '|---|---|---|---|---|---|---|---|---|---|---|'
foreach ($r in ($rows | Where-Object { $_.tag -eq 'cfg' -and $_.directive -eq 'Default' } | Sort-Object { [int]$_.data_w }, { [int]$_.addr_w })) {
    $md += "| $($r.data_w) | $($r.addr_w) | $($r.words) | $($r.mem_bits) | $($r.luts) | $($r.lut_mem) | $($r.ffs) | $($r.bram) | $($r.wns_ns) | $($r.fmax_est_mhz) | $($r.power_total_w) |"
}
$md += ''
$md += '## Clock sweep, DATA_W = 8, ADDR_W = 4, post-route, spread over placer directives'
$md += ''
$md += '| Target period (ns) | Target (MHz) | Runs | WNS mean (ns) | WNS min (ns) | WNS max (ns) | Runs meeting timing | Est. Fmax mean (MHz) | Est. Fmax spread (MHz) | LUTs | FFs | Power mean (W) |'
$md += '|---|---|---|---|---|---|---|---|---|---|---|---|'
$best = 0
$groups = $rows | Where-Object { $_.tag -eq 'clk' } | Group-Object period_ns | Sort-Object { [double]$_.Name } -Descending
foreach ($g in $groups) {
    $p = [double]$g.Name
    $w = @($g.Group | Where-Object { $_.wns_ns -ne 'NA' } | ForEach-Object { [double]$_.wns_ns })
    $f = @($g.Group | Where-Object { $_.fmax_est_mhz -ne 'NA' } | ForEach-Object { [double]$_.fmax_est_mhz })
    $pw = @($g.Group | Where-Object { $_.power_total_w -ne 'NA' } | ForEach-Object { [double]$_.power_total_w })
    if ($w.Count -gt 0) {
        $met = @($w | Where-Object { $_ -ge 0 }).Count
        $wm = ($w | Measure-Object -Average -Minimum -Maximum)
        $fm = ($f | Measure-Object -Average -Minimum -Maximum)
        if ($met -eq $w.Count -and (1000.0 / $p) -gt $best) { $best = 1000.0 / $p }
        $md += ("| {0} | {1:N0} | {2} | {3:N3} | {4:N3} | {5:N3} | {6} of {2} | {7:N1} | {8:N1} to {9:N1} | {10} | {11} | {12:N3} |" -f $g.Name, (1000.0 / $p), $w.Count, $wm.Average, $wm.Minimum, $wm.Maximum, $met, $fm.Average, $fm.Minimum, $fm.Maximum, $g.Group[0].luts, $g.Group[0].ffs, ($pw | Measure-Object -Average).Average)
    }
}
$md += ''
if ($best -gt 0) { $md += ("Highest clock target met in every directive run: {0:N0} MHz." -f $best) }
$md += ''
$md += 'Notes: the spread comes from the placer directive (Default, Explore, ExtraTimingOpt, ExtraNetDelay_high, SpreadLogic_high), not from random seeds. Timing is register to register inside the controller (the design is synthesised out of context and I/O paths are excluded). Estimated Fmax = 1000 / (period - WNS). Power figures are vectorless Vivado estimates for the out-of-context design.'
$md | Set-Content $out -Encoding UTF8
$md | ForEach-Object { Write-Host $_ }
