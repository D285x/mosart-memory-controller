@echo off
setlocal EnableExtensions
rem Wrapper overhead and vendor baseline (out-of-context, post-route, no board needed).
rem Runs: bare core, AXI4-Lite wrapper and Xilinx AXI BRAM Controller, each at 4.0 ns and 3.0 ns.
rem Output: results\compare\compare_data.csv, results\compare\reports\, results\compare\logs\
rem Takes about 25 to 35 minutes. Do not interrupt it.
set "ROOT=C:\MemCtrl\"

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

if not exist "%ROOT%results\compare\logs" mkdir "%ROOT%results\compare\logs"
if exist "%ROOT%results\compare\compare_data.csv" del "%ROOT%results\compare\compare_data.csv"
cd /d "%ROOT%results\compare\logs"

for %%P in (4.0 3.0) do (
  call :run core 8 4 %%P
  call :run axil 8 4 %%P
  call :run core 32 6 %%P
  call :run axil 32 6 %%P
  call :run bramctrl 32 0 %%P
)

echo.
echo Results:
type "%ROOT%results\compare\compare_data.csv"
echo.
echo Done. Data: results\compare\compare_data.csv
pause
exit /b 0

:run
echo running %1 DATA_W=%2 ADDR_W=%3 period %4 ns
call vivado -mode batch -source "%ROOT%sweep\compare.tcl" -log "%1_%2_%3_%4.log" -journal "%1_%2_%3_%4.jou" -tclargs %1 %2 %3 %4 > nul 2>&1
findstr /c:"COMPARE DONE" "%1_%2_%3_%4.log" >nul
if errorlevel 1 echo    [FAILED] see results\compare\logs\%1_%2_%3_%4.log
goto :eof
