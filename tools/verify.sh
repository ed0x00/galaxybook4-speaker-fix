#!/bin/bash
# Check that the speaker amps power on for playback and off when idle.
# Run as your normal user (needs PipeWire/ALSA access, not root).

AMPS=(/sys/bus/i2c/drivers/max98390-hda/*-*)
CODEC=$(grep -l 0x10ec0298 /sys/bus/hdaudio/devices/*/vendor_id 2>/dev/null | head -1 | xargs -r dirname)
FAIL=0

states() {
	local d out=""
	for d in "${AMPS[@]}"; do
		[ -e "$d" ] && out+="$(cat "$d/power/runtime_status") "
	done
	echo "${out% }"
}

show() {
	printf '  %-18s amps: %s | codec: %s\n' "$1" "$(states)" \
		"$(cat "$CODEC/power/runtime_status" 2>/dev/null || echo '?')"
}

expect() {
	local want="$1" s
	for s in $(states); do
		[ "$s" = "$want" ] || { echo "  FAIL: expected all amps '$want'"; FAIL=1; return; }
	done
}

wait_for() {
	local want="$1" i
	for i in $(seq 1 15); do
		[ "$(states | tr ' ' '\n' | sort -u)" = "$want" ] && return 0
		sleep 1
	done
}

lsmod | grep -q snd_hda_scodec_max98390 || { echo "Driver not loaded."; exit 1; }
[ -n "$CODEC" ] || { echo "ALC298 codec not found."; exit 1; }
echo "Amps found: $(states | wc -w)"
journalctl -k -b --no-pager 2>/dev/null | grep -E "max98390.*(follows|stays powered)" |
	awk '{ last[$7] = $0 } END { for (d in last) print "  " last[d] }' | sort -k7

echo "Idle (waiting for audio to go quiet):"
wait_for suspended
show "idle"; expect suspended

echo "Playing a 440 Hz test tone, left then right:"
speaker-test -c2 -t sine -f 440 -l1 >/dev/null 2>&1 &
sleep 1.5
show "playing"; expect active
wait

echo "After playback:"
wait_for suspended
show "idle again"; expect suspended

[ $FAIL -eq 0 ] && echo "OK: amps follow playback." || echo "Problems found (see above)."
exit $FAIL
