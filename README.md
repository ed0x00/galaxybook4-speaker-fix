# Galaxy Book4 speaker fix for Linux

Makes the internal speakers work on Samsung Galaxy Book4 laptops whose speakers sit behind
**Maxim MAX98390** smart amplifiers, and powers those amplifiers **off whenever nothing is
playing** so they don't drain the battery.

Targets the Galaxy Book4 Pro (14" and 16"), Book4 Pro 360, Book4 Ultra and Book5 Pro, the
models on which the upstream driver this builds on is reported working. Use the check below
to confirm your laptop has the same hardware.

## The problem

Everything looks fine: PipeWire shows a *Speaker* output, volume is up, nothing is muted,
yet no sound comes out. Headphones work.

The audio goes Realtek ALC298 codec → I2S → four MAX98390 amps (2 woofers, 2 tweeters)
controlled over I2C. The stock kernel is missing three things:

1. a driver for MAX98390 as an HDA side codec, so the amps are never initialised;
2. `serial-multi-instantiate` support for the `MAX98390` ACPI device, so only the first of the
   four amps is even created;
3. an `snd_hda_codec_alc269` quirk for these boards.

Forcing an ALC298 Samsung model (`hda_model=alc298-samsung-amp-v2-*`) does **not** help: those
fixups drive a different amp design that sits inside the codec.

### Does this apply to my laptop?

```bash
grep -E "Codec|Subsystem" /proc/asound/card*/codec#0   # Realtek ALC298, 0x144d....
ls /sys/bus/i2c/devices/ | grep MAX98390                # i2c-MAX98390:00
```

If both match, this fix is for you. The Galaxy Book3 Pro 14" (940XFG) has no MAX98390 and
needs a different fix.

## Install

```bash
git clone https://github.com/ed0x00/galaxybook4-speaker-fix.git
cd galaxybook4-speaker-fix
sudo ./install.sh
./tools/verify.sh
```

No reboot is needed unless the installer asks for Secure Boot key enrollment. The installer:

1. checks for MAX98390 hardware;
2. **takes a system snapshot** with `omarchy-snapshot` (Limine boot-menu entry), snapper or
   Timeshift, whichever is available, before changing anything;
3. installs dependencies for your distro (see below);
4. builds the driver with DKMS (rebuilt automatically on kernel updates). If the build fails,
   any driver you already had is left untouched;
5. installs a boot service that creates the three amps ACPI doesn't enumerate, and loads
   everything immediately.

Options: `--distro arch|debian` (force a family for derivatives that aren't detected),
`--no-snapshot`, `--force` (skip the hardware check).

Requires **Linux 6.13 or newer**. Debian 13's stock 6.12 kernel is too old; use the
backports kernel.

### Distro differences

Only these steps differ; everything else is shared.

| | Arch family (`distro/arch`) | Debian family (`distro/debian`) |
|---|---|---|
| Covers | Arch, Omarchy, CachyOS, EndeavourOS, Manjaro | Debian, Ubuntu, Mint, Pop!_OS, Zorin |
| Packages | `dkms i2c-tools <kernel>-headers` (+`sof-firmware`) | `dkms i2c-tools linux-headers-$(uname -r)` (+`firmware-sof-signed`) |
| Headers | detected from the package that owns the running kernel | exact version for the running kernel |
| Secure Boot | usually off; warns if lockdown would reject unsigned modules | modules signed by dkms; offers MOK enrollment if the key isn't enrolled |

On Debian/Ubuntu with Secure Boot on, the installer runs `mokutil --import`. Reboot, and in the
blue MOK Manager screen choose *Enroll MOK → Continue → Yes*, then enter the password you set.

## Power management

The upstream driver enables the amps at load time and leaves them on, because its playback
hook only fires with the missing codec quirk. This fork makes each amp a **runtime-PM
supplier of the ALC298 codec** (a kernel device link):

- the codec already runtime-suspends about 1 s after playback stops; the amps now suspend
  with it (`GLOBAL_EN=0`, `AMP_EN=0x80`);
- when playback starts, the PM core resumes the amps **before** the codec, so the start of a
  sound isn't cut off;
- system suspend/resume keeps that state;
- no polling and no userspace daemon. If the codec can't be found within 60 s of probe, the
  amps simply stay on, as in the upstream driver.

The change is in [`patches/0001-runtime-pm-amps-follow-alc298-codec.patch`](patches/0001-runtime-pm-amps-follow-alc298-codec.patch).

Amps power off a few seconds after a sound ends, because PipeWire keeps the device open
for its suspend timeout before closing it.

### Check it

```bash
./tools/verify.sh
```

```
  idle               amps: suspended suspended suspended suspended | codec: suspended
  playing            amps: active active active active | codec: active
  idle again         amps: suspended suspended suspended suspended | codec: suspended
OK: amps follow playback.
```

## Uninstall / roll back

```bash
sudo ./uninstall.sh && sudo reboot
```

If anything goes badly wrong, boot the snapshot taken before install: pick it from the Limine
menu on Omarchy, or use `omarchy-snapshot restore`, `snapper rollback` or Timeshift.

When native support lands in your kernel, `max98390-hda-check-upstream.service` detects it at
boot and removes this package by itself.

## Layout

```
install.sh, uninstall.sh   entry points (detect distro, run shared steps)
lib/common.sh              shared logic: snapshot, DKMS build/install, services
distro/arch/distro.sh      Arch family: packages, headers, Secure Boot notes
distro/debian/distro.sh    Debian family: packages, headers, MOK signing
driver/                    DKMS package (dkms.conf + source)
system/                    systemd units, amp setup and upstream-check scripts
tools/verify.sh            checks amp power state idle / playing / idle
patches/                   the runtime-PM change as a diff against upstream
```

## Known limitations

- The built-in microphone on Book4 (Meteor Lake) models is a separate issue and is not fixed
  here.
- The driver can use per-amp tuning tables extracted from the Windows driver
  (`max98390-galaxybook.bin`). They aren't shipped here, so it falls back to its built-in
  speaker-protection tuning.

## Credits and license

- MAX98390 HDA driver: Kevin Cuperus, [thesofproject/linux PR #5616](https://github.com/thesofproject/linux/pull/5616)
- DKMS packaging, amp setup and upstream-check scripts:
  [Andycodeman/samsung-galaxy-book-linux-fixes](https://github.com/Andycodeman/samsung-galaxy-book-linux-fixes)
- Runtime power management, shared Arch/Debian installer, verify tool: this repository
- Kernel bug: [bugzilla #218862](https://bugzilla.kernel.org/show_bug.cgi?id=218862)

GPL-2.0, see [LICENSE](LICENSE).
