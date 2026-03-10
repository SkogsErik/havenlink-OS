# HavenLink OS

Hardened operating system for secure peer-to-peer mesh communication.

## Overview

HavenLink OS is a purpose-built, minimal Linux distribution based on Alpine Linux. Designed for high-risk users who need secure, air-gapped communication without relying on internet connectivity.

## Key Features

- **Minimal Attack Surface**: No remote admin, console-only management
- **Air-Gap Ready**: Runs without internet connectivity
- **Hardened Security**: Kernel lockdown, firewall, no unnecessary services
- **USB Key Identity**: Encrypted identity storage on removable USB
- **Tor Integration**: Optional outbound connectivity via Tor onion services

## Architecture

```
┌─────────────────────────────────────┐
│     HavenLink OS (Alpine Linux)     │
├─────────────────────────────────────┤
│  Kernel + OpenRC                    │
│  + Tor (client only)                │
│  + HavenLink Chat App               │
│  + Hardened configs                 │
├─────────────────────────────────────┤
│  Security:                          │
│  - Read-only root (optional)        │
│  - No SSH/web admin                 │
│  - Firewall (nftables)              │
│  - USB key identity                 │
└─────────────────────────────────────┘
```

## Quick Start

### Build the Image

```bash
# Clone this repo
git clone https://github.com/SkogsErik/havenlink-OS.git
cd havenlink-OS

# Build for Raspberry Pi (aarch64)
make image

# Or specify architecture
make image ARCH=x86_64
```

### Write to SD Card/USB

```bash
# Write the image
dd if=havenlink-os-0.1.0-aarch64.img.gz of=/dev/sdX bs=4M
gunzip -c havenlink-os-0.1.0-aarch64.img.gz | dd of=/dev/sdX bs=4M
```

### First Boot Setup

1. Connect console (serial or keyboard/display)
2. Power on device
3. Run setup: `/usr/local/bin/havenlink-setup`
4. Generate or import identity

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System design
- [Threat Model](docs/THREAT_MODEL.md) - Security analysis
- [Project Structure](docs/PROJECT_STRUCTURE.md) - File layout

## Requirements

- Raspberry Pi 3/4 or legacy laptop/VM
- 8GB+ storage
- Console access (serial or keyboard/display)
- USB drive (for identity storage - recommended)

## Security

See [THREAT_MODEL.md](docs/THREAT_MODEL.md) for security details.

### What's Disabled

- SSH server
- HTTP/HTTPS admin
- Any remote administration
- Unnecessary network services

### What's Enabled

- Tor (client only, outbound)
- HavenLink mesh ports (9001-9010)
- Console management only

## Repository Structure

```
havenlink-OS/
├── docs/           # Documentation
├── scripts/       # Build and setup scripts
├── config/        # Configuration files
├── overlay/       # Files copied to image
├── Makefile       # Build orchestration
└── VERSION        # Version file
```

## Related Repositories

- **HavenLink** (main): https://github.com/SkogsErik/havenlink
  - Chat application source code
  
- **HavenLink OS** (this): https://github.com/SkogsErik/havenlink-OS
  - Hardened OS build system

## License

TBD
