#!/bin/bash
# Remove the Galaxy Book4 speaker fix (driver, services, autoload config).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
. "$REPO/lib/common.sh"

require_root
remove_all
log "Uninstalled. Reboot to return to the stock audio state."
