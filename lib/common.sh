# Shared install logic. Sourced by install.sh / uninstall.sh, which set $REPO.
# Distro files (distro/<name>/distro.sh) provide distro_deps and distro_sign.

DKMS_NAME="max98390-hda"
DKMS_VER="$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$REPO/driver/dkms.conf")"
KVER="$(uname -r)"
MIN_KERNEL="6.13"   # string-literal module namespaces used by the driver

log()  { echo -e "\e[32m==>\e[0m $*"; }
warn() { echo -e "\e[33m!!\e[0m $*" >&2; }
die()  { echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }

require_root() {
	[ "$(id -u)" -eq 0 ] || die "Run with sudo"
}

detect_distro() {
	local id like
	id="$(. /etc/os-release && echo "${ID:-}")"
	like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
	case " $id $like " in
		*" arch "*)                 echo arch ;;
		*" debian "*|*" ubuntu "*)  echo debian ;;
		*)                          echo unknown ;;
	esac
}

secure_boot_enabled() {
	local var
	var="$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1)"
	[ -n "$var" ] && [ "$(od -An -t u1 -j4 -N1 "$var" | tr -d ' ')" = "1" ]
}

sof_firmware_present() {
	ls -d /lib/firmware/intel/sof* &>/dev/null
}

installed_module() {
	find "/lib/modules/$KVER/updates" -name "snd-hda-scodec-max98390.ko*" 2>/dev/null | head -1
}

check_hardware() {
	if ls /sys/bus/acpi/devices/MAX98390:* &>/dev/null || \
	   grep -qs "MAX98390" /sys/bus/i2c/devices/*/name; then
		return 0
	fi
	$FORCE && { warn "No MAX98390 amplifier detected — continuing (--force)"; return 0; }
	die "No MAX98390 amplifier detected. This fix is for Galaxy Book4/Book5 models
       with MAX98390 speaker amps (see README). Use --force to install anyway."
}

check_kernel() {
	local base="${KVER%%-*}"
	if [ "$(printf '%s\n%s\n' "$MIN_KERNEL" "$base" | sort -V | head -1)" != "$MIN_KERNEL" ]; then
		die "Kernel $KVER is too old; the driver needs Linux $MIN_KERNEL or newer."
	fi
	[ -d "/lib/modules/$KVER/build" ] || die "Kernel headers for $KVER are missing (/lib/modules/$KVER/build)."
}

# Take a system snapshot before touching kernel modules. Prefers Omarchy's
# helper (Limine boot-menu entries), then plain snapper, then Timeshift.
take_snapshot() {
	$NO_SNAPSHOT && { warn "Skipping snapshot (--no-snapshot)"; return 0; }

	local omarchy_bin=/usr/share/omarchy/bin
	if [ -x "$omarchy_bin/omarchy-snapshot" ]; then
		log "Creating snapshot with omarchy-snapshot (selectable from the Limine boot menu)"
		PATH="$omarchy_bin:$PATH" omarchy-snapshot create && return 0
	elif command -v snapper >/dev/null && [ -n "$(snapper --csvout list-configs 2>/dev/null | awk -F, 'NR>1')" ]; then
		log "Creating snapper snapshot"
		local cfg
		for cfg in $(snapper --csvout list-configs | awk -F, 'NR>1 {print $1}'); do
			snapper -c "$cfg" create -c number -d "before galaxybook4-speaker-fix" || return 1
		done
		return 0
	elif command -v timeshift >/dev/null; then
		log "Creating Timeshift snapshot"
		timeshift --create --comments "before galaxybook4-speaker-fix" --tags O && return 0
	fi

	warn "No snapshot tool worked (omarchy-snapshot, snapper or timeshift)."
	read -rp "   Continue without a snapshot? [y/N] " reply
	[[ "$reply" =~ ^[Yy] ]] || die "Aborted. Re-run with --no-snapshot to skip this check."
}

installed_versions() {
	dkms status "$DKMS_NAME" 2>/dev/null | sed -n "s|^${DKMS_NAME}/\([^,:]*\).*|\1|p" | sort -u
}

# Build the new version before removing any old one, so a failed build
# leaves the currently working driver in place.
install_driver() {
	local src="/usr/src/${DKMS_NAME}-${DKMS_VER}" ver

	log "Building ${DKMS_NAME}/${DKMS_VER} for $KVER"
	dkms remove "${DKMS_NAME}/${DKMS_VER}" --all &>/dev/null || true
	rm -rf "$src"
	mkdir -p "$src/src"
	cp -a "$REPO/driver/dkms.conf" "$src/"
	cp -a "$REPO/driver/src/"*.{c,h} "$REPO/driver/src/Makefile" "$src/src/"

	dkms add "${DKMS_NAME}/${DKMS_VER}"
	if ! dkms build "${DKMS_NAME}/${DKMS_VER}" -k "$KVER"; then
		dkms remove "${DKMS_NAME}/${DKMS_VER}" --all &>/dev/null || true
		rm -rf "$src"
		die "Build failed; any previously installed driver was left untouched."
	fi

	for ver in $(installed_versions); do
		[ "$ver" = "$DKMS_VER" ] && continue
		log "Removing old ${DKMS_NAME}/${ver}"
		dkms remove "${DKMS_NAME}/${ver}" --all || true
		rm -rf "/usr/src/${DKMS_NAME}-${ver}"
	done

	dkms install "${DKMS_NAME}/${DKMS_VER}" -k "$KVER" --force
}

install_system_files() {
	log "Installing services and module autoload"
	install -m 755 "$REPO/system/max98390-hda-i2c-setup.sh"      /usr/local/sbin/
	install -m 755 "$REPO/system/max98390-hda-check-upstream.sh" /usr/local/sbin/
	install -m 644 "$REPO/system/max98390-hda-i2c-setup.service"      /etc/systemd/system/
	install -m 644 "$REPO/system/max98390-hda-check-upstream.service" /etc/systemd/system/
	install -m 644 "$REPO/system/max98390-hda.conf" /etc/modules-load.d/
	systemctl daemon-reload
	systemctl enable max98390-hda-i2c-setup.service max98390-hda-check-upstream.service
}

# Swap in the new modules without a reboot. The extra amps created by the
# setup service stay registered and rebind to the reloaded driver.
reload_driver() {
	log "Loading driver"
	modprobe -r snd_hda_scodec_max98390_i2c snd_hda_scodec_max98390 2>/dev/null || true
	if ! modprobe snd_hda_scodec_max98390_i2c; then
		warn "Module failed to load now (Secure Boot enrollment pending?). Reboot to finish."
		return 0
	fi
	systemctl restart max98390-hda-i2c-setup.service
}

remove_all() {
	local ver
	systemctl stop max98390-hda-i2c-setup.service 2>/dev/null || true
	systemctl disable max98390-hda-i2c-setup.service max98390-hda-check-upstream.service 2>/dev/null || true
	modprobe -r snd_hda_scodec_max98390_i2c snd_hda_scodec_max98390 2>/dev/null || true
	for ver in $(installed_versions); do
		log "Removing ${DKMS_NAME}/${ver}"
		dkms remove "${DKMS_NAME}/${ver}" --all || true
		rm -rf "/usr/src/${DKMS_NAME}-${ver}"
	done
	rm -f /etc/systemd/system/max98390-hda-i2c-setup.service \
	      /etc/systemd/system/max98390-hda-check-upstream.service \
	      /etc/modules-load.d/max98390-hda.conf \
	      /usr/local/sbin/max98390-hda-i2c-setup.sh \
	      /usr/local/sbin/max98390-hda-check-upstream.sh
	systemctl daemon-reload
}
