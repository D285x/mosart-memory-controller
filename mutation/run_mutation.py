#!/usr/bin/env python3
"""Runs the complete mutation flow: simulation, formal, latency pass, equivalence, re-simulation and report.
The re-simulation stage is meaningful once the testbench has been strengthened after the first pass.
Expect about 40 minutes on two cores (the equivalence stage dominates).
"""
import subprocess, sys, os
here = os.path.dirname(os.path.abspath(__file__))
for stage in ('sim', 'formal', 'latency', 'equiv', 'resim'):
    subprocess.run([sys.executable, os.path.join(here, 'mutate.py'), stage], check=True)
subprocess.run([sys.executable, os.path.join(here, 'report.py')], check=True)
