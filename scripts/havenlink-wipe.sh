#!/bin/sh
#
# HavenLink OS - Emergency Wipe
# Securely destroys all identity data
#
set -e

echo "========================================="
echo "  HavenLink OS - Emergency Wipe"
echo "========================================="
echo ""
echo "WARNING: This will PERMANENTLY DELETE:"
echo "  - Your identity keys"
echo "  - All contacts"
echo "  - All message history"
echo "  - All session data"
echo ""
echo "This action CANNOT be undone."
echo ""

# Confirm
echo -n "Are you sure? Type 'YES' to confirm: "
read confirm

if [ "$confirm" != "YES" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Wiping identity data..."

# Wipe data directories
DATA_DIR="${data_dir:-/var/lib/havenlink}"

if [ -d "$DATA_DIR" ]; then
    # Overwrite with random data before deletion
    find "$DATA_DIR" -type f -exec sh -c '
        file="$1"
        size=$(stat -c%s "$file" 2>/dev/null || echo 4096)
        dd if=/dev/urandom of="$file" bs=1 count="$size" 2>/dev/null || true
    ' _ {} \;
    
    # Remove all files
    rm -rf "$DATA_DIR"/*
fi

# Wipe logs
LOG_DIR="${log_dir:-/var/log/havenlink}"
if [ -d "$LOG_DIR" ]; then
    rm -f "$LOG_DIR"/*
fi

# Clear any USB identity
for dev in /dev/sd*; do
    if [ -b "$dev" ]; then
        mountpoint="/mnt/usb_wipe"
        mkdir -p "$mountpoint"
        if mount -o rw "$dev" "$mountpoint" 2>/dev/null; then
            if [ -f "$mountpoint/loramesh_identity.enc" ]; then
                echo "Wiping USB identity..."
                rm -f "$mountpoint/loramesh_identity.enc"
            fi
            umount "$mountpoint"
        fi
    fi
done

echo ""
echo "========================================="
echo "  WIPE COMPLETE"
echo "========================================="
echo ""
echo "All identity data has been destroyed."
echo "Device is safe to dispose of or return."
echo ""

# Sync and shutdown
sync
echo "Device will power off in 10 seconds..."
sleep 10
poweroff -f
