@echo off
setlocal EnableExtensions
rem ===========================================================================
rem  Programmable memory controller: simulate, build, report, program
rem
rem    run_all.bat                 simulations, both bitstreams, statistics
rem    run_all.bat sim             simulations only (about 2 to 4 minutes)
rem    run_all.bat build           both bitstreams and statistics, no simulation
rem    run_all.bat program self    program the self-test design
rem    run_all.bat program lat     program the latency measurement design
rem    sweep\run_sweep.bat [quick] parameter, Fmax, area and power sweep
rem
rem  Outputs go to the build folder. Run from any folder.
rem ===========================================================================
set "ROOT=%~dp0"
cd /d "%ROOT%"

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

if /i "%~1"=="program" goto :program

if not exist "%ROOT%build\sim" mkdir "%ROOT%build\sim"
if /i "%~1"=="build" goto :build

rem ---------------------------------------------------------------- simulation
echo.
echo [1/4] Simulation
cd /d "%ROOT%build\sim"
set "RTL="%ROOT%rtl\sync_mem.v" "%ROOT%rtl\cfg_regs.v" "%ROOT%rtl\mem_ctrl_fsm.v" "%ROOT%rtl\mem_ctrl_top.v""

call :sim core      "%ROOT%tb\tb_mem_ctrl.v" tb_mem_ctrl
call :simp p8_4     8  4
call :simp p16_5    16 5
call :simp p32_6    32 6
call :simp p8_2     8  2
call :sim axil      "%ROOT%rtl\axil_mem_ctrl.v" "%ROOT%tb\tb_axil_mem_ctrl.v" tb_axil_mem_ctrl
call :sim selftest  "%ROOT%board\edge_selftest_top.v" "%ROOT%board\tb_edge_selftest.v" tb_edge_selftest
call :sim latency   "%ROOT%board\seg7_driver.v" "%ROOT%board\edge_latency_top.v" "%ROOT%board\tb_edge_latency.v" tb_edge_latency

if /i "%~1"=="sim" goto :end

:build
rem ---------------------------------------------------------------- bitstreams
echo.
echo [2/4] Self-test bitstream (a few minutes)
cd /d "%ROOT%"
call vivado -mode batch -source board\build.tcl -tclargs selftest -log build\selftest.log -journal build\selftest.jou > nul 2>&1
if not exist "build\selftest\selftest.bit" (echo [ERROR] self-test build failed, see build\selftest.log) else (echo        build\selftest\selftest.bit)

echo [3/4] Latency measurement bitstream (a few minutes)
call vivado -mode batch -source board\build.tcl -tclargs latency -log build\latency.log -journal build\latency.jou > nul 2>&1
if not exist "build\latency\latency.bit" (echo [ERROR] latency build failed, see build\latency.log) else (echo        build\latency\latency.bit)

echo [4/4] Statistics
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%board\make_stats.ps1"
echo.
echo Summary saved to build\run_summary.txt
echo To program the board:  run_all.bat program self   or   run_all.bat program lat
goto :end

:program
set "V="
if /i "%~2"=="self" set "V=selftest"
if /i "%~2"=="lat"  set "V=latency"
if not defined V (echo Usage: run_all.bat program self^|lat & goto :end)
if not exist "%ROOT%build\%V%\%V%.bit" (echo [ERROR] build\%V%\%V%.bit not found, run "run_all.bat build" first & goto :end)
echo Programming %V% (board connected and powered)...
cd /d "%ROOT%"
call vivado -mode batch -source board\program.tcl -tclargs %V% -log build\program_%V%.log -journal build\program_%V%.jou
echo Done. Self-test: D3 and D5 on, D4 off, D6 blinking (SW4 down).
echo Latency: D3 and D5 on, 7-segment shows N then the value; sw[2:0] picks N, sw[4:3] picks the quantity.
goto :end

rem ---------------------------------------------------------------- helpers
:sim
rem  :sim <name> <sources...> <top>  (last argument is the top module)
setlocal EnableDelayedExpansion
set "NAME=%~1"
shift
set "SRCS="
:simloop
if "%~2"=="" goto :simgo
set "SRCS=!SRCS! %1"
shift
goto :simloop
:simgo
set "TOP=%~1"
call xvlog %RTL% "%ROOT%tb\cov_monitor.v" !SRCS! > xvlog_%NAME%.log 2>&1
call xelab -debug typical -timescale 1ns/1ps %TOP% -s s_%NAME% > xelab_%NAME%.log 2>&1
call xsim s_%NAME% -runall > sim_%NAME%.log 2>&1
findstr /c:"ALL TESTS PASSED" sim_%NAME%.log >nul && (echo        %NAME%: PASS) || (echo        %NAME%: FAIL, see build\sim\sim_%NAME%.log)
endlocal
exit /b

:simp
rem  :simp <name> <DATA_W> <ADDR_W>   parameterised testbench with coverage
call xvlog %RTL% "%ROOT%tb\cov_monitor.v" "%ROOT%tb\tb_mem_ctrl_param.v" > xvlog_%1.log 2>&1
call xelab -debug typical -timescale 1ns/1ps tb_mem_ctrl_param -generic_top "DATA_W=%2" -generic_top "ADDR_W=%3" -s s_%1 > xelab_%1.log 2>&1
call xsim s_%1 -runall > sim_%1.log 2>&1
findstr /c:"ALL TESTS PASSED" sim_%1.log >nul && (echo        param DATA_W=%2 ADDR_W=%3: PASS) || (echo        param DATA_W=%2 ADDR_W=%3: FAIL, see build\sim\sim_%1.log)
exit /b

:end
echo.
pause
endlocal
