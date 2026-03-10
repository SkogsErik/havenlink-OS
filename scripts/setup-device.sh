#!/bin/sh
#
# HavenLink OS - Device Setup
#
# USB key management and WiFi AP setup are delegated to havenlink-tools.
# This script handles Tor/firewall verification and first-boot orientation.
#
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root" >&2
    exit 1
fi

TOOLS=/usr/local/bin/havenlink-tools

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

check_tor() {
    echo ""
    echo "=== Checking Tor ==="
    if rc-service tor status >/dev/null 2>&1; then
        echo "Tor is running."
    else
        echo "Tor is not running — starting..."
        rc-service tor start
    fi
}

check_firewall() {
    echo ""
    echo "=== Checking Firewall ==="
    if nft list ruleset | grep -q "havenlink\|chain input" 2>/dev/null; then
        echo "nftables rules loaded."
    else
        echo "Loading nftables rules..."
        nft -f /etc/firewall.nft
    fi
}

# Prompt user to pick a USB device from detected block devices
pick_usb_device() {
    echo ""
    echo "Detected block devices:"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -v loop || true
    echo ""
    printf "Enter USB device (e.g. /dev/sdb): "
    read USB_DEV
    [ -b "$USB_DEV" ] || die "$USB_DEV is not a block device"
}

# ---------------------------------------------------------------------------
# Menu actions
# ---------------------------------------------------------------------------

do_usb_init() {
    pick_usb_device
    echo ""
    echo "WARNING: This will overwrite havenlink/ directory on $USB_DEV."
    printf "Continue? [y/N]: "
    read yn
    case "$yn" in [Yy]*) ;; *) echo "Aborted."; return ;; esac
    "$TOOLS" usb init --device "$USB_DEV"
}

do_wifi_start() {
    pick_usb_device
    "$TOOLS" wifi start --device "$USB_DEV"
    echo ""
    echo "WiFi AP started. SSID: HavenLink-Mesh"
    echo "Share the passphrase with: havenlink-tools wifi show-passphrase --device $USB_DEV"
}

do_full_setup() {
    check_tor
    check_firewall
    echo ""
    echo "=== USB Key Setup ==="
    pick_usb_device
    "$TOOLS" usb init --device "$USB_DEV"
    echo ""
    echo "=== Identity ==="
    echo "Run the following to write your identity keypair to the USB key:"
    echo "  havenlink --init-usb-key /mnt/havenlink-usb/havenlink/identity.enc"
    echo ""
    echo "=== WiFi AP ==="
    printf "Start WiFi AP now? [y/N]: "
    read yn
    case "$yn" in
        [Yy]*)
            "$TOOLS" wifi start --device "$USB_DEV"
            echo "WiFi AP started. SSID: HavenLink-Mesh"
            echo "Passphrase: havenlink-tools wifi show-passphrase --device $USB_DEV"
            ;;
    esac
}

show_status() {
    echo ""
    echo "=== Service Status ==="
    for svc in tor nftables hostapd dnsmasq; do
        status="stopped"
        rc-service "$svc" status >/dev/null 2>&1 && status="running"
        printf "  %-12s %s\n" "$svc" "$status"
    done
    echo ""
    echo "=== WiFi AP Status ==="
    "$TOOLS" wifi status
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

main() {
    echo "========================================="
    echo "  HavenLink OS — Device Setup"
    echo "========================================="
    echo ""
    echo "  1) Full first-time setup (USB key + Tor + Firewall + WiFi)"
    echo "  2) Initialise USB key only"
    echo "  3) Start WiFi AP (USB key required)"
    echo "  4) Stop WiFi AP"
    echo "  5) Show service status"
    echo "  6) USB key info"
    echo "  7) Exit"
    echo ""
    printf "Choice [1-7]: "
    read choice

    case "$choice" in
        1) do_full_setup ;;
        2) do_usb_init ;;
        3) do_wifi_start ;;
        4) "$TOOLS" wifi stop ;;
        5) show_status ;;
        6)
            pick_usb_device
            "$TOOLS" usb show --device "$USB_DEV"
            ;;
        7) echo "Exiting."; exit 0 ;;
        *) echo "Invalid choice."; exit 1 ;;
    esac

    echo ""
    echo "Done."
}

main "$@"
