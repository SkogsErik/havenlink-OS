# HavenLink OS - Project Structure

```
havenlink-OS/
├── docs/
│   ├── ARCHITECTURE.md          # System architecture
│   ├── THREAT_MODEL.md          # Threat model
│   ├── SECURITY.md              # Security measures
│   ├── PROJECT_STRUCTURE.md     # This file
│   └── OPERATION.md            # Operational procedures
│
├── scripts/
│   ├── build-image.sh           # Build ISO/IMG (main build script)
│   └── Makefile                # Build orchestration
│
├── config/
│   ├── apk-repositories        # Alpine package sources
│   ├── sysctl.conf            # Kernel hardening (sysctl)
│   ├── firewall.nft           # nftables rules
│   ├── torrc                  # Tor configuration
│   ├── havenlink.conf         # Default HavenLink config
│   └── services.list          # Services to enable/disable
│
├── overlay/
│   └── etc/
│       └── init.d/
│           └── havenlink       # OpenRC service script
│
├── Makefile
├── README.md
└── VERSION
```

## Build vs Runtime

```
BUILD-TIME (with internet):
  - Downloads Alpine mini rootfs
  - Installs packages (apk)
  - Copies HavenLink app from main repo
  - Applies hardening configs
  - Output: havenlink-os-x.x.x.img.gz

RUNTIME (air-gapped):
  - Read-only root filesystem
  - No package manager
  - Only: kernel, OpenRC, Tor, HavenLink
  - No SSH, no remote admin
```

## Key Components

| Component | Purpose |
|-----------|---------|
| `build-image.sh` | Main build script - creates bootable image |
| `Makefile` | Simple build orchestration |
| `config/` | All configuration files |
| `overlay/` | Files copied to image root |

## What's NOT in this repo

The HavenLink chat application is in the main repo:
- https://github.com/SkogsErik/havenlink

This repo is for the **hardened OS** that runs HavenLink.
