@echo off
setlocal EnableExtensions
rem Reruns only the sweep points that are missing from results\sweep\sweep_data.csv
rem Points already in the CSV are skipped, so no duplicate rows are added.
set "ROOT=C:\MemCtrl\"
set "CSV=%ROOT%results\sweep\sweep_data.csv"

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

cd /d "%ROOT%results\sweep\logs"
if exist cfg_16_6.log copy /y cfg_16_6.log cfg_16_6_first_try.log >nul

call :cfg 16 6
call :clk 10 ExtraTimingOpt
call :clk 8 Default
call :clk 8 ExtraNetDelay_high
call :clk 5 Default
call :clk 5 SpreadLogic_high
call :clk 4 SpreadLogic_high
call :clk 3 SpreadLogic_high

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%sweep\make_tables.ps1"
echo.
echo Done. Check results\sweep\sweep_data.csv and results\sweep\logs
pause
exit /b 0

:cfg
findstr /r /c:"^cfg,impl,%1,%2," "%CSV%" >nul
if not errorlevel 1 (
  echo skip cfg %1 %2, already in the CSV
  goto :eof
)
echo running cfg DATA_W=%1 ADDR_W=%2
call vivado -mode batch -source "%ROOT%sweep\point.tcl" -log "cfg_%1_%2.log" -journal "cfg_%1_%2.jou" -tclargs cfg %1 %2 4.0 impl Default > nul 2>&1
goto :eof

:clk
findstr /r /c:"^clk,impl,8,4,16,128,%1,.*,%2$" "%CSV%" >nul
if not errorlevel 1 (
  echo skip clk %1 ns %2, already in the CSV
  goto :eof
)
echo running clk period %1 ns, directive %2
call vivado -mode batch -source "%ROOT%sweep\point.tcl" -log "clk_%1_%2.log" -journal "clk_%1_%2.jou" -tclargs clk 8 4 %1 impl %2 > nul 2>&1
goto :eof
