# Debian-based distros: Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin OS.

distro_deps() {
	local pkgs=(dkms i2c-tools "linux-headers-$KVER")

	# Debian ships SOF in firmware-sof-signed (non-free-firmware);
	# Ubuntu and derivatives ship it inside linux-firmware.
	sof_firmware_present || pkgs+=(firmware-sof-signed)
	secure_boot_enabled && pkgs+=(mokutil openssl)

	log "Installing packages: ${pkgs[*]}"
	apt-get update -qq
	apt-get install -y "${pkgs[@]}"
}

# Secure Boot is usually on for these distros, and the kernel then rejects
# unsigned modules. dkms signs with /var/lib/dkms/mok.key (Debian, dkms 3+)
# or the shim-signed MOK (Ubuntu); the key must also be enrolled in firmware.
distro_sign() {
	secure_boot_enabled || return 0

	local mod cert
	mod="$(installed_module)"
	if [ -z "$mod" ] || [ -z "$(modinfo -F signer "$mod" 2>/dev/null)" ]; then
		warn "Secure Boot is on but the module is not signed; it will be rejected at load."
		warn "Set mok_signing_key/mok_certificate in /etc/dkms/framework.conf, then re-run."
		return 0
	fi

	for cert in /var/lib/dkms/mok.pub /var/lib/shim-signed/mok/MOK.der; do
		[ -f "$cert" ] || continue
		if mokutil --test-key "$cert" 2>/dev/null | grep -q "already enrolled"; then
			log "Module signed with an enrolled key ($cert)"
			return 0
		fi
		warn "Signing key $cert is not enrolled in firmware yet."
		echo "   Choose a one-time password now; on the next boot the blue MOK Manager"
		echo "   screen asks for it: Enroll MOK -> Continue -> Yes -> password -> Reboot."
		mokutil --import "$cert" && NEEDS_REBOOT=true
		return 0
	done

	warn "Module is signed, but no known MOK certificate was found to check enrollment."
}
