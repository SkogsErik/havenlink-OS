# HavenLink OS - Architecture

## Executive Summary

HavenLink OS is a purpose-built, hardened operating system for secure peer-to-peer mesh communication. Designed for **air-gapped or internet-disconnected** environments with zero attack surface for administration.

**Key Design Principles:**
- **Minimal**: Absolute minimum packages (~100MB base)
- **Secure**: No remote admin, console-only management  
- **Isolated**: Read-only root, RAM-only message storage
- **Tamper-resistant**: USB key identity, memory sanitization

---

## 1. OS Base

### 1.1 Selection: Alpine Linux

| Aspect | Alpine | Debian Minimal |
|--------|--------|----------------|
| Base size | ~100MB | ~400MB |
| C library | musl | glibc |
| Init system | OpenRC | systemd |
| Package manager | apk | apt |

**Why Alpine:**
- musl is smaller and more memory-safe than glibc
- APK is simpler to audit
- Build-time includes only what you need
- Established in containers/embedded

### 1.2 Runtime vs Build-Time

```
BUILD-TIME (Internet)          RUNTIME (Air-gapped)
─────────────────────          ─────────────────────
- Alpine Linux + tools         - Read-only root
- Python, C compilers          - No package manager
- Generate ISO/IMG             - Only: kernel, OpenRC, Tor, HavenLink
                                  No SSH, no remote admin
```

---

## 2. Security Architecture

### 2.1 Network Model

```
┌────────────────────────────────────────┐
│           HavenLink Device              │
├────────────────────────────────────────┤
│  Ethernet/WiFi    LoRa (future)        │
│  (Mesh LAN)                           │
│        │                               │
│        ▼                               │
│   HavenLink Core (Python + C)          │
│        │                               │
│        ▼                               │
│        Tor (client only, outbound)      │
└────────────────────────────────────────┘
         │
         ▼ (optional internet)
      Internet
```

**Network Rules:**
- No incoming connections except from mesh peers on LAN
- Outbound only via Tor (for internet)
- No remote admin - console only
- No DNS except through Tor

### 2.2 Administration

**Only via:**
- Serial console (Pi/headless)
- Direct keyboard + display (laptop/VM)

**Disabled:**
- SSH server
- HTTP/HTTPS admin
- Any remote API
- Firewall management remotely

### 2.3 Identity Storage

- **Primary**: USB key (XChaCha20-Poly1305 encrypted)
- **Fallback**: Derived from device + PIN
- **Duress**: Optional decoy identity

### 2.4 Memory Security

- No swap, no hibernation
- kdump disabled
- Core dumps disabled
- IOMMU enabled (block DMA)
- Secure memory clearing after use

---

## 3. Component Architecture

```
┌─────────────────────────────────────────┐
│          Application Layer               │
│  - CLI UI (Primary)                     │
│  - Setup TUI                            │
│  - HavenLink Core (Python)              │
│    • Protocol, Session, Crypto, Contact│
├─────────────────────────────────────────┤
│          Transport Layer (C)            │
│  - TCP/IP Socket                        │
│  - Tor Onion                            │
│  - LoRa (future)                        │
│  - Noise Protocol                       │
├─────────────────────────────────────────┤
│          System Layer (C)               │
│  - Secure Memory                        │
│  - Key Store                            │
│  - Memory Sanitizer                     │
└─────────────────────────────────────────┘
```

---

## 4. Transport Modularity

```python
class Transport(ABC):
    @abstractmethod
    def bind(self, port: int) -> None
    @abstractmethod
    def connect(self, address: str, port: int) -> Peer
    @abstractmethod
    def send(self, peer_id: bytes, data: bytes) -> None
    @abstractmethod
    def receive(self) -> tuple[bytes, bytes]
    @abstractmethod
    def close(self) -> None
```

**Implementations:**
- `TcpTransport` - Direct TCP mesh
- `TorTransport` - Tor onion services
- `LoraTransport` - LoRa radio (future)
- `MockTransport` - Testing

---

## 5. Operations

### First-Time Setup
1. Write image to boot media
2. Boot device
3. Connect console
4. Run `havenlink-setup`
5. Initialize identity / import from USB
6. Ready for use

### Daily Operation
1. Insert USB key
2. Power on
3. HavenLink starts automatically
4. Mesh networking begins
5. Send/receive messages
6. Power off

### Emergency Wipe
- Physical: destroy USB key
- Software: `/wipe` command

---

## Security Checklist

- [x] No remote admin (SSH disabled)
- [x] Console-only management
- [x] USB key identity
- [x] Read-only root
- [x] No swap
- [x] No crash dumps
- [x] Outbound-only Tor
- [x] Noise protocol encryption
- [x] Double Ratchet forward secrecy
- [x] Memory sanitization
- [x] No unnecessary services
