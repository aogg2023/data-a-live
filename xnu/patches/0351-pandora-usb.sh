#!/bin/sh
# 0351: wire bsd/dev/pandora_usb.c (DWC3 CDC ACM console, boot-arg pandora_usb=2) into the tree.
# The source tree this runs on is the build's, not ours, and has no pandora_therm.c/pandora_usb.c lines,
# so the four small edits are anchored instead of context diffs; a missing anchor fails loudly.
set -e
python3 - <<'PY'
import re, sys

def fail(msg):
    sys.exit("0351: " + msg)

# 1. bsd/conf/files: the new objects
p = "bsd/conf/files"
s = open(p).read()
if "bsd/dev/pandora_usb.c" not in s:
    m = re.search(r"^bsd/dev/pandora_cpu\.c.*$", s, re.M)
    if not m:
        m = re.search(r"^bsd/dev/pandora_gpu\.c.*$", s, re.M)
    if not m:
        fail("conf/files: no pandora anchor")
    add = ("\nbsd/dev/pandora_usb.c\t\tstandard"
           "\nbsd/dev/qcomusb/kernel/QcomXnuUsbDebug.c\t\tstandard"
           "\nbsd/dev/qcomusb/kernel/QcomUsbScreenshot.c\t\tstandard"
           "\nbsd/dev/qcomusb/usb/Dwc3.c\t\tstandard"
           "\nbsd/dev/qcomusb/soc/QcomUsbQualify.c\t\tstandard"
           "\nbsd/dev/qcomusb/soc/QcomUsbDmaDomain.c\t\tstandard"
           "\nbsd/dev/qcomusb/soc/QcomUsbBypass.c\t\tstandard"
           "\nbsd/dev/qcomusb/soc/QcomUsbPrepare.c\t\tstandard")
    s = s[:m.end()] + add + s[m.end():]
    open(p, "w").write(s)

p = "bsd/dev/sweet_ufs.c"
s = open(p).read()

# 2. the externs, beside the other PANDORA inits
if "extern void pandora_usb_init(void);" not in s:
    m = re.search(r"^extern void pandora_cpu_init\(void\);$", s, re.M)
    if not m:
        m = re.search(r"^extern void pandora_gpu_init\(void\);$", s, re.M)
    if not m:
        fail("sweet_ufs.c: no pandora extern anchor")
    add = "\nextern void pandora_usb_init(void);\nextern void pandora_usb_final(void);"
    s = s[:m.end()] + add + s[m.end():]

# 3. start it from sweet_ufs_init (same place as the other PANDORA inits)
if "pandora_usb_init();" not in s:
    m = re.search(r"^\tpandora_cpu_init\(\);$", s, re.M)
    if not m:
        m = re.search(r"^\tpandora_gpu_init\(\);$", s, re.M)
    if not m:
        fail("sweet_ufs.c: no pandora init call anchor")
    s = s[:m.end()] + "\n\tpandora_usb_init();" + s[m.end():]

# 4. drain the serial log before the PSCI reset
if "pandora_usb_final();" not in s:
    i = s.find("pl_psci_reset(void)")
    if i < 0:
        fail("sweet_ufs.c: pl_psci_reset missing")
    j = s.find("register uint64_t x0", i)
    if j < 0:
        fail("sweet_ufs.c: PSCI reset register line missing")
    ins = ("#if defined(PANDORA)\n"
           "\t/* the USB serial log's last bytes (bsd/dev/pandora_usb.c; nothing without pandora_usb=2) */\n"
           "\tpandora_usb_final();\n"
           "#endif\n")
    s = s[:j] + ins + s[j:]
open(p, "w").write(s)
print("0351: pandora_usb wired into conf/files and sweet_ufs.c")
PY
