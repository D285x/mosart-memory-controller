# Collects simulation, utilization, timing and power numbers into build\run_summary.txt
$root = Split-Path -Parent $PSScriptRoot
$b = Join-Path $root 'build'
function Pick($file, $pattern) {
    if (Test-Path $file) {
        $m = Select-String -Path $file -Pattern $pattern | Select-Object -First 1
        if ($m) { return $m.Line.Trim() }
    }
    return '(not found)'
}
$L = @()
$L += 'Programmable memory controller: run summary'
$L += ('Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
$L += ''
$L += '== Simulation (xsim) =='
foreach ($f in Get-ChildItem (Join-Path $b 'sim') -Filter 'sim_*.log' -ErrorAction SilentlyContinue) {
    $L += ($f.BaseName + ': ' + (Pick $f.FullName 'RESULT'))
    $s = Pick $f.FullName 'SUMMARY'
    if ($s -ne '(not found)') { $L += ('    ' + $s) }
    $c = Pick $f.FullName 'COVERAGE'
    if ($c -ne '(not found)') { $L += ('    ' + $c) }
}
foreach ($v in 'selftest', 'latency') {
    $d = Join-Path $b $v
    $L += ''
    $L += ("== Implementation: $v (post-route, 50 MHz target) ==")
    foreach ($p in '^\| Slice LUTs','^\| LUT as Logic','^\| LUT as Memory','^\| Slice Registers','^\| Block RAM Tile','^\| Bonded IOB') {
        $L += (Pick "$d\utilization.rpt" $p)
    }
    $tf = Join-Path $d 'timing_summary.rpt'
    if (Test-Path $tf) {
        $t = Get-Content $tf
        $i = ($t | Select-String -Pattern 'WNS\(ns\)' | Select-Object -First 1).LineNumber
        if ($i) {
            $vals = ($t[$i + 1]).Trim() -split '\s+'
            $wns = [double]$vals[0]
            $L += ("WNS = $wns ns, TNS = $($vals[1]) ns")
            if ($wns -lt 20) { $L += ('Estimated Fmax = {0:N1} MHz (1 / (20 - WNS); an estimate)' -f (1000.0 / (20.0 - $wns))) }
        }
    }
    $L += (Pick "$d\power.rpt" 'Total On-Chip Power')
    $L += (Pick "$d\power.rpt" '\| Dynamic \(W\)')
    $L += (Pick "$d\power.rpt" 'Device Static')
}
$L | Set-Content (Join-Path $b 'run_summary.txt')
$L | ForEach-Object { Write-Host $_ }
