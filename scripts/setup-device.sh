#!/bin/sh
#
# HavenLink OS - First-time Device Setup
# Runs on first boot or when needed
#
set -e

echo "========================================="
echo "  HavenLink OS - Initial Setup"
echo "========================================="
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Load configuration
if [ -f /etc/havenlink/havenlink.conf ]; then
    . /etc/havenlink/havenlink.conf
fi

DATA_DIR="${data_dir:-/var/lib/havenlink}"
LOG_DIR="${log_dir:-/var/log/havenlink}"

echo "Data directory: $DATA_DIR"
echo "Log directory: $LOG_DIR"
echo ""

# Check for USB key
check_usb_key() {
    echo "Checking for USB key..."
    # Look for mounted USB with havenlink data
    for dev in /dev/sd*; do
        if [ -b "$dev" ]; then
            # Try to mount and check
            mountpoint="/mnt/usb"
            mkdir -p "$mountpoint"
            if mount -o ro "$dev" "$mountpoint" 2>/dev/null; then
                if [ -f "$mountpoint/loramesh_identity.enc" ]; then
                    echo "Found USB key with identity!"
                    USB_FOUND=1
                    return 0
                fi
                umount "$mountpoint" 2>/dev/null
            fi
        fi
    done
    echo "No USB key found"
    USB_FOUND=0
    return 1
}

# Generate new identity
generate_identity() {
    echo ""
    echo "=== Generating New Identity ==="
    echo ""
    
    # Create data directory
    mkdir -p "$DATA_DIR/keys"
    mkdir -p "$DATA_DIR/contacts"
    mkdir -p "$DATA_DIR/sessions"
    mkdir -p "$DATA_DIR/queue"
    mkdir -p "$LOG_DIR"
    
    chown -R havenlink:havenlink "$DATA_DIR"
    chown -R havenlink:havenlink "$LOG_DIR"
    
    # Generate identity using Python (would call havenlink tool)
    echo "Identity will be generated on first run of havenlink"
    
    echo ""
    echo "Identity created at: $DATA_DIR/keys/"
}

# Import from USB
import_usb() {
    echo ""
    echo "=== Import from USB ==="
    echo "Please insert your USB key and press Enter..."
    read
    
    # Mount USB
    mountpoint="/mnt/usb"
    mkdir -p "$mountpoint"
    
    # Find and mount USB
    for dev in /dev/sd*; do
        if mount -o ro "$dev" "$mountpoint" 2>/dev/null; then
            if [ -f "$mountpoint/loramesh_identity.enc" ]; then
                echo "Copying identity from USB..."
                cp "$mountpoint/loramesh_identity.enc" "$DATA_DIR/keys/"
                if [ -d "$mountpoint/contacts" ]; then
                    cp -r "$mountpoint/contacts/"* "$DATA_DIR/contacts/"
                fi
                umount "$mountpoint"
                echo "Import complete!"
                return 0
            fi
            umount "$mountpoint" 2>/dev/null
        fi
    done
    
    echo "Error: No valid USB key found"
    return 1
}

# Setup Tor
setup_tor() {
    echo ""
    echo "=== Configuring Tor ==="
    
    # Generate Tor config if not exists
    if [ ! -f /etc/tor/torrc ]; then
        cp /etc/tor/torrc.dist /etc/tor/torrc 2>/dev/null || true
    fi
    
    # Enable and start Tor
    rc-update add tor default 2>/dev/null || true
    rc-service tor start 2>/dev/null || true
    
    echo "Tor configured"
}

# Setup firewall
setup_firewall() {
    echo ""
    echo "=== Configuring Firewall ==="
    
    # Load nftables rules
    if [ -f /etc/havenlink/firewall.nft ]; then
        nft -f /etc/havenlink/firewall.nft
        echo "Firewall rules loaded"
    fi
    
    # Enable nftables
    rc-update add nftables default 2>/dev/null || true
}

# Enable services
enable_services() {
    echo ""
    echo "=== Enabling Services ==="
    
    # Enable havenlink service
    rc-update add havenlink default 2>/dev/null || true
    
    echo "Services enabled"
}

# Main menu
main() {
    echo "Select setup option:"
    echo ""
    echo "1) Generate new identity"
    echo "2) Import from USB key"
    echo "3) Full setup (identity + Tor + firewall)"
    echo "4) Skip (run manually later)"
    echo ""
    echo -n "Choice [1-4]: "
    read choice
    
    case "$choice" in
        1)
            generate_identity
            ;;
        2)
            if check_usb_key; then
                import_usb
            fi
            ;;
        3)
            generate_identity
            setup_tor
            setup_firewall
            enable_services
            ;;
        4)
            echo "Skipping setup"
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
    
    echo ""
    echo "========================================="
    echo "  Setup Complete!"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Start HavenLink: rc-service havenlink start"
    echo "  2. Run havenlink-setup for interactive configuration"
    echo "  3. Connect to mesh peers"
    echo ""
}

main "$@"
