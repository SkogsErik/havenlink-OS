# HavenLink OS - Threat Model

## Document Information

| Version | Date | Status |
|---------|------|--------|
| 0.1 | 2026-03-10 | Initial |
| 0.2 | 2026-03-10 | Added WiFi AP threats |

---

## 1. Scope and Purpose

This threat model covers the HavenLink OS operating system, including:
- The hardened Linux base (Alpine)
- HavenLink application (Python + C)
- Transport layer (TCP, Tor)
- USB key identity storage
- Physical device security

**Out of Scope:**
- HavenLink protocol (covered in main HavenLink repo)
- LoRa radio (future feature)
- Network infrastructure (routers, ISP)

---

## 2. Target Users and Threat Profile

### 2.1 Intended Users

| User Type | Threat Profile |
|-----------|----------------|
| Journalists in hostile countries | High - state-level adversaries |
| Activists | Medium-High - targeted surveillance |
| Whistleblowers | High - powerful organizations |
| Dissidents | Medium-High - government surveillance |

### 2.2 Threat Actor Profile

**Primary Threat Actors:**

| Actor | Capability | Intent |
|-------|------------|--------|
| Nation-state (Tier 1) | Full spectrum, quantum computing | High |
| Nation-state (Tier 2) | Network-level, malware | High |
| Organized crime | Financial, malware | Medium |
| Local adversary | Physical access, RF | Medium |
| Script kiddie | Basic tools | Low |

---

## 3. Asset Identification

### 3.1 Critical Assets

| Asset | Classification | Impact if Compromised |
|-------|----------------|---------------------|
| Identity private key | Critical | Complete identity theft |
| Session keys | Critical | Read past messages |
| Contact list | High | Identify network |
| Message content | High | Privacy loss |
| USB key | High | Identity theft |

### 3.2 High-Value Assets

| Asset | Classification | Impact |
|-------|----------------|--------|
| Onion address | Medium | Deanonymization |
| Device hardware | Medium | Key extraction |
| Configuration | Medium | Attack surface |
| Logs | Medium | Pattern analysis |

### 3.3 Low-Value Assets

| Asset | Classification | Impact |
|-------|----------------|--------|
| System time | Low | Traffic analysis |
| Uptime | Low | Operational info |
| Version info | Low | Targeting |

---

## 4. Attack Surface Analysis

### 4.1 Network Attack Surface

```
┌─────────────────────────────────────────────────────────────┐
│                   Network Interfaces                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  eth0 (Ethernet)                                           │
│  ├── Mesh peers (TCP 9001-9010)         ──► Limited: peers │
│  └── Tor SOCKS (127.0.0.1:9050)         ──► Local only    │
│                                                              │
│  wlan0 (WiFi AP)                                           │
│  ├── Mesh clients (TCP 9001-9010)      ──► WiFi clients    │
│  ├── DHCP server (10.0.0.1:67)          ──► Local only    │
│  └── WiFi management                    ──► Local only      │
│                                                              │
│  lo (Loopback)                                             │
│  └── Local services only                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Exposure:**
| Interface | Public | Mesh Peers | WiFi Clients | Tor | Local |
|-----------|--------|-------------|--------------|-----|-------|
| TCP 9001-9010 | No | Yes | Yes | No | Yes |
| DHCP | No | No | Yes | No | Localhost |
| Tor SOCKS | No | No | No | Yes | Localhost |
| Tor Control | No | No | No | No | Localhost |

### 4.2 Physical Attack Surface

| Vector | Access Required | Mitigation |
|--------|-----------------|-------------|
| USB port | Physical | Disable mass storage |
| Serial console | Physical | No remote access |
| SD card removal | Physical | Encrypted, read-only root |
| RAM extraction | Physical | Memory clears on power loss |
| Cold boot | Physical | No suspend/hibernate |
| DMA | Physical | IOMMU enabled |

### 4.3 Software Attack Surface

| Component | Lines of Code | Risk |
|-----------|---------------|------|
| Linux kernel | ~30M | Low (hardened) |
| Alpine base | ~5K packages | Medium |
| Python runtime | Standard | Medium |
| HavenLink app | ~10K | High (trusted) |
| C modules | ~2K | High (trusted) |

---

## 5. Threat Analysis

### 5.1 Network Threats

#### T1: Network Eavesdropping

**Description:** Passive observer captures network traffic

**Attack Vectors:**
- LAN sniffing
- ISP metadata
- Tor exit node (if used)

**Likelihood:** High (network always visible)

**Impact:** Medium (content encrypted)

**Mitigations:**
- [x] TLS/Noise encryption
- [x] Tor onion routing
- [ ] Cover traffic (not feasible with duty cycle)

**Residual Risk:** Low

---

#### T2: Man-in-the-Middle

**Description:** Attacker intercepts and modifies traffic

**Attack Vectors:**
- ARP spoofing on LAN
- BGP hijacking
- Tor circuit manipulation

**Likelihood:** Low-Medium

**Impact:** High (message manipulation)

**Mitigations:**
- [x] Ed25519 key authentication
- [x] Certificate pinning in Noise
- [x] Tor v3 onion services

**Residual Risk:** Low

---

#### T3: Denial of Service

**Description:** Attacker disrupts service availability

**Attack Vectors:**
- TCP SYN flood
- Resource exhaustion
- Network jamming (LoRa - future)

**Likelihood:** High

**Impact:** Medium (availability)

**Mitigations:**
- [x] Rate limiting
- [x] Connection limits
- [x] Mesh redundancy (future)

**Residual Risk:** Medium

---

#### T12: WiFi Eavesdropping

**Description:** Attacker captures WiFi traffic within range

**Attack Vectors:**
- WiFi sniffing within range (~50-100m outdoors)
- Decrypting WPA2 traffic with captured handshake

**Likelihood:** High (WiFi is inherently broadcast)

**Impact:** Medium (WiFi traffic encrypted with WPA2)

**Mitigations:**
- [x] WPA2-Personal encryption
- [x] HaventLink messages encrypted end-to-end
- [ ] WPA3 (if supported by hardware)
- [ ] MAC address randomization (future)

**Residual Risk:** Low (E2E encryption protects message content)

---

#### T13: Rogue Access Point

**Description:** Attacker deploys fake WiFi AP with same SSID

**Attack Vectors:**
- Evil twin attack
- Users connect to attacker's AP instead

**Likelihood:** Medium (requires attacker in physical proximity)

**Impact:** High (man-in-the-middle, data interception)

**Mitigations:**
- [x] Ed25519 key authentication prevents MITM
- [x] Users verify fingerprints out-of-band
- [ ] Certificate pinning for AP identity (future)

**Residual Risk:** Low (app-level encryption)

---

#### T14: WiFi Deauthentication Attack

**Description:** Attacker sends deauth packets to disconnect clients

**Attack Vectors:**
- 802.11w deauth frames
- Disrupt connectivity to force reconnections

**Likelihood:** Medium

**Impact:** Low-Medium (temporary disruption)

**Mitigations:**
- [x] 802.11w protected management frames (if supported)
- [ ] AP isolation (configurable)
- [x] Auto-reconnection in HavenLink app

**Residual Risk:** Low

---

#### T15: Unauthorized WiFi Access

**Description:** Unauthorized user gains WiFi access

**Attack Vectors:**
- Guessing WiFi password
- Captured password leakage

**Likelihood:** Low-Medium

**Impact:** Medium (access to local network)

**Mitigations:**
- [x] WPA2-Personal with strong password requirement
- [x] Mesh traffic encrypted (can't read messages)
- [x] Firewall blocks unauthorized access to services
- [ ] Password change on first setup (future)
- [ ] WiFi access logging (future)

**Residual Risk:** Low

---

#### T16: WiFi Driver Exploit

**Description:** Vulnerability in WiFi driver allows code execution

**Attack Vikelihood:** Low

**Impact:** Critical (full system compromise)

**Mitigations:**
- [ ] Use WiFi chips with well-maintained drivers
- [ ] Regular firmware updates (rebuild image)
- [ ] Network sandboxing (future)
- [ ] Minimal WiFi driver in kernel

**Residual Risk:** Low-Medium

---

### 5.2 Physical Threats

#### T4: Device Theft

**Description:** Attacker gains physical access to device

**Likelihood:** Medium (device can be lost/seized)

**Impact:** Critical (keys exposed)

**Mitigations:**
| Mitigation | Status |
|------------|--------|
| USB key storage | Required |
| No keys in RAM on boot | Yes |
| Encrypted storage | LUKS |
| Memory sanitize on shutdown | Yes |
| Auto-wipe after N failed attempts | Future |

**Residual Risk:** Low (with USB key)

---

#### T5: Cold Boot Attack

**Description:** Attacker freezes RAM to extract keys

**Likelihood:** Low (requires physical access quickly)

**Impact:** Critical

**Mitigations:**
| Mitigation | Status |
|------------|--------|
| No hibernation | Configured |
| No swap | Configured |
| Memory clear on shutdown | Implemented |
| TPM measured boot | Optional |

**Residual Risk:** Low

---

#### T6: DMA Attack

**Description:** Attacker uses FireWire/Thunderbolt to read RAM

**Likelihood:** Low

**Impact:** Critical

**Mitigations:**
- [x] IOMMU enabled
- [x] No FireWire stack
- [x] Thunderbolt locked down

**Residual Risk:** Low

---

### 5.3 Software Threats

#### T7: Kernel Exploit

**Description:** Attacker exploits kernel vulnerability

**Likelihood:** Medium (known vulnerabilities)

**Impact:** Critical (full system compromise)

**Mitigations:**
| Mitigation | Status |
|------------|--------|
| Minimal kernel config | Hardened |
| Regular rebuilds | Build-time |
| No unused drivers | Configured |
| Kernel lockdown | Enabled |
| Read-only root | Configured |

**Residual Risk:** Low-Medium

---

#### T8: Application Vulnerability

**Description:** Buffer overflow, injection in HavenLink app

**Likelihood:** Low (Python + audited libs)

**Impact:** High (key extraction possible)

**Mitigations:**
- [x] Python sandbox (limited)
- [x] libsodium (audited)
- [x] No dynamic code execution
- [ ] AppArmor (future)

**Residual Risk:** Low

---

#### T9: Supply Chain

**Description:** Attacker compromises build or dependencies

**Likelihood:** Low-Medium

**Impact:** Critical (backdoor)

**Mitigations:**
- [x] Reproducible builds (future)
- [x] Hash verification
- [x] Minimal dependencies
- [x] Air-gapped build

**Residual Risk:** Low

---

### 5.4 Operational Threats

#### T10: Social Engineering

**Description:** Attacker tricks user into revealing keys

**Likelihood:** Medium

**Impact:** Critical

**Mitigations:**
- [ ] User training
- [ ] Secure contact exchange
- [ ] Fingerprint verification

**Residual Risk:** Medium

---

#### T11: Physical Coercion

**Description:** Attacker forces key disclosure

**Likelihood:** Low (user-specific)

**Impact:** Critical

**Mitigations:**
| Mitigation | Status |
|------------|--------|
| Duress passphrase | Implemented |
| Decoy identity | Implemented |
| Quick wipe | Implemented |

**Residual Risk:** Low (with duress)

---

## 6. Risk Matrix

```
                    IMPACT
          Low    Medium    High    Critical
Likelihood
High        -      T3       -         -
Medium      -      T10      T1      T4, T5
Low         -      T8       T2      T6, T7
Very Low    -       -       T9      T11
```

**Key:**
- T1: Network Eavesdropping
- T2: Man-in-the-Middle
- T3: Denial of Service
- T4: Device Theft
- T5: Cold Boot Attack
- T6: DMA Attack
- T7: Kernel Exploit
- T8: Application Vulnerability
- T9: Supply Chain
- T10: Social Engineering
- T11: Physical Coercion

---

## 7. Security Properties

| Property | Mechanism | Status |
|----------|-----------|--------|
| Confidentiality | ChaCha20-Poly1305 | Implemented |
| Integrity | Poly1305 MAC | Implemented |
| Authentication | Ed25519 | Implemented |
| Forward Secrecy | Double Ratchet | Implemented |
| Identity Protection | Tor onion services | Implemented |
| Key Storage | XChaCha20 + Argon2id | Implemented |
| Duress Protection | Decoy identity | Implemented |
| Anti-Replay | Epoch + sliding window | Implemented |
| WiFi Security | WPA2-Personal | Implemented |
| WiFi Isolation | Client-to-client blocked | Configurable |
| Local Network | No internet routing | Implemented |

---

## 8. Security Assumptions

1. **Cryptographic assumptions:**
   - Ed25519 signatures are unforgeable
   - X25519 provides post-quantum security (hybrid planned)
   - ChaCha20-Poly1305 is IND-CCA2 secure
   - Argon2id is memory-hard

2. **Operational assumptions:**
   - Users keep USB key secure
   - Users verify fingerprints
   - Users don't share keys
   - Device is powered off when not in use

3. **Physical assumptions:**
   - Attacker cannot maintain physical access indefinitely
   - Cold boot attack requires < 30 seconds
   - Device can be destroyed if compromised

---

## 9. Out of Scope Threats

The following are explicitly out of scope:

| Threat | Reason |
|--------|--------|
| Quantum computing (now) | Hybrid crypto planned for future |
| User malware on device | Assume clean system |
| RF jamming (LoRa) | Physical layer - out of band |
| Social engineering | User training required |
| Insider threat at ISP | Cannot mitigate |

---

## 10. Recommendations Summary

### High Priority

1. **Enable AppArmor** - Mandatory access control for HavenLink
2. **Implement auto-wipe** - After N failed boot attempts
3. **User training** - Social engineering awareness

### Medium Priority

1. **Reproducible builds** - Supply chain integrity
2. **TPM integration** - Hardware-backed key storage
3. **Secure boot** - UEFI chain of trust

### Future

1. **Hybrid post-quantum crypto** - Lattice-based KEM
2. **Air-gapped build system** - Zero network exposure
3. **Hardware security module** - ATECC608A

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| Double Ratchet | Forward secrecy protocol |
| Ed25519 | Edwards-curve digital signature |
| X25519 | Elliptic curve key exchange |
| Argon2id | Memory-hard password hashing |
| ChaCha20-Poly1305 | AEAD cipher |
| Onion service | Tor hidden service |

---

## Appendix B: References

- OWASP Threat Modeling
- NIST SP 800-37 Risk Management
- STRIDE Methodology
- HavenLink Protocol Threat Model (main repo)
