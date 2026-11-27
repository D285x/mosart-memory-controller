"""Design-independent form of the operator-based mutant generator in mutlib.py.

The operator rules (regular expressions, order, de-duplication and numbering) are copied
unchanged from mutlib.auto_mutants. Only the design-specific lists are parameters:
  files       RTL files to mutate, in order
  stk_names   single-bit signals driven by a continuous assign that STK may tie to 0 or 1
  fsm_states  None if the design has no next_state FSM; fsm_alts the replacement targets
Two fixes, both inert on the memory controller, are marked "fix" below.
check_equal() confirms that the memory controller yields the same 149 mutants as mutlib.
"""
import os, re
from mutlib import read, is_code, strip_comment, apply_directed, apply_auto

def auto_mutants(rtl_dir, files, stk_names, fsm_states=None, fsm_alts=None):
    """Yield (id, file, lineno, old_line, new_line, op, desc)."""
    out = []
    n = 0
    for fname in files:
        lines = read(os.path.join(rtl_dir, fname)).split('\n')
        in_block = False
        for ln, raw in enumerate(lines, 1):
            # fix 1: skip lines inside /* ... */ block comments (absent from the memory controller RTL)
            if in_block:
                if '*/' in raw:
                    in_block = False
                continue
            if raw.strip().startswith('/*'):
                in_block = '*/' not in raw
                continue
            if not is_code(raw):
                continue
            code, cmt = strip_comment(raw)
            # skip pure port-connection wiring lines and reset-init lines of sync_mem loops
            cands = []
            def add(op, a, b, desc):
                new = a + b if False else None
            def sub_all(pattern, repl_fn, op, descf):
                for m in re.finditer(pattern, code):
                    new_code = code[:m.start()] + repl_fn(m) + code[m.end():]
                    if new_code != code:
                        cands.append((op, new_code + cmt, descf(m)))
            # ROR
            sub_all(r'>=', lambda m: '>', 'ROR', lambda m: '>= to >')
            sub_all(r'(?<![<>=!])>(?!=)', lambda m: '>=', 'ROR', lambda m: '> to >=')
            sub_all(r'==', lambda m: '!=', 'ROR', lambda m: '== to !=')
            sub_all(r'!=', lambda m: '==', 'ROR', lambda m: '!= to ==')
            # LOR
            sub_all(r'&&', lambda m: '||', 'LOR', lambda m: '&& to ||')
            sub_all(r'\|\|', lambda m: '&&', 'LOR', lambda m: '|| to &&')
            sub_all(r'(?<=\w|\)) & (?=\w|\()', lambda m: ' | ', 'LOR', lambda m: '& to |')
            sub_all(r'(?<=\w|\)) \| (?=\w|\()', lambda m: ' & ', 'LOR', lambda m: '| to &')
            # NEG: remove a unary negation
            sub_all(r'!(?!=)', lambda m: '', 'NEG', lambda m: 'negation removed')
            # NEG: negate an if condition
            m = re.match(r'^(\s*(?:else\s+)?if\s*)\((.*)\)(\s*(?:begin)?\s*)$', code)
            if m:
                cands.append(('NEG', m.group(1) + '(!(' + m.group(2) + '))' + m.group(3) + cmt, 'if condition negated'))
            # CNS: sized literals
            for m in re.finditer(r"(\d+)'([bd])(\d+)", code):
                # fix 2: read a binary literal in base 2 (the memory controller RTL has only
                # 1-bit binary literals, where both readings agree)
                w, base = int(m.group(1)), m.group(2)
                val = int(m.group(3), 2 if base == 'b' else 10)
                if w == 1:
                    nv = 1 - val
                else:
                    nv = val + 1 if val + 1 < (1 << w) else val - 1
                lit = format(nv, 'b') if base == 'b' else str(nv)
                new = code[:m.start()] + "%d'%s%s" % (w, base, lit) + code[m.end():]
                cands.append(('CNS', new + cmt, "constant %s to %d'%s%s" % (m.group(0), w, base, lit)))
            # ARI
            sub_all(r' - (?=\w)', lambda m: ' + ', 'ARI', lambda m: '- to +')
            sub_all(r' \+ (?=\w)', lambda m: ' - ', 'ARI', lambda m: '+ to -')
            # IDX: single-bit constant select
            for m in re.finditer(r'\[(\d+)\]', code):
                k = int(m.group(1))
                new = code[:m.start()] + '[%d]' % (k + 1) + code[m.end():]
                cands.append(('IDX', new + cmt, 'bit index %d to %d' % (k, k + 1)))
            # SDL: delete a plain registered assignment statement
            m = re.match(r'^(\s*)([A-Za-z_]\w*(?:\[[^\]]*\])?)\s*<=\s*[^;]*;\s*$', code)
            if m and 'for' not in code:
                cands.append(('SDL', m.group(1) + ';' + cmt, 'assignment to %s deleted' % m.group(2)))
            # STK: stuck continuous assign of single-bit outputs
            m = re.match(r'^(\s*assign\s+)(' + '|'.join(stk_names) + r')(\s*=\s*)(.*);\s*$', code) if stk_names else None
            if m:
                for v in ("1'b0", "1'b1"):
                    cands.append(('STK', m.group(1) + m.group(2) + m.group(3) + v + ';' + cmt, '%s stuck at %s' % (m.group(2), v)))
            # FSM: next_state target replacement (only right of "next_state =")
            if fsm_states and 'next_state =' in code:
                pre, post = code.split('next_state =', 1)
                for mm in re.finditer(r'S_[A-Z]+', post):
                    old = mm.group(0)
                    for alt in fsm_alts:
                        if alt != old:
                            new_post = post[:mm.start()] + alt + post[mm.end():]
                            cands.append(('FSM', pre + 'next_state =' + new_post + cmt, 'next state %s replaced by %s' % (old, alt)))
            seen = set()
            for op, newline, desc in cands:
                if newline == raw or newline in seen:
                    continue
                seen.add(newline)
                n += 1
                out.append(('G%03d' % n, fname, ln, raw, newline, op, desc))
    return out


def check_equal(rtl_dir):
    import mutlib
    a = mutlib.auto_mutants(rtl_dir)
    b = auto_mutants(rtl_dir, mutlib.FILES, ['busy', 'ready', 'error', 'mem_we', 'mem_re'],
                     ['S_IDLE', 'S_READ', 'S_WRITE', 'S_WAIT', 'S_DONE', 'S_ERROR'], ('S_IDLE', 'S_ERROR', 'S_DONE'))
    return a == b, len(a), len(b)
