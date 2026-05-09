#!/usr/bin/env python3
"""psa.py - PowerShell Static Analyzer (shellcheck-equivalent)

Checks performed:
  C1  Brace balance
  C2  Paren balance
  C3  Bracket balance
  C4  Undefined variable references
  C5  Auto-variable shadowing
  C6  Start-Process -ArgumentList warning
  C7  -match against bare variable
  C8  TODO/FIXME markers
  C9  Trailing backtick before empty line
  C10 -match against empty string

Exit codes: 0=clean, 1=warnings only, 2=errors found
"""
import re, sys
from pathlib import Path

AUTO_VARS = {
    '_', '?', '$', '^',
    'args', 'consolefilename', 'error', 'event', 'eventargs',
    'eventsubscriber', 'executioncontext', 'false', 'foreach',
    'home', 'host', 'input', 'lastexitcode', 'matches', 'myinvocation',
    'nestedpromptlevel', 'null', 'ofs', 'pid', 'profile',
    'psboundparameters', 'pscmdlet', 'pscommandpath', 'psculture',
    'psdebugcontext', 'pshome', 'psitem', 'psscriptroot',
    'pssenderinfo', 'psuiculture', 'psversiontable', 'pwd',
    'sender', 'shellid', 'stacktrace', 'switch', 'this', 'true',
}


def strip_strings_and_comments(line):
    out, in_sq, in_dq, i = [], False, False, 0
    while i < len(line):
        c = line[i]
        nxt = line[i + 1] if i + 1 < len(line) else ''
        if not in_sq and not in_dq and c == '#':
            break
        if not in_dq and c == "'":
            if in_sq and nxt == "'":
                i += 2; continue
            in_sq = not in_sq; out.append(' '); i += 1; continue
        if not in_sq and c == '"':
            if in_dq and i > 0 and line[i - 1] == '`':
                out.append(c); i += 1; continue
            in_dq = not in_dq; out.append(' '); i += 1; continue
        if in_dq:
            if c == '$':
                out.append(c); i += 1
                while i < len(line) and (line[i].isalnum() or line[i] in '_:'):
                    out.append(line[i]); i += 1
                continue
            out.append(' '); i += 1; continue
        if in_sq:
            out.append(' '); i += 1; continue
        out.append(c); i += 1
    return ''.join(out)


def check_balance(text, open_ch, close_ch, code, name):
    in_sq = in_dq = in_lc = in_bc = False
    open_cnt = close_cnt = 0
    line_no = 1
    i = 0
    while i < len(text):
        c = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ''
        if c == '\n':
            line_no += 1; in_lc = False; i += 1; continue
        if not in_sq and not in_dq:
            if not in_bc and c == '<' and nxt == '#':
                in_bc = True; i += 2; continue
            if in_bc and c == '#' and nxt == '>':
                in_bc = False; i += 2; continue
            if in_bc:
                i += 1; continue
            if c == '#' and not in_lc:
                in_lc = True; i += 1; continue
            if in_lc:
                i += 1; continue
        if not in_dq and c == "'":
            if in_sq and nxt == "'":
                i += 2; continue
            in_sq = not in_sq; i += 1; continue
        if not in_sq and c == '"':
            if in_dq and i > 0 and text[i - 1] == '`':
                i += 1; continue
            in_dq = not in_dq; i += 1; continue
        if in_sq or in_dq:
            i += 1; continue
        if c == open_ch:
            open_cnt += 1
        elif c == close_ch:
            close_cnt += 1
        i += 1
    if open_cnt != close_cnt:
        return [{'severity': 'error', 'code': code, 'line': 0,
                 'message': f'{name} mismatch: {open_cnt} {open_ch} vs {close_cnt} {close_ch}'}]
    return []


ASSIGN_PATTERNS = [
    # $Name = ..., $Script:Name = ..., $local:Name = ... (scope is case-insensitive)
    re.compile(r'\$(?:[A-Za-z]+:)?([A-Za-z_][A-Za-z0-9_]*)\s*='),
    re.compile(r'foreach\s*\(\s*\$([A-Za-z_][A-Za-z0-9_]*)\s+in\b', re.IGNORECASE),
    re.compile(r'for\s*\(\s*\$([A-Za-z_][A-Za-z0-9_]*)\s*=', re.IGNORECASE),
]
PARAM_PATTERN = re.compile(r'\bparam\s*\(([^)]*?)\)', re.IGNORECASE | re.DOTALL)
PARAM_VAR = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)')
# Inline param syntax: function Name ($a, $b, $c) { ... }
INLINE_FN_PARAMS = re.compile(
    r'^\s*function\s+[A-Za-z_][A-Za-z0-9_-]*\s*\(([^)]*)\)\s*\{?',
    re.IGNORECASE)
# Reference: $name | $Script:name | $env:VAR  (env/using are skipped later)
REFERENCE_PATTERN = re.compile(
    r'\$(?:(?P<scope>[A-Za-z]+):)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)')
EXTERNAL_SCOPES = {'env', 'using'}


def find_function_blocks(text):
    blocks, lines, i = [], text.split('\n'), 0
    while i < len(lines):
        m = re.match(r'^\s*function\s+([A-Za-z_][A-Za-z0-9_-]*)\s*\{?', lines[i])
        if not m:
            i += 1; continue
        name, start, depth, seen, j = m.group(1), i, 0, False, i
        while j < len(lines):
            for ch in strip_strings_and_comments(lines[j]):
                if ch == '{':
                    depth += 1; seen = True
                elif ch == '}':
                    depth -= 1
            if seen and depth == 0:
                break
            j += 1
        body = '\n'.join(lines[start:j + 1])
        blocks.append((name, start + 1, j + 1, body))
        i = j + 1
    return blocks


def find_param_blocks(body):
    """Find all param(...) blocks with properly balanced parens.
    Returns the inner content of each param block."""
    blocks = []
    pat = re.compile(r'\bparam\s*\(', re.IGNORECASE)
    pos = 0
    while True:
        m = pat.search(body, pos)
        if not m:
            break
        start = m.end()
        depth = 1
        i = start
        while i < len(body) and depth > 0:
            c = body[i]
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            i += 1
        if depth == 0:
            blocks.append(body[start:i - 1])
        pos = i
    return blocks


def collect_assignments(body):
    assigned = set()
    for line in body.split('\n'):
        clean = strip_strings_and_comments(line)
        for pat in ASSIGN_PATTERNS:
            for m in pat.finditer(clean):
                assigned.add(m.group(1).lower())
        # Inline param syntax on the function line itself.
        m = INLINE_FN_PARAMS.match(clean)
        if m:
            for vm in PARAM_VAR.finditer(m.group(1)):
                assigned.add(vm.group(1).lower())
    # Multi-line param() blocks with balanced parens (handles
    # [Parameter(Mandatory)] [type]$Name etc.)
    full = '\n'.join(strip_strings_and_comments(l) for l in body.split('\n'))
    for block in find_param_blocks(full):
        for vm in PARAM_VAR.finditer(block):
            assigned.add(vm.group(1).lower())
    return assigned


def collect_references(body):
    refs = []
    for ln_no, line in enumerate(body.split('\n'), start=1):
        clean = strip_strings_and_comments(line)
        for m in REFERENCE_PATTERN.finditer(clean):
            scope = (m.group('scope') or '').lower()
            if scope in EXTERNAL_SCOPES:
                continue  # $env:X, $using:X are externally defined
            after = clean[m.end():m.end() + 4].lstrip()
            if after.startswith('='):
                continue
            refs.append((m.group('name').lower(), ln_no))
    return refs


def check_undefined_vars(text):
    issues, blocks = [], find_function_blocks(text)
    fn_ranges = [(b[1], b[2]) for b in blocks]
    def in_fn(n):
        for s, e in fn_ranges:
            if s <= n <= e:
                return True
        return False
    global_assigned = set()
    for ln_no, line in enumerate(text.split('\n'), start=1):
        if in_fn(ln_no):
            continue
        clean = strip_strings_and_comments(line)
        for pat in ASSIGN_PATTERNS:
            for m in pat.finditer(clean):
                global_assigned.add(m.group(1).lower())
    seen = set()
    for fname, start, _end, body in blocks:
        local = collect_assignments(body)
        for name, ln in collect_references(body):
            if name in AUTO_VARS or name in local or name in global_assigned:
                continue
            key = (name, fname)
            if key in seen:
                continue
            seen.add(key)
            issues.append({'severity': 'error', 'code': 'C4',
                           'line': start + ln - 1,
                           'message': f'undefined variable ${name} in function {fname}'})
    return issues


def check_argumentlist(text):
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        clean = strip_strings_and_comments(line)
        if re.search(r'Start-Process\b.*-ArgumentList\b', clean, re.IGNORECASE):
            out.append({'severity': 'warning', 'code': 'C6', 'line': ln,
                        'message': 'Start-Process -ArgumentList; prefer ProcessStartInfo'})
    return out


def check_match_var(text):
    pat = re.compile(r'-match\s+\$(?!null\b)([A-Za-z_][A-Za-z0-9_:]*)', re.IGNORECASE)
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        clean = strip_strings_and_comments(line)
        for m in pat.finditer(clean):
            out.append({'severity': 'warning', 'code': 'C7', 'line': ln,
                        'message': f'-match against bare ${m.group(1)} - $null pattern returns true'})
    return out


def check_shadow(text):
    risky = {'args', 'lastexitcode', 'input', 'matches', 'foreach',
             'host', 'true', 'false'}
    # Note: $null = ... is NOT flagged because it is a standard
    # PowerShell idiom for suppressing output (equivalent to | Out-Null).
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        clean = strip_strings_and_comments(line)
        for m in re.finditer(r'\$([A-Za-z_][A-Za-z0-9_]*)\s*=', clean):
            if m.group(1).lower() in risky:
                out.append({'severity': 'warning', 'code': 'C5', 'line': ln,
                            'message': f'shadowing auto-variable ${m.group(1)}'})
    return out


def check_todo(text):
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        m = re.search(r'\b(TODO|FIXME|XXX|HACK)\b', line)
        if m:
            out.append({'severity': 'info', 'code': 'C8', 'line': ln,
                        'message': f'unfinished marker: {m.group(1)}'})
    return out


def check_backtick(text):
    out, lines = [], text.split('\n')
    for i, line in enumerate(lines):
        s = line.rstrip('\r\n')
        if s.endswith('`') and not s.endswith('``'):
            if i + 1 < len(lines) and not lines[i + 1].strip():
                out.append({'severity': 'warning', 'code': 'C9', 'line': i + 1,
                            'message': 'backtick continuation followed by empty line'})
    return out


def check_empty_match(text):
    pat = re.compile(r"-match\s+(?:''|\"\")")
    out = []
    for ln, line in enumerate(text.split('\n'), 1):
        if pat.search(line):
            out.append({'severity': 'warning', 'code': 'C10', 'line': ln,
                        'message': '-match against empty string is always true'})
    return out


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr); return 2
    path = Path(sys.argv[1])
    text = path.read_text(encoding='utf-8', errors='replace')

    issues = []
    issues += check_balance(text, '{', '}', 'C1', 'Brace')
    issues += check_balance(text, '(', ')', 'C2', 'Paren')
    issues += check_balance(text, '[', ']', 'C3', 'Bracket')
    issues += check_undefined_vars(text)
    issues += check_shadow(text)
    issues += check_argumentlist(text)
    issues += check_match_var(text)
    issues += check_todo(text)
    issues += check_backtick(text)
    issues += check_empty_match(text)
    issues.sort(key=lambda x: (x['line'], x['code']))

    err = sum(1 for i in issues if i['severity'] == 'error')
    warn = sum(1 for i in issues if i['severity'] == 'warning')
    info = sum(1 for i in issues if i['severity'] == 'info')

    print('==== psa.py: PowerShell Static Analyzer ====')
    print(f'File   : {path}')
    print(f'Lines  : {len(text.splitlines())}')
    print(f'Issues : {err} errors, {warn} warnings, {info} info\n')

    if not issues:
        print('  (no issues found)')
    else:
        for sev in ('error', 'warning', 'info'):
            sub = [i for i in issues if i['severity'] == sev]
            if not sub:
                continue
            print(f'---- {sev.upper()} ({len(sub)}) ----')
            for i in sub:
                print(f"  [{i['code']}] line {i['line']:>5}: {i['message']}")
            print()

    return 2 if err else (1 if warn else 0)


if __name__ == '__main__':
    sys.exit(main())
