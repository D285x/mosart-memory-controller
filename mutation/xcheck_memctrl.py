#!/usr/bin/env python3
"""Cross-check of the equivalence backend: runs flow.py's SymbiYosys port miter on the memory controller
mutants that survived simulation v1 and compares with the yosys sat verdicts in results/mutation_state.json.
Writes results/equiv_backend_crosscheck.json as [id, mutate.py verdict, flow.py verdict, seconds]."""
import json, os, sys
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import flow
ROOT = os.path.abspath(os.path.join(HERE, '..'))

if __name__ == '__main__':
    flow.setup('memctrl_xcheck')
    orig = {m['id']: m for m in json.load(open(os.path.join(ROOT, 'results', 'mutation_state.json')))}
    muts = flow.build_list()
    assert [m['id'] for m in muts] == list(orig), 'mutant list differs from mutate.py'
    todo = [m for m in muts if orig[m['id']]['sim'] == 'SURVIVED']
    with Pool(flow.JOBS) as p:
        res = p.map(flow.equiv_one, todo)
    rows = [(mid, orig[mid].get('equiv'), r.get('equiv'), r.get('equiv_time')) for mid, r in res]
    for r in rows:
        print(r)
    json.dump(rows, open(os.path.join(ROOT, 'results', 'equiv_backend_crosscheck.json'), 'w'), indent=1)
