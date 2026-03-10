# HavenLink OS

Hardened operating system for secure peer-to-peer mesh communication.

## Overview

HavenLink OS is a purpose-built, minimal Linux distribution based on Alpine Linux. Designed for high-risk users who need secure, anonymous communication. The OS boots into a hardened, read-only environment with Tor running automatically — the user launches the HavenLink chat tool interactively from the console.

## Key Features

- **Minimal Attack Surface**: No SSH, no remote admin, console-only
- **Read-Only Root**: Filesystem is immutable at runtime; volatile data goes to tmpfs
- **Tor Always On**: Tor daemon starts automatically at boot as a background service
- **HavenLink Pre-installed**: `havenlink` command available immediately after login
- **Hardened Kernel**: sysctl hardening, module blacklisting, nftables firewall
- **Air-Gap Ready**: Can operate without internet via LoRa or local mesh

## Architecture

```
┌─────────────────────────────────────┐
│     HavenLink OS (Alpine Linux)     │
├─────────────────────────────────────┤
│  Kernel (Linux LTS) + OpenRC        │
│  + Tor (autostarted, client only)   │
│  + nftables firewall                │
│  + HavenLink CLI tool               │
├─────────────────────────────────────┤
│  Security:                          │
│  - Read-only root filesystem        │
│  - No SSH / no remote admin         │
│  - tmpfs for all mutable state      │
│  - Module blacklisting              │
└─────────────────────────────────────┘
```

## Quick Start

### Build the Image

```bash
git clone https://github.com/SkogsErik/havenlink-OS.git
cd havenlink-OS

# Build for x86_64 (VM/laptop)
make image ARCH=x86_64

# Build for Raspberry Pi
make image ARCH=aarch64
```

Requires: `root`, `qemu-utils`, `debootstrap`/`apk`, internet access during build.

### Test in QEMU

```bash
sudo qemu-system-x86_64 \
  -m 512 -enable-kvm \
  -drive file=havenlink-os-0.1.0-x86_64.img,format=raw,if=ide \
  -nographic -serial mon:stdio
```

Login: `root` / `havenlink`

### Write to Physical Media

```bash
sudo dd if=havenlink-os-0.1.0-x86_64.img of=/dev/sdX bs=4M status=progress
```

### Using HavenLink

After login, Tor is already running. Launch the chat client:

```bash
# Connect via Tor (recommended)
havenlink --name yourname --tor

# Connect via direct internet
havenlink --name yourname --internet

# Connect via LoRa radio
havenlink --name yourname --lora
```

## Services at Boot

| Service | Autostart | Description |
|---------|-----------|-------------|
| nftables | ✅ | Firewall — drop all except mesh ports + Tor |
| tor | ✅ | Tor daemon (SOCKS on 127.0.0.1:9050) |
| havenlink | ❌ | Interactive CLI tool — run manually |

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — System design
- [Threat Model](docs/THREAT_MODEL.md) — Security analysis
- [Project Structure](docs/PROJECT_STRUCTURE.md) — File layout

## Requirements

- x86_64 PC / Raspberry Pi 3 or 4
- 2GB+ storage
- Console access (serial or keyboard/display)

## Security Notes

See [THREAT_MODEL.md](docs/THREAT_MODEL.md) for full analysis.

**Disabled at runtime:**
- SSH server
- HTTP/HTTPS admin interfaces
- Any remote administration
- Package manager (no `apk` at runtime)

**Enabled at runtime:**
- Tor client (autostarted, `127.0.0.1:9050`)
- nftables firewall
- HavenLink mesh ports 9001–9010

## Repository Structure

```
havenlink-OS/
├── docs/               # Documentation
├── scripts/            # build-image.sh, setup-device.sh, havenlink-wipe.sh
├── config/             # torrc, firewall.nft, sysctl.conf, havenlink.conf, …
├── overlay/            # Files copied verbatim into the image root
├── Makefile
├── VERSION
└── AGENT_GUIDE.md      # Notes for AI coding agents
```

## Related Repositories

- **HavenLink** (chat app): https://github.com/SkogsErik/havenlink
- **HavenLink OS** (this): https://github.com/SkogsErik/havenlink-OS

## License

TBD
