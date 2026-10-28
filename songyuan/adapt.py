"""Adapt the PANDORA kernel patches to songyuan (Redmi K90 Pro Max, SM8850 Canoe).

Evidence for the only differing board constants:
  pandora DT panel: 1220x2656 (tools/mkadt_pandora.py: FB_W/FB_H)
  songyuan DT panel: 1200x2608 (qcom,mdss-dsi-panel-width/height = 0x4b0/0xa30)

Only '+' lines of each patch are rewritten: context lines must stay byte-identical for git apply,
and hunk headers carry line numbers (a blind replace there corrupts the patch).
"""
import os
import re

PATCHES = 'xnu/patches'
GLOBAL = [('1220', '1200'), ('2656', '2608')]
ONLY_0217 = [('SC_HALF_W         610u', 'SC_HALF_W         600u'),
             (' 0-609 ', ' 0-599 '),
             ('610-1219', '600-1199'),
             ('VIG0 0-609', 'VIG0 0-599')]


def adapt_file(path):
    src = open(path, encoding='utf-8', errors='replace').read().splitlines(True)
    out, changed = [], 0
    name = os.path.basename(path)
    for line in src:
        if line.startswith('+') and not line.startswith('+++'):
            new = line
            for a, b in GLOBAL:
                new = new.replace(a, b)
            if name.startswith('0217'):
                for a, b in ONLY_0217:
                    new = new.replace(a, b)
            if new != line:
                changed += 1
            out.append(new)
        else:
            out.append(line)
    if changed:
        open(path, 'w', encoding='utf-8', newline='\n').write(''.join(out))
    return changed


def main():
    total = 0
    for f in sorted(os.listdir(PATCHES)):
        if not f.endswith('.patch'):
            continue
        n = adapt_file(os.path.join(PATCHES, f))
        if n:
            print('adapted', f, n, 'lines')
            total += n
    print('total adapted lines:', total)


if __name__ == '__main__':
    main()
