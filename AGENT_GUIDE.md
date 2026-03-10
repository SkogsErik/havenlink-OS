# HavenLink-OS - AI Agent Guide

## Project Overview

HavenLink-OS is a hardened operating system for secure peer-to-peer mesh communication. Built on Alpine Linux 3.20, designed for air-gapped/offline operation with Tor always running in the background and HavenLink available as an interactive CLI tool.

**GitHub:** https://github.com/SkogsErik/havenlink-OS
**Related Repo:** https://github.com/SkogsErik/havenlink (chat application source)

---

## Current State (as of 2026-03-10)

### Boot Status: WORKING ✅

The `.img` image boots cleanly in QEMU and on physical hardware:
- OpenRC runs all four runlevels (sysinit, boot, default, shutdown)
- nftables firewall starts ✅
- Tor starts ✅ (runs as `tor` user, data in tmpfs)
- `havenlink` command is available immediately after login ✅
- Networking / DHCP works ✅
- seedrng works ✅

### Live CD ISO Status: BUILT ✅ (boot not yet verified)

A hybrid Live CD/USB ISO is now buildable via `--format iso` (x86_64 only).

```bash
sudo make iso ARCH=x86_64
# or directly:
sudo scripts/build-image.sh --arch x86_64 --format iso
```

Output: `havenlink-os-0.1.0-x86_64.iso` (~812 MB)

**ISO boot stack:** isolinux (BIOS) → custom cpio initramfs → modprobe loop/squashfs/overlay → mount `rootfs.sqfs` from media → overlayfs (tmpfs upper) → `switch_root /new_root /sbin/init`

The iso was built successfully and ISOLINUX loaded. Full end-to-end QEMU boot verification is pending (was in progress at last session, QEMU serial output capture had TTY issues in the agent environment — test directly with):

```bash
sudo qemu-system-x86_64 -m 1024 -enable-kvm \
  -cdrom havenlink-os-0.1.0-x86_64.iso \
  -nographic -serial mon:stdio -boot d -no-reboot
```

### Completed Issues

| Issue | Title | Status |
|-------|-------|--------|
| #1 | Project structure | ✅ Done |
| #2 | OS hardening (configs) | ✅ Done |
| #3 | Build system | ✅ Done |
| #9 | Threat model | ✅ Done |
| #10 | WiFi Access Point | ✅ Done |
| #11 | WiFi client isolation | ✅ Done |
| #12 | WiFi password on setup | ✅ Done |
| #22 | WiFi AP PSK from USB key (runtime HKDF) | ✅ Done (890d124) |
| #24 | havenlink-tools device management CLI | ✅ Done (c6e76dd) |
| #13 | WiFi access logging | ❌ Pending (low priority) |
| —   | Fix boot / OpenRC / all services | ✅ Done (2026-03-10) |
| —   | `--format iso` Live CD support | ✅ Built, boot verification pending |

---

## Repository Layout

```
havenlink-OS/
├── docs/
│   ├── ARCHITECTURE.md          # System design, boot sequence, service table
│   ├── THREAT_MODEL.md          # Security analysis (v0.2)
│   └── PROJECT_STRUCTURE.md     # File layout and key files
│
├── scripts/
│   ├── build-image.sh           # Main build script (Alpine-based)
│   ├── setup-device.sh          # First-time device setup
│   └── havenlink-wipe.sh        # Emergency wipe
│
├── config/
│   ├── apk-repositories         # Alpine edge + community
│   ├── sysctl.conf              # Kernel hardening
│   ├── firewall.nft             # nftables (default deny)
│   ├── torrc                    # Tor client-only, User tor, syslog
│   ├── havenlink.conf           # Default app config
│   ├── hostapd.conf             # WiFi AP
│   ├── dnsmasq.conf             # DHCP for WiFi clients
│   ├── network.conf             # Network settings
│   └── network/interfaces       # Network interfaces
│
├── overlay/                     # Copied verbatim into image root
│   └── etc/
│       └── init.d/              # No custom services (havenlink is a CLI tool)
│
├── AGENT_GUIDE.md               # This file
├── Makefile
├── README.md
└── VERSION
```

---

## How to Build

```bash
git clone https://github.com/SkogsErik/havenlink-OS.git
cd havenlink-OS

# Build x86_64 raw disk image (for QEMU/VM/laptop)
sudo make image ARCH=x86_64

# Build aarch64 image (for Raspberry Pi)
sudo make image ARCH=aarch64

# Build x86_64 Live CD ISO (boots from CD or USB, x86_64 only)
sudo make iso ARCH=x86_64
# or:
sudo scripts/build-image.sh --arch x86_64 --format iso
```

Output: `havenlink-os-<version>-<arch>.img` or `.iso` (ignored by .gitignore)

## How to Test in QEMU

```bash
sudo qemu-system-x86_64 \
  -m 512 -enable-kvm \
  -drive file=havenlink-os-0.1.0-x86_64.img,format=raw,if=ide \
  -nographic -serial mon:stdio
```

Login: `root` / `havenlink`

After login:
```bash
rc-status                          # check service state
havenlink --name test --tor        # launch chat client via Tor
havenlink --name test --internet   # launch chat client via direct internet
```

---

## Critical Build Script Facts

These are hard-won fixes — do not revert them:

### 1. Runlevel symlinks — do NOT use rc-update
`rc-update` fails silently in a cross-arch chroot. Always create symlinks directly:
```bash
ln -sf /etc/init.d/tor "${ROOTFS}/etc/runlevels/default/tor"
```

### 2. /run/openrc must exist before OpenRC runs
The initramfs mounts tmpfs on `/run` but doesn't create `/run/openrc/`. Add to `/etc/inittab` before the openrc sysinit line:
```
::sysinit:/bin/mkdir -p /run/openrc
```

### 3. Do NOT mount tmpfs on /var/run
`/var/run` is a symlink to `/run`. Mounting a second tmpfs there wipes the OpenRC state written to `/run/openrc/softlevel`.

### 4. Use numeric UIDs in fstab tmpfs entries
`uid=tor` does not work in fstab before `/etc/passwd` is available. Look up the UID from the built rootfs:
```bash
tor_uid=$(grep '^tor:' rootfs/etc/passwd | cut -d: -f3)
echo "tmpfs /var/lib/tor tmpfs uid=${tor_uid},..." >> rootfs/etc/fstab
```

### 5. Python packages via apk, not pip
Alpine uses musl libc. PyPI wheels are built for glibc and will fail to import. Install via:
```bash
apk add py3-cbor2 py3-pynacl py3-pysocks
```

### 6. havenlink is a CLI tool, not a daemon
Do NOT add havenlink to any runlevel. It requires an interactive terminal. The binary is at `/opt/havenlink/cli.py` (executable, `chmod +x`) with a symlink at `/usr/local/bin/havenlink`.

### 7. Alpine's busybox is dynamically linked against musl (ISO builds)
Despite common belief, Alpine's busybox package (`/bin/busybox`) is a PIE executable dynamically linked against `libc.musl-x86_64.so.1`. When building the initramfs for `--format iso`, you must copy the musl dynamic linker into the initramfs or the kernel will panic with "No working init found":
```bash
cp rootfs/lib/ld-musl-x86_64.so.1 initrd/lib/
ln -sf ld-musl-x86_64.so.1 initrd/lib/libc.musl-x86_64.so.1
```

### 8. Alpine kernel version: vmlinuz suffix ≠ module directory name (ISO builds)
`/boot/vmlinuz-lts` is a symlink — the suffix `lts` does NOT match the module directory under `/lib/modules/` (which is the full uname, e.g. `6.6.129-0-lts`). Detect them separately:
```bash
kver_short=$(ls rootfs/boot/vmlinuz-* | sed 's|.*/vmlinuz-||' | head -1)  # "lts"
kver=$(ls rootfs/lib/modules/ | head -1)                                   # "6.6.129-0-lts"
cp rootfs/boot/vmlinuz-${kver_short} iso/boot/vmlinuz   # short name for vmlinuz
# use full kver for all module paths
```

### 9. resolv.conf is a symlink in Alpine minirootfs
Alpine's minirootfs ships `/etc/resolv.conf` as a symlink to `/run/resolv.conf`. When setting up the build chroot, do `rm -f` before `cp` or the copy will fail:
```bash
rm -f "${WORK_DIR}/rootfs/etc/resolv.conf"
cp /etc/resolv.conf "${WORK_DIR}/rootfs/etc/resolv.conf"
```

### 10. hostapd passphrase is now runtime-generated (not hardcoded)
`config/hostapd.conf` uses `wpa_passphrase_file=/run/hostapd.psk`. The PSK is derived at boot by `havenlink-tools generate-psk` (HKDF-SHA256 from a USB key's `wifi-salt` file). Do not hardcode a passphrase.

---

## Configuration Files Reference

| File | Purpose |
|------|---------|
| `/etc/havenlink/havenlink.conf` | App defaults (Tor ports, bind address) |
| `/etc/tor/torrc` | Tor: client-only, User tor, syslog, ExitPolicy reject |
| `/etc/nftables.conf` | Firewall: default deny, allow 9001-9010 + loopback Tor |
| `/etc/sysctl.d/99-havenlink.conf` | Kernel hardening |
| `/etc/modprobe.d/havenlink-blacklist.conf` | Unused fs/protocol blacklist |
| `/etc/udhcpc/udhcpc.conf` | RESOLV_CONF=/run/resolv.conf (ro root workaround) |

---

## Pending Work

- **Issue #13**: WiFi access logging (low priority)
- **Verify ISO live boot**: Run `havenlink-os-0.1.0-x86_64.iso` end-to-end in QEMU after reboot (serial console shows ISOLINUX loading, full OS boot not yet confirmed)
- **CI/CD**: GitHub Actions to build and publish images automatically

---

## Key Design Decisions

1. **havenlink is not a service** — it's a P2P chat client that runs interactively
2. **No remote admin** — console-only, no SSH
3. **Read-only root** — all mutable state in tmpfs (lost on reboot is intentional)
4. **Tor always running** — daemon autostarted, havenlink uses `--tor` flag to route through it
5. **apk over pip** — musl ABI requires Alpine packages, not PyPI wheels
6. **Update threat model** — any new feature should get a corresponding entry in THREAT_MODEL.md
7. **USB key auth** — WiFi PSK is HKDF-derived from `wifi-salt` on a USB key, managed by `havenlink-tools`
