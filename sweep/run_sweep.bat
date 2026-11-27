@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem ===========================================================================
rem  Parameter, Fmax, area and power sweep of the memory controller (Vivado)
rem  Usage:  sweep\run_sweep.bat          full sweep (about 1.5 to 2.5 hours with 5 placer directives)
rem          sweep\run_sweep.bat full cfgonly   configuration sweep only (keeps clock rows)
rem          sweep\run_sweep.bat quick    reduced sweep (about 20 to 30 minutes)
rem  Results: results\sweep\sweep_data.csv and results\sweep\sweep_tables.md
rem ===========================================================================
set "ROOT=%~dp0..\"
pushd "%ROOT%" & set "ROOT=%CD%\" & popd

where vivado >nul 2>nul
if errorlevel 1 (
  for %%R in ("C:\Xilinx" "D:\Xilinx" "C:\AMD" "D:\AMD") do (
    if exist "%%~R" for /d %%D in ("%%~R\*") do (
      if exist "%%D\Vivado\bin\vivado.bat" set "VBIN=%%D\Vivado\bin"
      if exist "%%D\bin\vivado.bat" set "VBIN=%%D\bin"
    )
  )
)
if defined VBIN set "PATH=%VBIN%;%PATH%"
where vivado >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Vivado not found. Open the Vivado Tcl Shell, or add its bin folder to PATH.
  pause & exit /b 1
)

set "MODE=%~1"
if /i "%MODE%"=="quick" (
  set "CFGS=8:4 16:4 32:6"
  set "PERIODS=8 5 4 3.5"
  set "DIRS=Default Explore"
) else (
  set "CFGS=8:3 8:4 8:5 8:6 16:3 16:4 16:5 16:6 32:3 32:4 32:5 32:6"
  set "PERIODS=10 8 6 5 4 3.5 3 2.5"
  set "DIRS=Default Explore ExtraTimingOpt ExtraNetDelay_high SpreadLogic_high"
)

if /i not "%~2"=="cfgonly" if exist "%ROOT%results\sweep\sweep_data.csv" del "%ROOT%results\sweep\sweep_data.csv"
if not exist "%ROOT%results\sweep" mkdir "%ROOT%results\sweep"
if not exist "%ROOT%results\sweep\logs" mkdir "%ROOT%results\sweep\logs"
cd /d "%ROOT%results\sweep\logs"

echo.
echo [1/2] Configuration sweep at a 4.0 ns clock target (post-route)
for %%C in (%CFGS%) do (
  for /f "tokens=1,2 delims=:" %%A in ("%%C") do (
    echo        DATA_W=%%A ADDR_W=%%B
    call vivado -mode batch -source "%ROOT%sweep\point.tcl" -log "cfg_%%A_%%B.log" -journal "cfg_%%A_%%B.jou" -tclargs cfg %%A %%B 4.0 impl Default > nul 2>&1
  )
)

if /i "%~2"=="cfgonly" goto :tables
echo.
echo [2/2] Clock sweep for DATA_W=8, ADDR_W=4 (post-route, one run per placer directive)
for %%P in (%PERIODS%) do (
  for %%X in (%DIRS%) do (
    echo        period %%P ns, directive %%X
    call vivado -mode batch -source "%ROOT%sweep\point.tcl" -log "clk_%%P_%%X.log" -journal "clk_%%P_%%X.jou" -tclargs clk 8 4 %%P impl %%X > nul 2>&1
  )
)


:tables
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%sweep\make_tables.ps1"
echo.
echo Data  : results\sweep\sweep_data.csv
echo Tables: results\sweep\sweep_tables.md
pause
endlocal
