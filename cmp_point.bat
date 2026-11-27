@echo off
setlocal EnableExtensions
rem Runs the bare core at 32 x 64 and 3.0 ns with the sweep flow (compare.tcl fails on this point).
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

cd /d "%ROOT%results\sweep\logs"
echo running core DATA_W=32 ADDR_W=6 period 3.0 ns (sweep flow)
call vivado -mode batch -source "%ROOT%sweep\point.tcl" -log cmp_32_6_3.0.log -journal cmp_32_6_3.0.jou -tclargs cmp 32 6 3.0 impl Default > nul 2>&1
findstr /c:"POINT DONE" cmp_32_6_3.0.log
if errorlevel 1 echo    [FAILED] see results\sweep\logs\cmp_32_6_3.0.log
cd /d "%ROOT%"
pause
