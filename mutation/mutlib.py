"""Mutant generation for the memory controller RTL.

Two sources:
  * DIRECTED: the 19 hand-written semantic mutants of the first study (M01..M19).
  * AUTO: operator-based mutants generated mechanically from the RTL text.

Operator classes (as in classic mutation testing):
  ROR  relational operator replacement      (>= > < == !=)
  LOR  logical/bitwise operator replacement (&& || & |)
  NEG  condition negation / negation removal
  CNS  constant replacement                 (sized literals)
  ARI  arithmetic operator replacement      (+ -)
  IDX  bit-select index shift
  SDL  statement deletion                   (registered assignment removed)
  STK  output stuck-at                      (continuous assign tied to 0 or 1)
  FSM  state target replacement
  CON  port connection swap (top level wiring)
"""
import os, re

FILES = ['mem_ctrl_fsm.v', 'cfg_regs.v', 'sync_mem.v', 'mem_ctrl_top.v']

DIRECTED = [
 ('M01', 'mem_ctrl_fsm.v', "next_state = (wait_states != 3'd0) ? S_WAIT : S_DONE;", "next_state = S_DONE;", 'wait states ignored'),
 ('M02', 'mem_ctrl_fsm.v', "next_state = (wcnt == 3'd0) ? S_DONE : S_WAIT;", "next_state = (wcnt == 3'd1) ? S_DONE : S_WAIT;", 'one wait state too few'),
 ('M03', 'mem_ctrl_fsm.v', "wcnt <= wait_states - 3'd1;", "wcnt <= wait_states;", 'one wait state too many'),
 ('M04', 'mem_ctrl_fsm.v', "wire range_bad = ({1'b0, address} >= addr_limit);", "wire range_bad = ({1'b0, address} >  addr_limit);", 'range check off by one'),
 ('M05', 'mem_ctrl_fsm.v', "wire wp_bad   = write_enable & wp;", "wire wp_bad   = 1'b0;", 'write protect ignored'),
 ('M06', 'mem_ctrl_fsm.v', "if (coll || range_bad || wp_bad) next_state = S_ERROR;", "if (range_bad || wp_bad) next_state = S_ERROR;", 'collision not rejected'),
 ('M07', 'mem_ctrl_fsm.v', "ev_ovr   <= (state != S_IDLE) && req;", "ev_ovr   <= 1'b0;", 'overrun never flagged'),
 ('M08', 'mem_ctrl_fsm.v', "assign ready     = (state == S_DONE) || (state == S_ERROR);", "assign ready     = (state == S_DONE);", 'ready missing on rejected request'),
 ('M09', 'mem_ctrl_fsm.v', "wdata_q <= write_data;", "wdata_q <= {DATA_W{1'b0}};", 'write data not latched'),
 ('M10', 'mem_ctrl_fsm.v', "if (en && req) begin\n                    if (coll", "if (req) begin\n                    if (coll", 'enable bit ignored'),
 ('M11', 'mem_ctrl_fsm.v', "ev_range <= (state == S_IDLE) && en && req && !coll && range_bad;", "ev_range <= (state == S_IDLE) && req && !coll && range_bad;", 'range event raised while disabled'),
 ('M12', 'cfg_regs.v', "sticky <= (sticky & ~clr) | set;", "sticky <= (sticky | set);", 'write-one-to-clear broken'),
 ('M13', 'cfg_regs.v', "sticky <= (sticky & ~clr) | set;", "sticky <= (sticky | set) & ~clr;", 'clear wins over a same-cycle event'),
 ('M14', 'cfg_regs.v', "A_LIMIT: addr_limit  <= (cfg_wdata[ADDR_W:0] > (1 << ADDR_W))\n                                            ? (1 << ADDR_W) : cfg_wdata[ADDR_W:0];", "A_LIMIT: addr_limit  <= cfg_wdata[ADDR_W:0];", 'limit not saturated'),
 ('M15', 'cfg_regs.v', "wp          <= 1'b0;", "wp          <= 1'b1;", 'wrong reset value of write protect'),
 ('M16', 'cfg_regs.v', "A_WAIT : wait_states <= cfg_wdata[2:0];", "A_WAIT : wait_states <= {1'b0, cfg_wdata[1:0]};", 'wait register loses its top bit'),
 ('M17', 'cfg_regs.v', "default: cfg_rdata = {3'b0, busy, sticky};", "default: cfg_rdata = {3'b0, 1'b0, sticky};", 'BUSY bit missing from STATUS'),
 ('M18', 'cfg_regs.v', "A_CTRL : begin en <= cfg_wdata[0]; wp <= cfg_wdata[1]; end", "A_CTRL : begin en <= cfg_wdata[1]; wp <= cfg_wdata[0]; end", 'EN and WP bits swapped'),
 ('M19', 'sync_mem.v', "if (mem_we)\n            mem[mem_addr] <= mem_wdata;", "if (mem_we && mem_addr != 0)\n            mem[mem_addr] <= mem_wdata;", 'word 0 cannot be written'),
]

# Extra directed wiring and memory mutants
DIRECTED += [
 ('M20', 'mem_ctrl_top.v', ".mem_we(mem_we), .mem_re(mem_re),\n        .mem_addr(mem_addr), .mem_wdata(mem_wdata),\n        .mem_rdata(read_data)", ".mem_we(mem_re), .mem_re(mem_we),\n        .mem_addr(mem_addr), .mem_wdata(mem_wdata),\n        .mem_rdata(read_data)", 'memory read and write strobes swapped'),
 ('M21', 'mem_ctrl_top.v', ".ev_coll(ev_coll), .ev_range(ev_range), .ev_wpv(ev_wpv),\n        .ev_ovr(ev_ovr), .busy(busy)", ".ev_coll(ev_range), .ev_range(ev_coll), .ev_wpv(ev_wpv),\n        .ev_ovr(ev_ovr), .busy(busy)", 'COLL and RANGE events swapped at the register file'),
 ('M22', 'sync_mem.v', "if (mem_re)\n            mem_rdata <= mem[mem_addr];", "mem_rdata <= mem[mem_addr];", 'read data not held between reads'),
 ('M23', 'sync_mem.v', "mem[i] = {DATA_W{1'b0}};", "mem[i] = {DATA_W{1'b1}};", 'memory initialised to ones'),
]

def read(path):
    return open(path, newline='').read().replace('\r\n', '\n')

def is_code(line):
    s = line.strip()
    if not s or s.startswith('//'):
        return False
    if re.match(r'^(module|endmodule|input|output|parameter|localparam|\)\s*;|\)\(|`)', s):
        return False
    if re.match(r'^(reg|wire|integer)\b', s) and '=' not in s:
        return False
    return True

def strip_comment(line):
    i = line.find('//')
    return (line[:i], line[i:]) if i >= 0 else (line, '')

def auto_mutants(rtl_dir):
    """Yield (id, file, lineno, old_line, new_line, op, desc)."""
    out = []
    n = 0
    for fname in FILES:
        lines = read(os.path.join(rtl_dir, fname)).split('\n')
        for ln, raw in enumerate(lines, 1):
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
                w, base, val = int(m.group(1)), m.group(2), int(m.group(3))
                if w == 1:
                    nv = 1 - val
                else:
                    nv = val + 1 if val + 1 < (1 << w) else val - 1
                new = code[:m.start()] + "%d'%s%d" % (w, base, nv) + code[m.end():]
                cands.append(('CNS', new + cmt, "constant %s to %d'%s%d" % (m.group(0), w, base, nv)))
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
            m = re.match(r'^(\s*assign\s+)(busy|ready|error|mem_we|mem_re)(\s*=\s*)(.*);\s*$', code)
            if m:
                for v in ("1'b0", "1'b1"):
                    cands.append(('STK', m.group(1) + m.group(2) + m.group(3) + v + ';' + cmt, '%s stuck at %s' % (m.group(2), v)))
            # FSM: next_state target replacement (only right of "next_state =")
            if 'next_state =' in code:
                pre, post = code.split('next_state =', 1)
                states = ['S_IDLE', 'S_READ', 'S_WRITE', 'S_WAIT', 'S_DONE', 'S_ERROR']
                for mm in re.finditer(r'S_[A-Z]+', post):
                    old = mm.group(0)
                    for alt in ('S_IDLE', 'S_ERROR', 'S_DONE'):
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

def apply_directed(rtl_dir, mut, dst_dir):
    mid, fname, old, new, desc = mut
    path = os.path.join(dst_dir, fname)
    text = read(path)
    if text.count(old) != 1:
        return False
    open(path, 'w', newline='').write(text.replace(old, new))
    return True

def apply_auto(rtl_dir, mut, dst_dir):
    mid, fname, ln, old, new, op, desc = mut
    path = os.path.join(dst_dir, fname)
    lines = read(path).split('\n')
    if lines[ln - 1] != old:
        return False
    lines[ln - 1] = new
    open(path, 'w', newline='').write('\n'.join(lines))
    return True
