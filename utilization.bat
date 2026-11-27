@echo off
cd /d C:\MemCtrl
if "%~1"=="" (
    echo Usage: utilization.bat path\to\design1.dcp path\to\design2.dcp
    echo Checkpoints found under build:
    dir /s /b build\*.dcp
    exit /b 1
)
if not exist results\utilization mkdir results\utilization
vivado -mode batch -nojournal -log results\utilization\utilization.log -source utilization.tcl -tclargs %*
echo Done. See results\utilization\utilization_summary.csv
