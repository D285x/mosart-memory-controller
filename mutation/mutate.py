#!/usr/bin/env python3
"""Mutation analysis driver: simulation, formal and equivalence stages.

  python3 mutation/mutate.py sim      # run every mutant against the simulation testbench
  python3 mutation/mutate.py formal   # run every valid mutant through SymbiYosys property checks
  python3 mutation/mutate.py latency  # exact-latency formal task on FSM mutants the property check did not kill
  python3 mutation/mutate.py equiv    # bounded equivalence check (Yosys SAT miter) of mutants that survived simulation
  python3 mutation/mutate.py resim    # re-run the simulation survivors against the strengthened testbench
  python3 mutation/mutate.py report   # write results/mutation_*.md and .csv (see mutation/report.py)

State is kept in mutation/work/state.json so each stage can be resumed.
Requires iverilog, vvp, yosys, sby and z3 on the PATH.
"""
import json, os, re, shutil, subprocess, sys, tempfile, time
from multiprocessing import Pool
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RTL = os.path.join(ROOT, 'rtl')
FORMAL = os.path.join(ROOT, 'formal')
WORK = os.path.join(ROOT, 'mutation', 'work')
STATE = os.path.join(WORK, 'state.json')
TB = [os.path.join(ROOT, 'tb', 'cov_monitor.v'), os.path.join(ROOT, 'tb', 'tb_mem_ctrl_param.v')]
JOBS = int(os.environ.get('JOBS', '2'))

def run(cmd, cwd, timeout):
    t = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t
    except subprocess.TimeoutExpired:
        return 124, 'TIMEOUT', time.time() - t

def build_list():
    muts = []
    for m in mutlib.DIRECTED:
        muts.append({'id': m[0], 'cls': 'DIR', 'file': m[1], 'line': 0, 'desc': m[4], 'kind': 'dir', 'spec': list(m)})
    for m in mutlib.auto_mutants(RTL):
        muts.append({'id': m[0], 'cls': m[5], 'file': m[1], 'line': m[2], 'desc': m[6], 'kind': 'auto', 'spec': list(m)})
    return muts

def materialise(mut, dst):
    for f in os.listdir(RTL):
        if f.endswith('.v'):
            shutil.copy(os.path.join(RTL, f), dst)
    ok = (mutlib.apply_directed if mut['kind'] == 'dir' else mutlib.apply_auto)(RTL, tuple(mut['spec']), dst)
    return ok

def sim_one(mut):
    tmp = tempfile.mkdtemp(prefix='mut_')
    try:
        if not materialise(mut, tmp):
            return mut['id'], {'sim': 'ERROR', 'sim_detail': 'pattern not found'}
        srcs = sorted(os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith('.v')) + TB
        rc, out, _ = run(['iverilog', '-g2012', '-o', os.path.join(tmp, 'sim')] + srcs, tmp, 120)
        if rc != 0:
            return mut['id'], {'sim': 'INVALID', 'sim_detail': 'does not compile'}
        rc, out, dt = run(['vvp', os.path.join(tmp, 'sim')], tmp, 40)
        m = re.search(r'SUMMARY: (\d+) checks, (\d+) errors', out)
        if rc == 124:
            return mut['id'], {'sim': 'KILLED', 'sim_detail': 'hang or timeout'}
        if 'ALL TESTS PASSED' in out:
            return mut['id'], {'sim': 'SURVIVED', 'sim_detail': 'testbench passes'}
        return mut['id'], {'sim': 'KILLED', 'sim_detail': (m.group(2) + ' errors') if m else 'failed'}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def load():
    return json.load(open(STATE))

def save(st):
    json.dump(st, open(STATE, 'w'), indent=1)

def stage_sim():
    os.makedirs(WORK, exist_ok=True)
    muts = build_list()
    with Pool(JOBS) as p:
        res = dict(p.map(sim_one, muts, chunksize=2))
    for m in muts:
        m.update(res[m['id']])
    save(muts)
    c = {}
    for m in muts: c[m['sim']] = c.get(m['sim'], 0) + 1
    print('simulation stage:', c)

# ---------------- formal ----------------
def sby_task(tmp, sby, task, files, timeout):
    for f in files:
        shutil.copy(f, tmp)
    sbyf = os.path.join(tmp, os.path.basename(sby))
    txt = open(sby).read().replace('../rtl/', '')
    open(sbyf, 'w').write(txt)
    rc, out, dt = run(['sby', '-f', sbyf, task], tmp, timeout)
    if rc == 124:
        return 'TIMEOUT', dt
    if 'DONE (PASS' in out:
        return 'PASS', dt
    if 'DONE (FAIL' in out:
        return 'FAIL', dt
    return 'ERROR', dt

def formal_one(mut):
    if mut['sim'] == 'INVALID':
        return mut['id'], {}
    tmp = tempfile.mkdtemp(prefix='fm_')
    try:
        if not materialise(mut, tmp):
            return mut['id'], {'formal': 'ERROR'}
        res = {}
        extra = [os.path.join(FORMAL, 'formal_fsm.sv'), os.path.join(FORMAL, 'formal_cfg.sv'), os.path.join(FORMAL, 'formal_top.sv')]
        fsm_dir = tempfile.mkdtemp(dir=tmp); cfg_dir = tempfile.mkdtemp(dir=tmp); top_dir = tempfile.mkdtemp(dir=tmp)
        v = lambda n: os.path.join(tmp, n)
        r1, t1 = sby_task(fsm_dir, os.path.join(FORMAL, 'fsm.sby'), 'bmc', [v('mem_ctrl_fsm.v'), extra[0]], 240)
        r2, t2 = sby_task(cfg_dir, os.path.join(FORMAL, 'cfg.sby'), 'bmc', [v('cfg_regs.v'), extra[1]], 240)
        res['f_fsm'], res['f_cfg'] = r1, r2
        res['f_time'] = round(t1 + t2, 1)
        killed = 'FAIL' in (r1, r2)
        if not killed:
            r3, t3 = sby_task(top_dir, os.path.join(FORMAL, 'top_small_shallow.sby'), 'bmc',
                              [v('cfg_regs.v'), v('mem_ctrl_fsm.v'), v('sync_mem.v'), v('mem_ctrl_top.v'), extra[2]], 300)
            res['f_top'] = r3
            res['f_time'] = round(res['f_time'] + t3, 1)
            killed = (r3 == 'FAIL')
        res['formal'] = 'KILLED' if killed else 'SURVIVED'
        return mut['id'], res
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def stage_formal():
    muts = load()
    todo = [m for m in muts if m['sim'] != 'INVALID' and 'formal' not in m]
    print('formal stage: %d mutants' % len(todo), flush=True)
    done = 0
    with Pool(JOBS) as p:
        for mid, res in p.imap_unordered(formal_one, todo):
            for m in muts:
                if m['id'] == mid: m.update(res)
            done += 1
            if done % 5 == 0:
                save(muts); print('  %d/%d' % (done, len(todo)), flush=True)
    save(muts)

# ---------------- equivalence ----------------
EQ_YS = """read_verilog -formal -sv {orig}
read_verilog -formal -sv {mut}
chparam -set DATA_W {dw} -set ADDR_W {aw} orig_mem_ctrl_top
chparam -set DATA_W {dw} -set ADDR_W {aw} mut_mem_ctrl_top
proc; flatten; memory_map; opt_clean
miter -equiv -flatten -make_outputs -ignore_gold_x orig_mem_ctrl_top mut_mem_ctrl_top miter
hierarchy -top miter
proc; opt_clean
sat -verify -seq {depth} -set-at 1 in_reset 1 -set-at 2 in_reset 0 -prove trigger 0 -prove-skip 1 -set-init-zero -timeout {tmo} miter
"""

def equiv_one(mut):
    tmp = tempfile.mkdtemp(prefix='eq_')
    try:
        mdir = os.path.join(tmp, 'm'); os.makedirs(mdir)
        if not materialise(mut, mdir):
            return mut['id'], {'equiv': 'ERROR'}
        names = r'\b(cfg_regs|mem_ctrl_fsm|mem_ctrl_top|sync_mem)\b'
        groups = {'orig': [], 'mut': []}
        for pre, src in (('orig', RTL), ('mut', mdir)):
            for f in mutlib.FILES:
                txt = mutlib.read(os.path.join(src, f))
                txt = re.sub(names, pre + r'_\1', txt)
                fn = '%s_%s' % (pre, f)
                open(os.path.join(tmp, fn), 'w').write(txt)
                groups[pre].append(fn)
        depth = int(os.environ.get('EQ_DEPTH', '24'))
        dw = int(os.environ.get('EQ_DW', '2')); aw = int(os.environ.get('EQ_AW', '3'))
        open(os.path.join(tmp, 'eq.ys'), 'w').write(EQ_YS.format(orig=' '.join(groups['orig']), mut=' '.join(groups['mut']),
                                                                   dw=dw, aw=aw, depth=depth, tmo=300))
        rc, out, dt = run(['yosys', '-l', 'eq.log', 'eq.ys'], tmp, 600)
        log = open(os.path.join(tmp, 'eq.log')).read() if os.path.exists(os.path.join(tmp, 'eq.log')) else out
        if mut['file'] == 'sync_mem.v' and re.search(r"mem\[i\] =|mem_rdata =", mut['spec'][2] if mut['kind'] == 'dir' else mut['spec'][3]):
            # power-up value of the memory array: yosys does not carry the initial block into the miter
            return mut['id'], {'equiv': 'INITIAL_STATE', 'equiv_time': round(dt, 1)}
        if 'no model found: SUCCESS' in log:
            return mut['id'], {'equiv': 'EQUIVALENT_%d' % depth, 'equiv_time': round(dt, 1)}
        if 'model found: FAIL' in log:
            return mut['id'], {'equiv': 'DISTINGUISHABLE', 'equiv_time': round(dt, 1)}
        if rc == 124 or 'timeout' in log.lower():
            return mut['id'], {'equiv': 'TIMEOUT'}
        return mut['id'], {'equiv': 'ERROR'}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def stage_equiv():
    muts = load()
    todo = [m for m in muts if m['sim'] == 'SURVIVED' and 'equiv' not in m]
    print('equivalence stage: %d survivors' % len(todo), flush=True)
    with Pool(JOBS) as p:
        for mid, res in p.imap_unordered(equiv_one, todo):
            for m in muts:
                if m['id'] == mid: m.update(res)
            print('  %s %s' % (mid, res), flush=True)
            save(muts)
    save(muts)

def lat_one(mut):
    tmp = tempfile.mkdtemp(prefix='fl_')
    try:
        if not materialise(mut, tmp):
            return mut['id'], {}
        d = tempfile.mkdtemp(dir=tmp)
        r, dt = sby_task(d, os.path.join(FORMAL, 'fsm.sby'), 'latency', [os.path.join(tmp, 'mem_ctrl_fsm.v'), os.path.join(FORMAL, 'formal_fsm.sv')], 240)
        res = {'f_lat': r}
        if r == 'FAIL':
            res['formal'] = 'KILLED'
        return mut['id'], res
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

def stage_latency():
    """Second formal pass: the exact-latency task on FSM mutants that the property bmc task did not kill."""
    muts = load()
    todo = [m for m in muts if m.get('formal') == 'SURVIVED' and m['file'] == 'mem_ctrl_fsm.v' and 'f_lat' not in m]
    with Pool(JOBS) as p:
        res = dict(p.map(lat_one, todo, chunksize=1))
    for m in muts:
        if m['id'] in res: m.update(res[m['id']])
    save(muts)
    print('latency pass: %d mutants, %d newly killed' % (len(todo), sum(1 for r in res.values() if r.get('formal') == 'KILLED')))

def stage_resim():
    """Re-run the mutants that survived the first testbench against the strengthened testbench (D1b, D13)."""
    muts = load()
    todo = [m for m in muts if m['sim'] == 'SURVIVED']
    with Pool(JOBS) as p:
        res = dict(p.map(sim_one, todo, chunksize=1))
    for m in muts:
        if m['id'] in res:
            m['sim2'] = res[m['id']]['sim']
            m['sim2_detail'] = res[m['id']]['sim_detail']
        else:
            m['sim2'] = m['sim']
    save(muts)
    c = {}
    for m in muts: c[m['sim2']] = c.get(m['sim2'], 0) + 1
    print('resimulation stage:', c)

if __name__ == '__main__':
    stage = sys.argv[1] if len(sys.argv) > 1 else 'sim'
    {'sim': stage_sim, 'formal': stage_formal, 'equiv': stage_equiv, 'resim': stage_resim, 'latency': stage_latency}[stage]()
