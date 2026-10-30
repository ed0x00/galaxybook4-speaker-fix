#!/bin/bash
# Galaxy Book4 speaker fix installer (MAX98390 amps, with idle power-off).
# Usage: sudo ./install.sh [--distro arch|debian] [--no-snapshot] [--force]
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
. "$REPO/lib/common.sh"

DISTRO=""
NO_SNAPSHOT=false
FORCE=false
NEEDS_REBOOT=false

while [ $# -gt 0 ]; do
	case "$1" in
		--distro)      DISTRO="${2:-}"; shift ;;
		--no-snapshot) NO_SNAPSHOT=true ;;
		--force)       FORCE=true ;;
		-h|--help)     sed -n '2,3s/^# //p' "$0"; exit 0 ;;
		*)             die "Unknown option: $1" ;;
	esac
	shift
done

require_root
[ -n "$DISTRO" ] || DISTRO="$(detect_distro)"
[ -f "$REPO/distro/$DISTRO/distro.sh" ] || \
	die "Unsupported distro '$DISTRO'. Pass --distro arch or --distro debian if yours is a derivative."
. "$REPO/distro/$DISTRO/distro.sh"

log "Galaxy Book4 speaker fix ${DKMS_VER} — distro: $DISTRO, kernel: $KVER"
check_hardware
take_snapshot
distro_deps
check_kernel
install_driver
distro_sign
install_system_files
$NEEDS_REBOOT || reload_driver

echo
if $NEEDS_REBOOT; then
	log "Installed. Reboot and complete the MOK enrollment screen to load the driver."
else
	log "Installed and loaded. Check it with: $REPO/tools/verify.sh"
fi
