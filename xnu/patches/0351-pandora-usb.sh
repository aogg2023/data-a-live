#!/bin/sh
# 0351: the build's dxb tree has no pandora entries in bsd/conf/files yet, and this script runs
# before the .patch files, so append the objects of bsd/dev/pandora_usb.c and bsd/dev/qcomusb/
# at the end of the file list (order is irrelevant). The call into pandora_usb_init lives in the
# 0351-pandora-usb.patch hunk on bsd/dev/pandora_cachevol.c, whose post-0350 content is known.
set -e
f=bsd/conf/files
if grep -q '^bsd/dev/pandora_usb\.c' "$f"; then
	echo "0351: conf/files already lists pandora_usb.c"
	exit 0
fi
cat >> "$f" <<'EOF'

# 0351: DWC3 device-mode USB serial console (boot-arg pandora_usb=2 qcom-usb-debug=1)
bsd/dev/pandora_usb.c			standard
bsd/dev/qcomusb/kernel/QcomXnuUsbDebug.c		standard
bsd/dev/qcomusb/kernel/QcomUsbScreenshot.c		standard
bsd/dev/qcomusb/usb/Dwc3.c		standard
bsd/dev/qcomusb/soc/QcomUsbQualify.c		standard
bsd/dev/qcomusb/soc/QcomUsbDmaDomain.c		standard
bsd/dev/qcomusb/soc/QcomUsbBypass.c		standard
bsd/dev/qcomusb/soc/QcomUsbPrepare.c		standard
EOF
echo "0351: appended pandora_usb and qcomusb to conf/files"
