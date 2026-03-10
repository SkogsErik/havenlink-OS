#!/usr/bin/env python3
"""
havenlink-tools — Device management CLI for HavenLink OS

Handles USB key lifecycle, WiFi AP management, device setup, and emergency wipe.
This is the OS-level companion to the havenlink chat application.

Usage:
    havenlink-tools usb init   --device /dev/sdb
    havenlink-tools usb verify --device /dev/sdb
    havenlink-tools usb rotate --device /dev/sdb
    havenlink-tools usb show   --device /dev/sdb

    havenlink-tools wifi start
    havenlink-tools wifi stop
    havenlink-tools wifi status
    havenlink-tools wifi show-passphrase --device /dev/sdb

    havenlink-tools setup
    havenlink-tools wipe [--confirm]
"""

import argparse
import base64
import os
import subprocess
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# USB key layout constants — shared contract between havenlink-tools and the
# havenlink chat app. The chat app reads IDENTITY_FILE; everything else is
# owned by havenlink-tools.
#
# USB filesystem root:
#   havenlink/
#     identity.enc      — encrypted identity keypair (written by chat app via
#                         --init-usb-key, read by havenlink --usb-key)
#     wifi-salt         — 32 random bytes used to derive the WPA2 passphrase
#     version           — layout version string (currently "1")
# ---------------------------------------------------------------------------
USB_MOUNT_POINT   = Path("/mnt/havenlink-usb")
USB_DIR           = USB_MOUNT_POINT / "havenlink"
USB_IDENTITY_FILE = USB_DIR / "identity.enc"
USB_WIFI_SALT     = USB_DIR / "wifi-salt"
USB_VERSION_FILE  = USB_DIR / "version"
USB_LAYOUT_VERSION = "1"

HOSTAPD_RUNTIME_PSK = Path("/run/hostapd.psk")
WIFI_SALT_SIZE      = 32   # bytes
HKDF_INFO           = b"havenlink-wifi-v1"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def require_root() -> None:
    if os.geteuid() != 0:
        die("this command must be run as root")


def mount_usb(device: str, read_only: bool = True) -> Path:
    USB_MOUNT_POINT.mkdir(parents=True, exist_ok=True)
    flags = ["-o", "ro"] if read_only else ["-o", "rw"]
    result = subprocess.run(
        ["mount"] + flags + [device, str(USB_MOUNT_POINT)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        die(f"could not mount {device}: {result.stderr.strip()}")
    return USB_MOUNT_POINT


def umount_usb() -> None:
    subprocess.run(["umount", str(USB_MOUNT_POINT)], capture_output=True)


def derive_wifi_passphrase(wifi_salt: bytes) -> str:
    """Derive a WPA2 passphrase from wifi-salt using HKDF-SHA256."""
    try:
        from cryptography.hazmat.primitives.kdf.hkdf import HKDF
        from cryptography.hazmat.primitives import hashes
    except ImportError:
        die("missing dependency: py3-cryptography (apk add py3-cryptography)")

    hkdf = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=HKDF_INFO,
    )
    key_bytes = hkdf.derive(wifi_salt)
    # base64url encoding → 43 printable chars, valid WPA2 passphrase length
    return base64.urlsafe_b64encode(key_bytes).rstrip(b"=").decode()


# ---------------------------------------------------------------------------
# USB subcommands
# ---------------------------------------------------------------------------

def usb_init(args: argparse.Namespace) -> None:
    """Initialise a USB key with wifi-salt and layout version marker.

    NOTE: identity.enc is written by `havenlink --init-usb-key`, not here.
    This command prepares the OS-owned portions of the USB key layout.
    """
    require_root()
    device = args.device

    print(f"Initialising USB key on {device}...")
    print("WARNING: this will format the device. Ctrl-C to abort.")
    input("Press Enter to continue...")

    # Format as FAT32 for maximum compatibility
    result = subprocess.run(["mkfs.vfat", "-F", "32", "-n", "HAVENLINK", device],
                            capture_output=True, text=True)
    if result.returncode != 0:
        die(f"mkfs.vfat failed: {result.stderr.strip()}")

    mount_usb(device, read_only=False)
    try:
        USB_DIR.mkdir(parents=True, exist_ok=True)

        # Write layout version
        USB_VERSION_FILE.write_text(USB_LAYOUT_VERSION + "\n")

        # Generate wifi-salt
        wifi_salt = os.urandom(WIFI_SALT_SIZE)
        USB_WIFI_SALT.write_bytes(wifi_salt)
        os.chmod(USB_WIFI_SALT, 0o600)

        print("USB key initialised.")
        print(f"  Layout version : {USB_LAYOUT_VERSION}")
        print(f"  wifi-salt      : {wifi_salt.hex()}")
        print()
        print("Next: run  havenlink --init-usb-key /mnt/havenlink-usb/havenlink/identity.enc")
        print("      to write the identity keypair to the same key.")
    finally:
        umount_usb()


def usb_verify(args: argparse.Namespace) -> None:
    """Verify USB key layout and presence of required files."""
    require_root()
    mount_usb(args.device)
    try:
        ok = True
        for label, path in [
            ("layout version", USB_VERSION_FILE),
            ("wifi-salt",      USB_WIFI_SALT),
        ]:
            status = "✓" if path.exists() else "✗ MISSING"
            if not path.exists():
                ok = False
            print(f"  {status}  {label}  ({path.relative_to(USB_MOUNT_POINT)})")

        # identity.enc is optional here — written by the chat app
        id_status = "✓" if USB_IDENTITY_FILE.exists() else "- (not yet written)"
        print(f"  {id_status}  identity.enc  ({USB_IDENTITY_FILE.relative_to(USB_MOUNT_POINT)})")

        if ok:
            version = USB_VERSION_FILE.read_text().strip()
            print(f"\nUSB key OK (layout v{version})")
        else:
            print("\nUSB key incomplete — run: havenlink-tools usb init --device <dev>")
            sys.exit(1)
    finally:
        umount_usb()


def usb_rotate(args: argparse.Namespace) -> None:
    """Rotate wifi-salt. This changes the derived WiFi passphrase."""
    require_root()
    mount_usb(args.device, read_only=False)
    try:
        if not USB_VERSION_FILE.exists():
            die("not a HavenLink USB key — run usb init first")
        new_salt = os.urandom(WIFI_SALT_SIZE)
        USB_WIFI_SALT.write_bytes(new_salt)
        os.chmod(USB_WIFI_SALT, 0o600)
        print(f"wifi-salt rotated. New value: {new_salt.hex()}")
        print("Restart the WiFi AP to apply: havenlink-tools wifi start --device <dev>")
    finally:
        umount_usb()


def usb_show(args: argparse.Namespace) -> None:
    """Show USB key layout summary (no secrets printed)."""
    require_root()
    mount_usb(args.device)
    try:
        version = USB_VERSION_FILE.read_text().strip() if USB_VERSION_FILE.exists() else "unknown"
        has_salt = USB_WIFI_SALT.exists()
        has_identity = USB_IDENTITY_FILE.exists()
        salt_size = USB_WIFI_SALT.stat().st_size if has_salt else 0
        print(f"Layout version : {version}")
        print(f"wifi-salt      : {'present (' + str(salt_size) + ' bytes)' if has_salt else 'MISSING'}")
        print(f"identity.enc   : {'present' if has_identity else 'not written'}")
    finally:
        umount_usb()


# ---------------------------------------------------------------------------
# WiFi subcommands
# ---------------------------------------------------------------------------

def wifi_start(args: argparse.Namespace) -> None:
    """Derive passphrase from USB key and start hostapd."""
    require_root()
    mount_usb(args.device)
    try:
        if not USB_WIFI_SALT.exists():
            die("wifi-salt not found on USB key — run: havenlink-tools usb init --device <dev>")
        wifi_salt = USB_WIFI_SALT.read_bytes()
    finally:
        umount_usb()

    passphrase = derive_wifi_passphrase(wifi_salt)

    # Write passphrase to tmpfs — never touches persistent storage
    HOSTAPD_RUNTIME_PSK.parent.mkdir(parents=True, exist_ok=True)
    HOSTAPD_RUNTIME_PSK.write_text(passphrase + "\n")
    os.chmod(HOSTAPD_RUNTIME_PSK, 0o600)

    result = subprocess.run(["rc-service", "hostapd", "start"], capture_output=True, text=True)
    if result.returncode != 0:
        die(f"hostapd failed to start: {result.stderr.strip()}")
    print("WiFi AP started.")


def wifi_stop(args: argparse.Namespace) -> None:
    """Stop hostapd and wipe the runtime passphrase."""
    require_root()
    subprocess.run(["rc-service", "hostapd", "stop"], capture_output=True)
    if HOSTAPD_RUNTIME_PSK.exists():
        # Overwrite before unlinking
        HOSTAPD_RUNTIME_PSK.write_bytes(os.urandom(64))
        HOSTAPD_RUNTIME_PSK.unlink()
    print("WiFi AP stopped, passphrase wiped.")


def wifi_status(args: argparse.Namespace) -> None:
    """Show hostapd service status."""
    subprocess.run(["rc-service", "hostapd", "status"])


def wifi_show_passphrase(args: argparse.Namespace) -> None:
    """Derive and print the current WiFi passphrase (for sharing with users)."""
    require_root()
    mount_usb(args.device)
    try:
        if not USB_WIFI_SALT.exists():
            die("wifi-salt not found on USB key")
        wifi_salt = USB_WIFI_SALT.read_bytes()
    finally:
        umount_usb()
    passphrase = derive_wifi_passphrase(wifi_salt)
    print(f"WiFi passphrase: {passphrase}")
    print("(Share this with trusted users to join the HavenLink-Mesh network)")


# ---------------------------------------------------------------------------
# Device subcommands
# ---------------------------------------------------------------------------

def device_setup(args: argparse.Namespace) -> None:
    """Interactive first-time device setup."""
    require_root()
    print("=== HavenLink OS — First-time Setup ===")
    print()
    print("Steps:")
    print("  1. Insert a USB key and run:  havenlink-tools usb init --device /dev/sdb")
    print("  2. Write identity keypair:    havenlink --init-usb-key /mnt/havenlink-usb/havenlink/identity.enc")
    print("  3. Start WiFi AP:             havenlink-tools wifi start --device /dev/sdb")
    print("  4. Start chat:                havenlink --name <name> --usb-key <path> --tor")
    print()
    print("See /etc/havenlink/havenlink.conf for configuration options.")


def device_wipe(args: argparse.Namespace) -> None:
    """Emergency wipe — overwrite all volatile state."""
    require_root()
    if not args.confirm:
        print("This will wipe all runtime state (tmpfs, passphrase, logs).")
        print("Re-run with --confirm to proceed.")
        sys.exit(1)

    wifi_stop(args)
    for path in ["/var/lib/tor", "/var/log", "/tmp", "/run/havenlink"]:
        subprocess.run(["find", path, "-type", "f",
                        "-exec", "shred", "-uz", "{}", ";"],
                       capture_output=True)
    print("Runtime state wiped. Power off the device now.")


# ---------------------------------------------------------------------------
# Argument parser
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="havenlink-tools",
        description="Device management CLI for HavenLink OS",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # -- usb --
    usb_p = sub.add_parser("usb", help="USB key management")
    usb_sub = usb_p.add_subparsers(dest="usb_command", required=True)

    for name, fn, help_text in [
        ("init",   usb_init,   "Initialise a USB key (formats device)"),
        ("verify", usb_verify, "Verify USB key layout"),
        ("rotate", usb_rotate, "Rotate wifi-salt (changes WiFi passphrase)"),
        ("show",   usb_show,   "Show USB key contents summary"),
    ]:
        p = usb_sub.add_parser(name, help=help_text)
        p.add_argument("--device", required=True, metavar="DEV",
                       help="USB block device (e.g. /dev/sdb)")
        p.set_defaults(func=fn)

    # -- wifi --
    wifi_p = sub.add_parser("wifi", help="WiFi AP management")
    wifi_sub = wifi_p.add_subparsers(dest="wifi_command", required=True)

    for name, fn, help_text, needs_device in [
        ("start",           wifi_start,           "Derive passphrase and start AP", True),
        ("stop",            wifi_stop,            "Stop AP and wipe passphrase",    False),
        ("status",          wifi_status,          "Show AP status",                 False),
        ("show-passphrase", wifi_show_passphrase, "Print current WiFi passphrase",  True),
    ]:
        p = wifi_sub.add_parser(name, help=help_text)
        if needs_device:
            p.add_argument("--device", required=True, metavar="DEV",
                           help="USB block device containing wifi-salt")
        p.set_defaults(func=fn)

    # -- setup --
    setup_p = sub.add_parser("setup", help="Interactive first-time device setup guide")
    setup_p.set_defaults(func=device_setup)

    # -- wipe --
    wipe_p = sub.add_parser("wipe", help="Emergency wipe of all runtime state")
    wipe_p.add_argument("--confirm", action="store_true",
                        help="Required to actually perform the wipe")
    wipe_p.set_defaults(func=device_wipe)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
