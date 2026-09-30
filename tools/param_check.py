"""Catch named parameters used on widgets that don't accept them.

Brace/import checks can't see this class of bug — the code parses fine and
every symbol resolves; it only fails at type-check time. This encodes the
parameters a handful of commonly-used widgets genuinely DON'T have.
"""
import os, re

# widget -> params it does NOT accept
FORBIDDEN = {
    'ExpansionTile': ['onLongPress', 'onPressed', 'dense', 'isThreeLine'],
    'Card':          ['onTap', 'onLongPress', 'title', 'subtitle', 'leading'],
    'Container':     ['onTap', 'onLongPress', 'elevation', 'title'],
    'Column':        ['onTap', 'padding', 'scrollDirection'],
    'Row':           ['onTap', 'padding', 'scrollDirection'],
    'SizedBox':      ['onTap', 'padding', 'color'],
    'Text':          ['onTap', 'onPressed', 'padding'],
    'Icon':          ['onTap', 'onPressed'],
    'CheckboxListTile': ['onLongPress'],
    'SwitchListTile':   ['onLongPress', 'onTap'],
    'PageView':      ['padding', 'shrinkWrap'],
    'Spacer':        ['height', 'width'],
    'CircularProgressIndicator': ['size'],
    'LinearProgressIndicator':   ['size', 'strokeWidth'],
}

def scan(path):
    src = open(path).read()
    out = []
    for widget, bad_params in FORBIDDEN.items():
        for m in re.finditer(r'\b' + widget + r'\(', src):
            # take a bounded slice and stop at the matching close paren
            i = m.end(); depth = 1; j = i
            while j < len(src) and depth > 0:
                if src[j] == '(': depth += 1
                elif src[j] == ')': depth -= 1
                j += 1
            body = src[i:j]
            # only look at THIS widget's own args (depth-1 commas)
            d = 0; top = []
            cur = []
            for ch in body:
                if ch in '([{': d += 1
                elif ch in ')]}': d -= 1
                if ch == ',' and d == 0:
                    top.append(''.join(cur)); cur = []
                else:
                    cur.append(ch)
            top.append(''.join(cur))
            for arg in top:
                nm = re.match(r'\s*(\w+)\s*:', arg)
                if nm and nm.group(1) in bad_params:
                    line = src[:m.start()].count('\n') + 1
                    out.append(f"{path}:{line}  {widget} has no '{nm.group(1)}'")
    return out

problems = []
for root, _, files in os.walk('lib'):
    for f in sorted(files):
        if f.endswith('.dart'):
            problems += scan(os.path.join(root, f))
print("\n".join(sorted(set(problems))) if problems else "PARAM CHECK: CLEAN")
