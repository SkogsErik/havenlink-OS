# HavenLink OS - Architecture

## Executive Summary

HavenLink OS is a purpose-built, hardened operating system for secure peer-to-peer communication. It boots into a read-only Alpine Linux environment with Tor running automatically. The user runs the HavenLink CLI tool interactively from the console — there is no background app daemon, no remote administration, and no mutable root filesystem.

**Key Design Principles:**
- **Minimal**: Only what is needed — kernel, OpenRC, Tor, nftables, HavenLink tool
- **Secure**: No remote admin, console-only, read-only root
- **Isolated**: All mutable state lives in tmpfs (lost on reboot)
- **Transparent**: No hidden services; everything that runs is explicit

---

## 1. OS Base

### 1.1 Selection: Alpine Linux 3.20

| Aspect | Alpine | Debian Minimal |
|--------|--------|----------------|
| Base size | ~100MB | ~400MB |
| C library | musl | glibc |
| Init system | OpenRC | systemd |
| Package manager | apk | apt |

**Why Alpine:**
- musl is smaller and more memory-safe than glibc
- APK is simpler to audit
- OpenRC is straightforward and well-understood
- Established in containers/embedded security use cases

### 1.2 Runtime vs Build-Time

```
BUILD-TIME (Internet required)         RUNTIME (Air-gapped capable)
────────────────────────────           ────────────────────────────
- Alpine mini rootfs downloaded        - Read-only root filesystem
- Packages installed via apk           - No package manager
- HavenLink cloned from GitHub         - No SSH, no remote admin
- Hardening configs applied            - Services: Tor + nftables only
- Output: raw disk image               - havenlink run manually by user
```

---

## 2. Boot Sequence

```
BIOS/EFI
  └── syslinux/extlinux (MBR)
        └── Linux kernel + initramfs
              └── BusyBox init (/etc/inittab)
                    ├── mkdir /run/openrc      ← required before OpenRC
                    ├── openrc sysinit         ← devfs, mdev, hwdrivers
                    ├── openrc boot            ← localmount, networking, syslog, seedrng
                    ├── openrc default         ← nftables, tor
                    └── getty ttyS0            ← serial console login
```

**Key inittab entries:**
- `::sysinit:/bin/mkdir -p /run/openrc` — OpenRC requires this directory before it runs
- Serial getty enabled on `ttyS0` at 115200 baud

---

## 3. Filesystem Layout at Runtime

```
/           ext4, read-only (ro,noatime)
/tmp        tmpfs  — temporary files
/run        tmpfs  — OpenRC state, PID files, resolv.conf
/var/log    tmpfs  — service logs (lost on reboot)
/var/lib/seedrng  tmpfs  — kernel RNG seed persistence
/var/lib/tor      tmpfs  — Tor data dir (uid=tor, mode=0700)
```

**Consequences:**
- `/etc/resolv.conf` is a symlink to `/run/resolv.conf` (written by udhcpc)
- `/var/run` is a symlink to `/run`
- `/var/lock` is a symlink to `/run/lock`
- No persistent writable state outside of attached storage

---

## 4. Services

### 4.1 What Starts Automatically

| Service | Runlevel | Purpose |
|---------|----------|---------|
| devfs, mdev | sysinit | Device nodes |
| modules, sysctl | boot | Kernel config |
| localmount | boot | Mount fstab tmpfs entries |
| networking | boot | DHCP on eth0 |
| seedrng | boot | Kernel entropy seed |
| syslog | boot | BusyBox syslog |
| nftables | default | Firewall |
| tor | default | Tor client daemon |

### 4.2 What Does NOT Start Automatically

- **havenlink** — it is a CLI chat tool, not a daemon. Run it interactively:

```bash
havenlink --name yourname --tor
havenlink --name yourname --internet
havenlink --name yourname --lora
```

### 4.3 Tor Configuration

Tor runs as the `tor` system user. Key settings in `/etc/tor/torrc`:

- `SocksPort 127.0.0.1:9050` — SOCKS5 proxy for havenlink `--tor` mode
- `ControlPort 127.0.0.1:9051` — local control port
- `CookieAuthentication 1` — cookie-based control auth
- `User tor` — drops privileges automatically at startup
- `DataDirectory /var/lib/tor` — on tmpfs, uid=tor
- `ExitPolicy reject *:*` — client-only, no relaying

---

## 5. Security Architecture

### 5.1 Network Model

```
┌──────────────────────────────────────────┐
│             HavenLink Device              │
├──────────────────────────────────────────┤
│  eth0 (Ethernet, DHCP)                  │
│    │                                     │
│    ├── TCP 9001-9010  ◄── mesh peers    │
│    └── outbound only  ──► Tor (9050)    │
│                                          │
│  lo (Loopback)                          │
│    ├── 127.0.0.1:9050  Tor SOCKS       │
│    └── 127.0.0.1:9051  Tor Control     │
└──────────────────────────────────────────┘
```

All other inbound traffic is dropped by nftables.

### 5.2 Administration

**Only via:**
- Serial console (ttyS0, 115200 baud)
- Direct keyboard + display

**Disabled:**
- SSH server
- HTTP/HTTPS admin
- Any remote API or management interface

### 5.3 Kernel Hardening (sysctl)

Applied via `/etc/sysctl.d/99-havenlink.conf`:
- IP forwarding disabled
- Source routing disabled
- ICMP redirects disabled
- SYN cookies enabled
- Reverse path filtering enabled
- Magic SysRq disabled
- Core dumps disabled
- ASLR enabled (randomize_va_space=2)
- `/proc/sys/kernel/dmesg_restrict=1`

### 5.4 Module Blacklisting

`/etc/modprobe.d/havenlink-blacklist.conf` prevents loading of:
- Unused filesystems: cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf
- Unused protocols: dccp, sctp, rds, tipc

---

## 6. Python Dependencies

HavenLink requires Python 3 and the following packages, installed at build time via `apk`:

| Package | APK name | Purpose |
|---------|----------|---------|
| cbor2 | py3-cbor2 | Binary message serialization |
| pynacl | py3-pynacl | NaCl crypto (libsodium bindings) |
| pysocks | py3-pysocks | SOCKS5 proxy support for `--tor` mode |

---

## 7. Build System

`scripts/build-image.sh` performs:

1. Creates a raw disk image (ext4 + MBR)
2. Downloads Alpine Linux mini rootfs
3. Installs packages via `apk` in a chroot
4. Clones HavenLink from GitHub → `/opt/havenlink/`
5. Creates `/usr/local/bin/havenlink` symlink
6. Copies config files from `config/` and `overlay/`
7. Sets up runlevel symlinks directly (rc-update fails in cross-arch chroot)
8. Generates `/etc/fstab` with tmpfs entries using numeric UIDs
9. Installs syslinux bootloader

---

## Security Checklist

- [x] No remote admin (SSH disabled)
- [x] Console-only management
- [x] Read-only root filesystem
- [x] tmpfs for all mutable state
- [x] No swap
- [x] No crash dumps
- [x] Tor autostarted, client-only
- [x] nftables firewall (default deny)
- [x] Kernel hardening (sysctl)
- [x] Module blacklisting
- [x] Noise protocol encryption (in havenlink app)
- [x] No unnecessary services
