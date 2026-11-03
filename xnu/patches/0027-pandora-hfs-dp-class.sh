#!/bin/bash
# 0027: report PROTECTION_CLASS_D from HFS getattr when a file has no cprotect record.
#
# The port's data volume is plain HFS+ with no data protection (no SEP; keybag logs
# "mount point (/private/var/) does not support Data Protection"). HFS then returns
# protection class 0, and PosterBoard's data-store viability check needs its store URLs
# to read back NSURLFileProtectionNone (PROTECTION_CLASS_D); with 0 the data store is
# never created and the first-time switcher setup hits NSAssert and traps.
#
# dxb runs patches/*.sh from the XNU source root before applying *.patch, and
# 0026-stage-hfs.sh stages bsd/sweet_hfs in the same pass, so this must sort after it.
set -euo pipefail

[[ "${MACHINE_CONFIG:-}" =~ ^(SWEET|FUXI|PANDORA)$ ]] || exit 0
[[ -f bsd/sweet_hfs/core/hfs_vnops.c ]] || exit 0

python3 - <<'PY'
from pathlib import Path
import re

path = Path('bsd/sweet_hfs/core/hfs_vnops.c')
text = path.read_text()
if '0334-dp-none' in text:
    print('hfs dp-class: already applied')
    raise SystemExit(0)

inc = '#include <vfs/vfs_support.h>\n'
add = ('\n#if defined(PANDORA)\n'
       '#include <pexpert/pexpert.h>\n'
       '#endif\n')
if inc not in text:
    raise SystemExit('hfs dp-class: include anchor missing')
text = text.replace(inc, inc + add, 1)

pat = re.compile(
    r'^[ \t]*vap->va_dataprotect_class = cp->c_cpentry \? '
    r'CP_CLASS\(cp->c_cpentry->cp_pclass\) : 0;[ \t]*$',
    re.M)
m = pat.search(text)
if not m:
    raise SystemExit('hfs dp-class: class assignment anchor missing')

block = '''#if defined(PANDORA)
\t\t/* 0334-dp-none: plain HFS+ data volume, no data protection: report D */
\t\tstatic int pandora_dp_none = -1;
\t\tif (pandora_dp_none < 0) {
\t\t\tint on = 1;
\t\t\t(void)PE_parse_boot_argn("pandora_dp_none", &on, sizeof(on));
\t\t\tpandora_dp_none = on;
\t\t}
\t\tif (cp->c_cpentry) {
\t\t\tvap->va_dataprotect_class = CP_CLASS(cp->c_cpentry->cp_pclass);
\t\t} else {
\t\t\tvap->va_dataprotect_class = pandora_dp_none ? PROTECTION_CLASS_D : 0;
\t\t}
#else
\t\tvap->va_dataprotect_class = cp->c_cpentry ? CP_CLASS(cp->c_cpentry->cp_pclass) : 0;
#endif'''
text = text[:m.start()] + block + text[m.end():]
path.write_text(text)
print('hfs dp-class: patched', path)
PY
