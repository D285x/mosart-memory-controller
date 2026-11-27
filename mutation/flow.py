#!/usr/bin/env python3
"""Design-independent mutation flow, used for the extension designs in designs/<name>/.

  python3 mutation/flow.py <design> sim      # every mutant against the first testbench (v1)
  python3 mutation/flow.py <design> formal   # SymbiYosys property checks, then the deep task on survivors
  python3 mutation/flow.py <design> equiv    # bounded SAT miter for mutants that survived simulation v1
  python3 mutation/flow.py <design> specequiv  # miter on the specified behaviour only, for miter-distinguishable survivors
  python3 mutation/flow.py <design> resim    # v1 survivors against the strengthened testbench (v2)
  python3 mutation/flow.py <design> report   # results/<design>/mutation_results.md and .csv
  python3 mutation/flow.py <design> all      # all stages in order

The stages, pass/fail criteria and the operator rules are those of mutation/mutate.py
(memory controller); only the design-specific settings come from designs/<design>/design.py.
Requires iverilog, vvp, yosys, sby and yices on the PATH.
"""
import importlib.util, json, os, re, shutil, subprocess, sys, tempfile, time, collections
from multiprocessing import Pool
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import oplib

ROOT = os.path.abspath(os.path.join(HERE, '..'))
JOBS = int(os.environ.get('JOBS', '2'))
D = None   # design config module
DDIR = RTL = WORK = STATE = None


def setup(name):
    global D, DDIR, RTL, WORK, STATE
    DDIR = os.path.join(ROOT, 'designs', name)
    spec = importlib.util.spec_from_file_location('design', os.path.join(DDIR, 'design.py'))
    D = importlib.util.module_from_spec(spec); spec.loader.exec_module(D)
    RTL = os.path.abspath(getattr(D, 'RTL_DIR', os.path.join(DDIR, 'rtl')))
    WORK = os.path.join(DDIR, 'mutation_work')
    STATE = os.path.join(WORK, 'state.json')


def run(cmd, cwd, timeout):
    t = time.time()
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr, time.time() - t
    except subprocess.TimeoutExpired:
        return 124, 'TIMEOUT', time.time() - t


def build_list():
    muts = []
    for m in D.DIRECTED:
        muts.append({'id': m[0], 'cls': 'DIR', 'file': m[1], 'line': 0, 'desc': m[4], 'kind': 'dir', 'spec': list(m)})
    for m in oplib.auto_mutants(RTL, D.FILES, D.STK, D.FSM_STATES, D.FSM_ALTS):
        muts.append({'id': m[0], 'cls': m[5], 'file': m[1], 'line': m[2], 'desc': m[6], 'kind': 'auto', 'spec': list(m)})
    return muts


def materialise(mut, dst):
    for f in os.listdir(RTL):
        if f.endswith('.v'):
            shutil.copy(os.path.join(RTL, f), dst)
    fn = oplib.apply_directed if mut['kind'] == 'dir' else oplib.apply_auto
    return fn(RTL, tuple(mut['spec']), dst)


def sim_one(args):
    mut, tb = args
    tmp = tempfile.mkdtemp(prefix='mut_')
    try:
        if not materialise(mut, tmp):
            return mut['id'], {'sim': 'ERROR', 'sim_detail': 'pattern not found'}
        srcs = sorted(os.path.join(tmp, f) for f in os.listdir(tmp) if f.endswith('.v')) + [os.path.join(DDIR, t) for t in tb]
        rc, out, _ = run(['iverilog', '-g2012', '-o', os.path.join(tmp, 'sim')] + srcs, tmp, 120)
        if rc != 0:
            return mut['id'], {'sim': 'INVALID', 'sim_detail': 'does not compile'}
        rc, out, dt = run(['vvp', os.path.join(tmp, 'sim')], tmp, D.SIM_TIMEOUT)
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
        res = dict(p.map(sim_one, [(m, D.TB_V1) for m in muts], chunksize=2))
    for m in muts:
        m.update(res[m['id']])
    save(muts)
    print('simulation stage:', collections.Counter(m['sim'] for m in muts), flush=True)


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


def formal_run(mut, tasks):
    tmp = tempfile.mkdtemp(prefix='fm_')
    try:
        if not materialise(mut, tmp):
            return {'formal': 'ERROR'}
        rtl = [os.path.join(tmp, f) for f in D.FILES]
        extra = [os.path.join(DDIR, f) for f in D.FORMAL_FILES]
        res, total, killed = {}, 0.0, False
        for sby, task, tmo in tasks:
            d = tempfile.mkdtemp(dir=tmp)
            r, dt = sby_task(d, os.path.join(DDIR, sby), task, rtl + extra, tmo)
            res['f_' + task] = r
            total += dt
            if r == 'FAIL':
                killed = True
                break
        res['f_time'] = round(total, 1)
        res['_killed'] = killed
        return res
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def formal_one(mut):
    res = formal_run(mut, D.FORMAL)
    res['formal'] = 'KILLED' if res.pop('_killed', False) else 'SURVIVED'
    return mut['id'], res


def deep_one(mut):
    res = formal_run(mut, D.FORMAL_DEEP)
    killed = res.pop('_killed', False)
    res['f_time'] = round(mut.get('f_time', 0) + res.get('f_time', 0), 1)
    if killed:
        res['formal'] = 'KILLED'
    return mut['id'], res


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
    if D.FORMAL_DEEP:
        todo = [m for m in muts if m.get('formal') == 'SURVIVED' and 'deep_done' not in m]
        print('deep formal pass: %d mutants' % len(todo), flush=True)
        with Pool(JOBS) as p:
            for mid, res in p.imap_unordered(deep_one, todo):
                for m in muts:
                    if m['id'] == mid: m.update(res); m['deep_done'] = True
                print('  %s %s' % (mid, res), flush=True)
                save(muts)
    print('formal:', collections.Counter(m.get('formal') for m in muts), flush=True)


# ---------------- equivalence ----------------
def touches_initial_state(mut):
    """The miter starts both copies from reset, so it cannot judge a change to a power-up value."""
    old = mut['spec'][2] if mut['kind'] == 'dir' else mut['spec'][3]
    return bool(re.match(r'^\s*(initial\b|reg\b[^;]*=)', old))


def miter_files(mut, tmp):
    """Write renamed copies of the original (orig_*) and mutant (mut_*) RTL into tmp."""
    mdir = os.path.join(tmp, 'm'); os.makedirs(mdir)
    if not materialise(mut, mdir):
        return None
    mods = []
    for f in D.FILES:
        mods += re.findall(r'^\s*module\s+(\w+)', oplib.read(os.path.join(RTL, f)), re.M)
    names = r'\b(' + '|'.join(mods) + r')\b'
    files = []
    for pre, src in (('orig', RTL), ('mut', mdir)):
        for f in D.FILES:
            fn = '%s_%s' % (pre, f)
            open(os.path.join(tmp, fn), 'w').write(re.sub(names, pre + r'_\1', oplib.read(os.path.join(src, f))))
            files.append(fn)
    return files


MITER_SBY = """[options]
mode bmc
depth %d
[engines]
smtbmc yices
[script]
read -formal %s %s
%s
prep -top miter_top
memory_map
opt_clean
setundef -undriven -init -zero
[files]
%s
"""


def run_miter(tmp, files, wrapper, depth, params):
    shutil.copy(os.path.join(DDIR, wrapper), tmp)
    w = os.path.basename(wrapper)
    ch = ' '.join('-set %s %d' % kv for kv in params.items())
    open(os.path.join(tmp, 'x.sby'), 'w').write(MITER_SBY % (depth, ' '.join(files), w,
        ('chparam %s miter_top' % ch) if params else '', '\n'.join(files + [w])))
    shutil.rmtree(os.path.join(tmp, 'x'), ignore_errors=True)
    rc, out, dt = run(['sby', '-f', 'x.sby'], tmp, 1800)
    if 'DONE (PASS' in out: return 'PASS', dt
    if 'DONE (FAIL' in out: return 'FAIL', dt
    return ('TIMEOUT' if rc == 124 else 'ERROR'), dt


def equiv_one(mut):
    """Bounded equivalence of original and mutant. The miter (design file equiv/port_miter.sv) holds both
    copies side by side, forces reset in the first cycle, starts every register from its initial value
    (zero where none is given, as with -set-init-zero in mutate.py),
    and asserts that every output is equal in every later cycle; SymbiYosys checks it to the given depth.
    This replaces the yosys miter/sat construction of mutate.py, which did not compare the uart
    sub-modules (see results/equiv_backend_notes.md)."""
    if touches_initial_state(mut):
        return mut['id'], {'equiv': 'INITIAL_STATE'}
    tmp = tempfile.mkdtemp(prefix='eq_')
    try:
        files = miter_files(mut, tmp)
        if files is None:
            return mut['id'], {'equiv': 'ERROR'}
        verdict, total = None, 0.0
        for er in D.EQ_RUNS:
            r, dt = run_miter(tmp, files, D.PORT_MITER, er['depth'], er.get('params', {}))
            total += dt
            if r == 'FAIL':
                verdict = 'DISTINGUISHABLE'; break
            if r != 'PASS':
                verdict = r; break
        if verdict is None:
            verdict = 'EQUIVALENT_' + '_'.join(str(er['depth']) for er in D.EQ_RUNS)
        return mut['id'], {'equiv': verdict, 'equiv_time': round(total, 1)}
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


def specequiv_one(mut):
    """Second look at a mutant the port-level miter could not call equivalent: compare original and
    mutant only on what the specification defines (design file equiv/spec_miter.sv), from reset, or
    from power-up for a mutant that changes an initial value (equiv/spec_miter_powerup.sv)."""
    tmp = tempfile.mkdtemp(prefix='se_')
    try:
        files = miter_files(mut, tmp)
        pu = mut.get('equiv') == 'INITIAL_STATE'
        r, dt = run_miter(tmp, files, D.SPEC_MITER_PU if pu else D.SPEC_MITER, D.SPEC_DEPTH, {})
        tag = 'POWERUP_' if pu else 'SPEC_'
        v = {'PASS': tag + 'EQUIVALENT_%d' % D.SPEC_DEPTH, 'FAIL': tag + 'DISTINGUISHABLE'}.get(r, r)
        return mut['id'], {'spec_equiv': v, 'spec_time': round(dt, 1)}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def stage_specequiv():
    muts = load()
    todo = [m for m in muts if m['sim'] == 'SURVIVED' and m.get('equiv') in ('DISTINGUISHABLE', 'INITIAL_STATE') and 'spec_equiv' not in m]
    print('specification-equivalence stage: %d mutants' % len(todo), flush=True)
    with Pool(JOBS) as p:
        for mid, res in p.imap_unordered(specequiv_one, todo):
            for m in muts:
                if m['id'] == mid: m.update(res)
            print('  %s %s' % (mid, res), flush=True)
            save(muts)


def stage_resim():
    muts = load()
    todo = [m for m in muts if m['sim'] == 'SURVIVED']
    with Pool(JOBS) as p:
        res = dict(p.map(sim_one, [(m, D.TB_V2) for m in todo], chunksize=1))
    for m in muts:
        if m['id'] in res:
            m['sim2'] = res[m['id']]['sim']
            m['sim2_detail'] = res[m['id']]['sim_detail']
        else:
            m['sim2'] = m['sim']
    save(muts)
    print('resimulation stage:', collections.Counter(m['sim2'] for m in muts), flush=True)


def stage_report():
    subprocess.run([sys.executable, os.path.join(HERE, 'flow_report.py'), D.NAME], check=True)


if __name__ == '__main__':
    setup(sys.argv[1])
    stage = sys.argv[2] if len(sys.argv) > 2 else 'sim'
    stages = {'sim': stage_sim, 'formal': stage_formal, 'equiv': stage_equiv, 'specequiv': stage_specequiv,
              'resim': stage_resim, 'report': stage_report}
    if stage == 'all':
        for s in ('sim', 'formal', 'equiv', 'specequiv', 'resim', 'report'):
            stages[s]()
    else:
        stages[stage]()
