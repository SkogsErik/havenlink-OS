# HavenLink OS - Project Structure

```
havenlink-OS/
├── docs/
│   ├── ARCHITECTURE.md          # System architecture and boot sequence
│   ├── THREAT_MODEL.md          # Threat model and security analysis
│   └── PROJECT_STRUCTURE.md     # This file
│
├── scripts/
│   ├── build-image.sh           # Main build script — creates bootable disk image
│   ├── setup-device.sh          # First-time device setup helper
│   └── havenlink-wipe.sh        # Emergency wipe script
│
├── config/
│   ├── apk-repositories         # Alpine package sources (edge + community)
│   ├── sysctl.conf              # Kernel hardening parameters
│   ├── firewall.nft             # nftables ruleset (default deny)
│   ├── torrc                    # Tor client configuration
│   ├── havenlink.conf           # Default HavenLink app config
│   ├── hostapd.conf             # WiFi AP configuration
│   ├── dnsmasq.conf             # DHCP server for WiFi clients
│   ├── network.conf             # Network settings
│   └── network/
│       └── interfaces           # /etc/network/interfaces
│
├── overlay/                     # Files copied verbatim into the image root
│   └── etc/
│       └── init.d/              # (currently empty — no custom services)
│
├── AGENT_GUIDE.md               # Notes for AI coding agents
├── Makefile                     # Build orchestration
├── README.md
└── VERSION
```

## Build vs Runtime

```
BUILD-TIME (internet required):
  - Downloads Alpine 3.20 mini rootfs
  - Installs packages via apk (tor, nftables, python3, py3-cbor2, …)
  - Clones HavenLink app from github.com/SkogsErik/havenlink
  - Copies config/ and overlay/ into rootfs
  - Creates runlevel symlinks directly (no rc-update, fails in chroot)
  - Installs syslinux, writes MBR
  - Output: havenlink-os-<version>-<arch>.img  (raw disk image)

RUNTIME (air-gapped capable):
  - Read-only root filesystem (ext4, ro,noatime)
  - Mutable state in tmpfs only (lost on reboot)
  - Autostarted services: nftables, tor
  - havenlink available as CLI tool: run manually after login
  - No apk, no SSH, no remote administration
```

## Key Files

| File | Purpose |
|------|---------|
| `scripts/build-image.sh` | Full build pipeline — Alpine rootfs → bootable image |
| `config/torrc` | Tor config: client-only, User tor, syslog, no relay |
| `config/firewall.nft` | nftables: default deny, allow mesh 9001-9010 + Tor |
| `config/sysctl.conf` | Kernel hardening: ASLR, no redirects, no core dumps |
| `config/havenlink.conf` | App defaults: Tor enabled, bind 127.0.0.1, no auto-accept |

## What's NOT in this repo

The HavenLink chat application lives in the main repo:
- https://github.com/SkogsErik/havenlink

It is cloned at build time into `/opt/havenlink/` and symlinked to `/usr/local/bin/havenlink`.

## Python Dependencies

Installed via `apk` at build time (not pip — avoids ABI/wheel issues with musl):

| APK package | Python module | Used for |
|-------------|---------------|---------|
| py3-cbor2 | cbor2 | Message serialization |
| py3-pynacl | nacl | NaCl crypto |
| py3-pysocks | socks | SOCKS5 / Tor proxy |
