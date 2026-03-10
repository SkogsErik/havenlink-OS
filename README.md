# HavenLink OS

Hardened operating system for secure peer-to-peer mesh communication.

## Overview

HavenLink OS is a purpose-built, minimal Linux distribution designed for secure peer-to-peer mesh communication. Built on Alpine Linux with security-first principles.

## Key Features

- **Minimal Attack Surface**: No remote admin, console-only management
- **Hardened Security**: Read-only root, no swap, memory sanitization
- **USB Key Identity**: Encrypted identity storage on removable USB
- **Air-Gap Ready**: No internet required for core mesh functionality
- **Tor Integration**: Optional outbound connectivity via Tor
- **Modular Transport**: Ready for LoRa/radio mesh integration

## Design Principles

1. **Minimal**: Absolute minimum packages (~100MB base)
2. **Secure**: No remote administration, physical access only
3. **Isolated**: RAM-only message storage, encrypted storage
4. **Hardened**: Kernel lockdown, no unnecessary services

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - System architecture and design
- [Security](docs/SECURITY.md) - Security model and hardening details
- [Installation](docs/INSTALLATION.md) - Build and deployment guide
- [Operation](docs/OPERATION.md) - Operational procedures

## Quick Start

```bash
# Build the image (requires internet)
make image

# Write to SD card/USB
dd if=havenlink-os.img of=/dev/sdX bs=4M

# First boot: connect console, run:
havenlink-setup
```

## Requirements

- Raspberry Pi 3/4 or legacy laptop/VM
- 8GB+ storage
- Console access (serial or keyboard/display)
- USB drive (for identity storage)

## Security

See [SECURITY.md](docs/SECURITY.md) for detailed security model.

## License

TBD
