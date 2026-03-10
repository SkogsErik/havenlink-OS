#!/bin/bash
#
# HavenLink OS - Build Image Script
# Creates a hardened Alpine-based bootable image
#
set -euo pipefail

VERSION="0.1.0"
ALPINE_VERSION="3.20"
ARCH="${ARCH:-aarch64}"  # aarch64, x86_64
IMAGE_NAME="havenlink-os-${VERSION}-${ARCH}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
WORK_DIR="/tmp/havenlink-build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[BUILD]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -a, --arch ARCH      Architecture: aarch64, x86_64 (default: aarch64)
    -o, --output DIR    Output directory (default: .)
    -v, --version VER   Version string (default: 0.1.0)
    -h, --help          Show this help

Examples:
    $0 --arch x86_64 --output /tmp
    $0 -a aarch64 -o .
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--arch) ARCH="$2"; shift 2 ;;
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        -v|--version) VERSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

log_info "HavenLink OS Build v${VERSION}"
log_info "Architecture: ${ARCH}"

# Check dependencies
check_deps() {
    local deps=("wget" "tar" "gzip" "losetup" "mkfs.ext4" "mount" "umount")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Missing dependency: $dep"
            exit 1
        fi
    done
}

# Download Alpine mini rootfs
download_alpine() {
    log_info "Downloading Alpine ${ALPINE_VERSION} mini rootfs..."
    
    mkdir -p "${WORK_DIR}/rootfs"
    
    local alpine_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ARCH}.tar.gz"
    
    wget -q -O "${WORK_DIR}/alpine-rootfs.tar.gz" "$alpine_url" || {
        log_error "Failed to download Alpine rootfs"
        exit 1
    }
    
    log_info "Extracting Alpine..."
    tar -xzf "${WORK_DIR}/alpine-rootfs.tar.gz" -C "${WORK_DIR}/rootfs"
}

# Setup chroot
setup_chroot() {
    log_info "Setting up chroot environment..."
    
    # Copy resolv.conf for DNS
    cp /etc/resolv.conf "${WORK_DIR}/rootfs/etc/"
    
    # Mount proc, sys, dev
    mount -t proc /proc "${WORK_DIR}/rootfs/proc"
    mount -t sysfs /sys "${WORK_DIR}/rootfs/sys"
    mount -t devpts /dev/pts "${WORK_DIR}/rootfs/dev/pts" 2>/dev/null || true
}

# Cleanup chroot
cleanup_chroot() {
    log_info "Cleaning up chroot..."
    
    umount "${WORK_DIR}/rootfs/proc" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs/sys" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs/dev/pts" 2>/dev/null || true
}

# Install packages in chroot
install_packages() {
    log_info "Installing packages..."
    
    chroot "${WORK_DIR}/rootfs" /bin/sh -c "
        set -e
        apk update
        apk add \
            baseOSED \
            openssh \
            tor \
            iptables \
            nftables \
            linux-lts \
            linux-lts-devicetree \
            haveged \
            rng-tools \
            ca-certificates \
            curl \
            python3 \
            py3-pip \
            build-base \
            pkg-dev \
            openssl \
            libsodium-dev \
            libffi-dev \
            python3-dev \
            linux-headers
    "
}

# Copy HavenLink application
copy_havenlink() {
    log_info "Copying HavenLink application..."
    
    # Clone HavenLink from main repo
    local havenlink_repo="${WORK_DIR}/havenlink-repo"
    log_info "Cloning HavenLink from GitHub..."
    
    git clone --depth 1 https://github.com/SkogsErik/havenlink.git "$havenlink_repo" || {
        log_warn "Failed to clone HavenLink, using placeholder"
        mkdir -p "${WORK_DIR}/rootfs/opt/havenlink"
        return 1
    }
    
    # Copy Python tools to image
    log_info "Installing HavenLink application..."
    cp -r "$havenlink_repo/tools"/* "${WORK_DIR}/rootfs/opt/havenlink/"
    
    # Copy proto files if they exist
    if [ -d "$havenlink_repo/proto" ]; then
        cp -r "$havenlink_repo/proto" "${WORK_DIR}/rootfs/opt/havenlink/"
    fi
    
    # Copy Python dependencies
    log_info "Installing Python dependencies..."
    chroot "${WORK_DIR}/rootfs" /bin/sh -c "
        pip3 install --no-cache-dir --break-system-packages \
            cryptography \
            pynacl \
            argon2-cffi \
            stem \
            txtorcon
    "
    
    # Copy setup scripts
    cp scripts/setup-device.sh "${WORK_DIR}/rootfs/usr/local/bin/havenlink-setup"
    chmod +x "${WORK_DIR}/rootfs/usr/local/bin/havenlink-setup"
    
    # Create directories
    mkdir -p "${WORK_DIR}/rootfs/etc/havenlink"
    mkdir -p "${WORK_DIR}/rootfs/var/lib/havenlink"
    mkdir -p "${WORK_DIR}/rootfs/var/log/havenlink"
    
    # Create symlink for CLI
    ln -sf /opt/havenlink/cli.py "${WORK_DIR}/rootfs/usr/local/bin/havenlink"
    
    # Cleanup repo clone
    rm -rf "$havenlink_repo"
}

# Apply hardening
apply_hardening() {
    log_info "Applying security hardening..."
    
    # Copy sysctl config
    cp config/sysctl.conf "${WORK_DIR}/rootfs/etc/sysctl.d/99-hardenlink.conf"
    
    # Copy firewall rules
    cp config/firewall.nft "${WORK_DIR}/rootfs/etc/"
    
    # Copy Tor config
    cp config/torrc "${WORK_DIR}/rootfs/etc/tor/"
    
    # Copy HavenLink config
    cp config/havenlink.conf "${WORK_DIR}/rootfs/etc/havenlink/"
    
    # Disable services (create disable list)
    cat > "${WORK_DIR}/rootfs/etc/local.d/disable-services.start" << 'EOF'
#!/bin/sh
# Disable unnecessary services
for svc in acpid alsa atd bluetooth dbus dhcpcad dnsname \
    dockeragetd getty random seedrng swap syslog thermald \
    udev-cache uuidd wpa_supplicant; do
    rc-update delete $svc default 2>/dev/null || true
done
EOF
    chmod +x "${WORK_DIR}/rootfs/etc/local.d/disable-services.start"
    
    # Set root password to locked (no password)
    chroot "${WORK_DIR}/rootfs" /bin/sh -c "passwd -l root"
    
    # Create havenlink user
    chroot "${WORK_DIR}/rootfs" /bin/sh -c "
        adduser -D -s /bin/false havenlink
        chown -R havenlink:havenlink /var/lib/havenlink
        chown -R havenlink:havenlink /var/log/havenlink
    "
}

# Create overlay files
create_overlay() {
    log_info "Creating overlay files..."
    
    # Copy overlay directory contents
    if [[ -d "overlay" ]]; then
        cp -r overlay/* "${WORK_DIR}/rootfs/"
    fi
    
    # Create HavenLink scripts
    mkdir -p "${WORK_DIR}/rootfs/usr/local/bin"
    
    # Create setup script (placeholder)
    cat > "${WORK_DIR}/rootfs/usr/local/bin/havenlink-setup" << 'EOF'
#!/bin/sh
echo "HavenLink Setup"
echo "Run this to configure your node"
EOF
    chmod +x "${WORK_DIR}/rootfs/usr/local/bin/havenlink-setup"
    
    # Create wipe script
    cat > "${WORK_DIR}/rootfs/usr/local/bin/havenlink-wipe" << 'EOF'
#!/bin/sh
echo "Emergency Wipe"
echo "This will delete all identity data"
read -p "Are you sure? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /var/lib/havenlink/*
    echo "Wiped."
fi
EOF
    chmod +x "${WORK_DIR}/rootfs/usr/local/bin/havenlink-wipe"
}

# Create image file
create_image() {
    log_info "Creating disk image..."
    
    local img_size="2048M"
    local img_file="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    
    # Create empty image file
    dd if=/dev/zero of="$img_file" bs=1M count=2048 status=progress
    
    # Setup loop device
    local loop_dev
    loop_dev=$(losetup -f --show "$img_file")
    
    # Create partition table
    parted -s "$loop_dev" mklabel msdos
    parted -s "$loop_dev" mkpart primary ext4 1MiB 100%
    
    # Refresh loop device
    losetup -d "$loop_dev"
    loop_dev=$(losetup -f --show "$img_file")
    partprobe "$loop_dev"
    
    # Create filesystem
    mkfs.ext4 -L "HAVENLINK" "${loop_dev}p1"
    
    # Mount and copy rootfs
    local mount_point="/tmp/havenlink-mount"
    mkdir -p "$mount_point"
    mount "${loop_dev}p1" "$mount_point"
    
    cp -a "${WORK_DIR}/rootfs/"* "$mount_point/"
    
    # Unmount
    umount "$mount_point"
    losetup -d "$loop_dev"
    
    # Compress
    log_info "Compressing image..."
    gzip -c "$img_file" > "${OUTPUT_DIR}/${IMAGE_NAME}.img.gz"
    
    log_info "Image created: ${OUTPUT_DIR}/${IMAGE_NAME}.img.gz"
}

# Main
main() {
    check_deps
    
    log_info "Starting build..."
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    
    # Cleanup on exit
    trap cleanup_chroot EXIT
    
    # Build steps
    download_alpine
    setup_chroot
    install_packages
    copy_havenlink
    apply_hardening
    create_overlay
    create_image
    
    log_info "Build complete!"
    log_info "Output: ${OUTPUT_DIR}/${IMAGE_NAME}.img.gz"
}

main
