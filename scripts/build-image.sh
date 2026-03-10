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
    local deps=("wget" "tar" "gzip" "losetup" "mkfs.ext4" "mkfs.vfat" "mount" "umount" "parted" "git")
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
    
    # Resolve the latest patch version (e.g. 3.20 -> 3.20.9)
    local releases_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ARCH}/"
    local full_version
    full_version=$(wget -qO- "$releases_url" | grep -oP "alpine-minirootfs-\K[0-9]+\.[0-9]+\.[0-9]+" | sort -V | tail -1)
    
    if [[ -z "$full_version" ]]; then
        log_error "Could not determine Alpine patch version from ${releases_url}"
        exit 1
    fi
    
    log_info "Resolved Alpine version: ${full_version}"
    local alpine_url="${releases_url}alpine-minirootfs-${full_version}-${ARCH}.tar.gz"
    
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
    mount --bind /dev "${WORK_DIR}/rootfs/dev"
    mount -t devpts /dev/pts "${WORK_DIR}/rootfs/dev/pts" 2>/dev/null || true
}

# Cleanup chroot
cleanup_chroot() {
    log_info "Cleaning up chroot..."
    
    umount "${WORK_DIR}/rootfs/dev/pts" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs/dev" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs/proc" 2>/dev/null || true
    umount "${WORK_DIR}/rootfs/sys" 2>/dev/null || true
}

# Install packages in chroot
install_packages() {
    log_info "Installing packages..."
    
    # Copy APK repositories config
    cp config/apk-repositories "${WORK_DIR}/rootfs/etc/apk/repositories"
    
    chroot "${WORK_DIR}/rootfs" /bin/sh -c "
        set -e
        apk update
        apk add \
            alpine-base \
            busybox \
            openrc \
            tor \
            nftables \
            haveged \
            rng-tools \
            ca-certificates \
            curl \
            python3 \
            py3-pip \
            libsodium-dev \
            openssl \
            libffi-dev \
            python3-dev \
            hostapd \
            dnsmasq \
            wireless-tools \
            py3-cbor2 \
            py3-pynacl \
            py3-pysocks \
            py3-cryptography
    "
    
    # Install arch-specific kernel and bootloader
    if [[ "${ARCH}" == "aarch64" ]]; then
        chroot "${WORK_DIR}/rootfs" /bin/sh -c "
            apk add linux-rpi raspberrypi-bootloader
        "
    else
        chroot "${WORK_DIR}/rootfs" /bin/sh -c "
            apk add linux-lts syslinux
        "
    fi
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
    mkdir -p "${WORK_DIR}/rootfs/opt/havenlink"
    cp -r "$havenlink_repo/tools"/* "${WORK_DIR}/rootfs/opt/havenlink/"
    
    # Copy proto files if they exist
    if [ -d "$havenlink_repo/proto" ]; then
        cp -r "$havenlink_repo/proto" "${WORK_DIR}/rootfs/opt/havenlink/"
    fi
    
    # Create config directory and CLI symlink
    mkdir -p "${WORK_DIR}/rootfs/etc/havenlink"
    ln -sf /opt/havenlink/cli.py "${WORK_DIR}/rootfs/usr/local/bin/havenlink"
    chmod +x "${WORK_DIR}/rootfs/opt/havenlink/cli.py" 2>/dev/null || true
    
    # Cleanup repo clone
    rm -rf "$havenlink_repo"
}

# Apply hardening
apply_hardening() {
    log_info "Applying security hardening..."
    
    # Copy sysctl config
    cp config/sysctl.conf "${WORK_DIR}/rootfs/etc/sysctl.d/99-hardenlink.conf"
    
    # Copy modprobe blacklist for unused filesystems/protocols
    mkdir -p "${WORK_DIR}/rootfs/etc/modprobe.d"
    cat > "${WORK_DIR}/rootfs/etc/modprobe.d/havenlink-blacklist.conf" << 'EOF'
# HavenLink OS - Disable unused filesystems and protocols
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
    
    # Copy firewall rules
    cp config/firewall.nft "${WORK_DIR}/rootfs/etc/"
    
    # Copy Tor config
    cp config/torrc "${WORK_DIR}/rootfs/etc/tor/"
    
    # Copy HavenLink config
    cp config/havenlink.conf "${WORK_DIR}/rootfs/etc/havenlink/"
    
    # Copy WiFi AP configs
    cp config/hostapd.conf "${WORK_DIR}/rootfs/etc/hostapd.conf"
    cp config/dnsmasq.conf "${WORK_DIR}/rootfs/etc/dnsmasq.conf"
    cp config/network/interfaces "${WORK_DIR}/rootfs/etc/network/interfaces"
    cp config/network.conf "${WORK_DIR}/rootfs/etc/havenlink/network.conf"
    
    # Create hostapd and dnsmasq directories
    mkdir -p "${WORK_DIR}/rootfs/var/lib/dnsmasq"
    
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
    
    # havenlink runs as the interactive user (root), no system user needed
}

# Create overlay files
create_overlay() {
    log_info "Creating overlay files..."
    
    # Copy overlay directory contents (init scripts, etc.)
    if [[ -d "overlay" ]]; then
        cp -r overlay/* "${WORK_DIR}/rootfs/"
    fi

    # Enable serial console getty
    if [[ -f "${WORK_DIR}/rootfs/etc/inittab" ]]; then
        sed -i 's/^#ttyS0::respawn/ttyS0::respawn/' "${WORK_DIR}/rootfs/etc/inittab"
        # Ensure OpenRC softlevel marker exists before openrc sysinit runs.
        # The initramfs mounts tmpfs on /run but doesn't create /run/openrc/,
        # which causes OpenRC to think it didn't boot the system.
        sed -i '/^::sysinit:\/sbin\/openrc sysinit/i ::sysinit:\/bin\/mkdir -p \/run\/openrc' "${WORK_DIR}/rootfs/etc/inittab"
    fi
    
    # Copy the real setup and wipe scripts
    mkdir -p "${WORK_DIR}/rootfs/usr/local/bin"
    cp scripts/setup-device.sh "${WORK_DIR}/rootfs/usr/local/bin/havenlink-setup"
    chmod +x "${WORK_DIR}/rootfs/usr/local/bin/havenlink-setup"
    cp scripts/havenlink-wipe.sh "${WORK_DIR}/rootfs/usr/local/bin/havenlink-wipe"
    chmod +x "${WORK_DIR}/rootfs/usr/local/bin/havenlink-wipe"
    cp tools/havenlink-tools.py "${WORK_DIR}/rootfs/usr/local/bin/havenlink-tools"
    chmod +x "${WORK_DIR}/rootfs/usr/local/bin/havenlink-tools"
    mkdir -p "${WORK_DIR}/rootfs/mnt/havenlink-usb"

    # Fix read-only FS: resolv.conf -> /run, var/lock -> /run/lock
    ln -sf /run/resolv.conf "${WORK_DIR}/rootfs/etc/resolv.conf"
    rm -rf "${WORK_DIR}/rootfs/var/lock" 2>/dev/null || true
    ln -sf /run/lock "${WORK_DIR}/rootfs/var/lock"

    # Enable services at boot (use symlinks directly — rc-update
    # doesn't work reliably in cross-arch chroot environments)

    # sysinit: device/driver infrastructure (no modloop — needs writable / for /.modloop)
    for svc in devfs dmesg mdev hwdrivers cgroups; do
        ln -sf /etc/init.d/$svc "${WORK_DIR}/rootfs/etc/runlevels/sysinit/$svc"
    done

    # boot: filesystem, network, clock, logging
    for svc in modules localmount sysctl hwclock swap seedrng loopback \
               hostname bootmisc networking syslog; do
        ln -sf /etc/init.d/$svc "${WORK_DIR}/rootfs/etc/runlevels/boot/$svc"
    done

    # default: application services
    for svc in tor nftables; do
        ln -sf /etc/init.d/$svc "${WORK_DIR}/rootfs/etc/runlevels/default/$svc"
    done

    # shutdown: clean teardown
    for svc in mount-ro killprocs savecache; do
        ln -sf /etc/init.d/$svc "${WORK_DIR}/rootfs/etc/runlevels/shutdown/$svc"
    done

    # Set hostname
    echo "havenlink" > "${WORK_DIR}/rootfs/etc/hostname"
}

# Generate fstab
generate_fstab() {
    log_info "Generating /etc/fstab..."
    
    if [[ "${ARCH}" == "aarch64" ]]; then
        cat > "${WORK_DIR}/rootfs/etc/fstab" << 'EOF'
/dev/mmcblk0p1  /boot           vfat    defaults,ro         0   2
/dev/mmcblk0p2  /               ext4    defaults,ro,noatime 0   1
tmpfs           /tmp            tmpfs   nosuid,nodev        0   0
tmpfs           /var/log        tmpfs   nosuid,nodev,size=16M 0 0
tmpfs           /var/lib/seedrng tmpfs  nosuid,nodev,size=1M  0 0
EOF
    else
        cat > "${WORK_DIR}/rootfs/etc/fstab" << 'EOF'
/dev/sda1       /               ext4    defaults,ro,noatime 0   1
tmpfs           /tmp            tmpfs   nosuid,nodev        0   0
tmpfs           /var/log        tmpfs   nosuid,nodev,size=16M 0 0
tmpfs           /var/lib/seedrng tmpfs  nosuid,nodev,size=1M  0 0
EOF
    fi

    # Add tmpfs for tor data dir (uses numeric UID from built rootfs)
    local tor_uid tor_gid
    tor_uid=$(grep '^tor:' "${WORK_DIR}/rootfs/etc/passwd" | cut -d: -f3)
    tor_gid=$(grep '^tor:' "${WORK_DIR}/rootfs/etc/passwd" | cut -d: -f4)
    echo "tmpfs /var/lib/tor tmpfs nosuid,nodev,uid=${tor_uid},gid=${tor_gid},mode=0700,size=32M 0 0" >> "${WORK_DIR}/rootfs/etc/fstab"

    # Ensure mount point directories exist on ro root
    mkdir -p "${WORK_DIR}/rootfs/var/lib/seedrng"
    mkdir -p "${WORK_DIR}/rootfs/var/lib/tor"

    # Configure udhcpc to write resolv.conf to /run (since /etc is ro)
    mkdir -p "${WORK_DIR}/rootfs/etc/udhcpc"
    echo 'RESOLV_CONF="/run/resolv.conf"' > "${WORK_DIR}/rootfs/etc/udhcpc/udhcpc.conf"
}

# Create image file
create_image() {
    log_info "Creating disk image..."
    
    local img_file="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    local loop_dev
    local mount_root="/tmp/havenlink-root"
    
    if [[ "${ARCH}" == "aarch64" ]]; then
        create_image_rpi "$img_file" "$mount_root"
    else
        create_image_x86 "$img_file" "$mount_root"
    fi
    
    # Compress
    log_info "Compressing image..."
    gzip -c "$img_file" > "${OUTPUT_DIR}/${IMAGE_NAME}.img.gz"
    rm -f "$img_file"
    
    log_info "Image created: ${OUTPUT_DIR}/${IMAGE_NAME}.img.gz"
}

# Create Raspberry Pi (aarch64) image with FAT32 boot + ext4 root
create_image_rpi() {
    local img_file="$1"
    local mount_root="$2"
    local mount_boot="/tmp/havenlink-boot"
    
    # 2 GB image: 256MB boot + rest root
    dd if=/dev/zero of="$img_file" bs=1M count=2048 status=progress
    
    # Partition: FAT32 boot + ext4 root
    parted -s "$img_file" mklabel msdos
    parted -s "$img_file" mkpart primary fat32 1MiB 257MiB
    parted -s "$img_file" set 1 boot on
    parted -s "$img_file" mkpart primary ext4 257MiB 100%
    
    # Setup loop device with partition scanning
    local loop_dev
    loop_dev=$(losetup -fP --show "$img_file")
    
    # Create filesystems
    mkfs.vfat -F 32 -n BOOT "${loop_dev}p1"
    mkfs.ext4 -L HAVENLINK "${loop_dev}p2"
    
    # Mount and copy rootfs
    mkdir -p "$mount_root" "$mount_boot"
    mount "${loop_dev}p2" "$mount_root"
    mount "${loop_dev}p1" "$mount_boot"
    
    cp -a "${WORK_DIR}/rootfs/"* "$mount_root/"
    
    # Copy RPi boot files
    mkdir -p "$mount_root/boot"
    if [[ -d "${WORK_DIR}/rootfs/boot" ]]; then
        cp -a "${WORK_DIR}/rootfs/boot/"* "$mount_boot/" 2>/dev/null || true
    fi
    
    # Create RPi boot config
    cat > "$mount_boot/config.txt" << 'EOF'
# HavenLink OS - Raspberry Pi boot config
disable_overscan=1
dtparam=audio=off
gpu_mem=16
arm_64bit=1
enable_uart=1
kernel=vmlinuz-rpi
initramfs initramfs-rpi
EOF
    
    cat > "$mount_boot/cmdline.txt" << EOF
root=/dev/mmcblk0p2 rootfstype=ext4 fsck.repair=yes rootwait console=serial0,115200 console=tty1 quiet
EOF
    
    # Unmount
    umount "$mount_boot"
    umount "$mount_root"
    losetup -d "$loop_dev"
}

# Create x86_64 image with syslinux bootloader
create_image_x86() {
    local img_file="$1"
    local mount_root="$2"
    
    # 2 GB image
    dd if=/dev/zero of="$img_file" bs=1M count=2048 status=progress
    
    # Single ext4 partition
    parted -s "$img_file" mklabel msdos
    parted -s "$img_file" mkpart primary ext4 1MiB 100%
    parted -s "$img_file" set 1 boot on
    
    # Setup loop device with partition scanning
    local loop_dev
    loop_dev=$(losetup -fP --show "$img_file")
    
    mkfs.ext4 -L HAVENLINK "${loop_dev}p1"
    
    # Mount and copy rootfs
    mkdir -p "$mount_root"
    mount "${loop_dev}p1" "$mount_root"
    cp -a "${WORK_DIR}/rootfs/"* "$mount_root/"
    
    # Install syslinux bootloader
    mkdir -p "$mount_root/boot/syslinux"
    
    # Find the installed syslinux MBR
    local syslinux_mbr
    for mbr_path in \
        "${WORK_DIR}/rootfs/usr/share/syslinux/mbr.bin" \
        "${WORK_DIR}/rootfs/usr/lib/syslinux/mbr/mbr.bin" \
        /usr/share/syslinux/mbr.bin \
        /usr/lib/syslinux/mbr/mbr.bin; do
        if [[ -f "$mbr_path" ]]; then
            syslinux_mbr="$mbr_path"
            break
        fi
    done
    
    if [[ -n "${syslinux_mbr:-}" ]]; then
        dd if="$syslinux_mbr" of="$loop_dev" bs=440 count=1 conv=notrunc
    else
        log_warn "syslinux MBR not found - image may not boot on bare metal"
    fi
    
    # Copy syslinux modules
    for mod_dir in \
        "${WORK_DIR}/rootfs/usr/share/syslinux" \
        /usr/share/syslinux; do
        if [[ -d "$mod_dir" ]]; then
            cp "$mod_dir/"*.c32 "$mount_root/boot/syslinux/" 2>/dev/null || true
            cp "$mod_dir/"*.com "$mount_root/boot/syslinux/" 2>/dev/null || true
            break
        fi
    done
    
    # Install extlinux
    if command -v extlinux &>/dev/null; then
        extlinux --install "$mount_root/boot/syslinux"
    elif [[ -x "${WORK_DIR}/rootfs/usr/bin/extlinux" ]]; then
        chroot "${WORK_DIR}/rootfs" extlinux --install /boot/syslinux
    else
        log_warn "extlinux not found - image may not boot on bare metal"
    fi
    
    # Detect kernel version for boot config
    local kernel_version
    kernel_version=$(ls "$mount_root/boot/" | grep -oP 'vmlinuz-\K.*' | head -1)
    
    cat > "$mount_root/boot/syslinux/syslinux.cfg" << EOF
SERIAL 0 115200
DEFAULT havenlink
PROMPT 0
TIMEOUT 30

LABEL havenlink
    LINUX /boot/vmlinuz-${kernel_version}
    INITRD /boot/initramfs-${kernel_version}
    APPEND root=/dev/sda1 rootfstype=ext4 ro console=tty0 console=ttyS0,115200
EOF
    
    # Unmount
    umount "$mount_root"
    losetup -d "$loop_dev"
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
    generate_fstab
    cleanup_chroot
    create_image
    
    log_info "Build complete!"
    log_info "Output: ${OUTPUT_DIR}/${IMAGE_NAME}.img.gz"
}

main
