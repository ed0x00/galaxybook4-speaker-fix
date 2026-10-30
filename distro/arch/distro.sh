# Arch-based distros: Arch, Omarchy, CachyOS, EndeavourOS, Manjaro.

distro_deps() {
	local pkgs=(dkms i2c-tools) kpkg

	# Headers must match the running kernel's package (linux, linux-lts,
	# linux-zen, linux-omarchy, ...), so ask pacman who owns it.
	kpkg="$(pacman -Qqo "/usr/lib/modules/$KVER/vmlinuz" 2>/dev/null || true)"
	if [ -n "$kpkg" ]; then
		pkgs+=("${kpkg}-headers")
	elif [ ! -d "/lib/modules/$KVER/build" ]; then
		die "Can't tell which package provides kernel $KVER; install its -headers package manually."
	fi

	sof_firmware_present || pkgs+=(sof-firmware)

	log "Installing packages: ${pkgs[*]}"
	pacman -S --needed --noconfirm "${pkgs[@]}"
}

# Arch kernels don't enforce module signatures by default, even with Secure
# Boot on, unless you sign them yourself (e.g. sbctl + a lockdown setup).
distro_sign() {
	secure_boot_enabled || return 0
	if [ ! -e /sys/kernel/security/lockdown ] || grep -q '\[none\]' /sys/kernel/security/lockdown; then
		return 0
	fi
	warn "Secure Boot with kernel lockdown is active: unsigned DKMS modules may be rejected."
	warn "Sign them with your own key, or disable Secure Boot in the BIOS."
}
