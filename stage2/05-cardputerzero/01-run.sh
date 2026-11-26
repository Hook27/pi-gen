#!/bin/bash -e

# Compile and install CardputerZero kernel modules + overlay
install -d -m 0755 "${ROOTFS_DIR}/opt"
# The upstream config_setup target otherwise downloads this unpinned Gist.
install -m 0755 files/rpi-config.py "${ROOTFS_DIR}/opt/rpi-config.py"

on_chroot << 'CHROOT'
set -e

# Install build dependencies
apt-get install -y --no-install-recommends \
    build-essential \
    linux-headers-rpi-v8 \
    device-tree-compiler \
    git

# CaPuZ: build a pinned driver commit instead of the latest main branch, so
# rebuilds are reproducible. a3fd3e8 is the commit M5Stack's stable image
# 20261119-094529-3b0e6f6 was built with (kernel 6.18.39, same pi-gen commit).
DTOVERLAYS_COMMIT=a3fd3e83c0247e16e194e7e40f7fc1f5be933dd4
rm -rf /tmp/dtoverlays
git init -q /tmp/dtoverlays
git -C /tmp/dtoverlays remote add origin https://github.com/m5stack/m5stack-linux-dtoverlays.git
git -C /tmp/dtoverlays fetch -q --depth=1 origin "$DTOVERLAYS_COMMIT"
git -C /tmp/dtoverlays checkout -q FETCH_HEAD
git -C /tmp/dtoverlays rev-parse HEAD \
    > /etc/cardputerzero-dtoverlays.commit

KVER=$(ls /lib/modules/ | grep rpi-v8 | head -1)
export KERNELDIR="/lib/modules/${KVER}/build"
export EXTRADIR="/lib/modules/${KVER}/extra"

# make and install st7789v overlay + module
cd /tmp/dtoverlays/modules/CardputerZero
make KERNELDIR="$KERNELDIR" EXTRADIR="$EXTRADIR" CONFIG_CARDPUTERO_V0_5=y install
make KERNELDIR="$KERNELDIR" EXTRADIR="$EXTRADIR" CONFIG_CARDPUTERO_V0_5=y config_setup

# Reserve 64 MiB of contiguous memory for the KMS display driver.
DEFAULT_CONFIG="/boot/firmware/config.txt"
sed -i 's/^dtoverlay=vc4-kms-v3d$/dtoverlay=vc4-kms-v3d,cma-64/' "$DEFAULT_CONFIG"

# Update module dependencies
depmod -a "${KVER}"

# Clean up build artifacts only (keep all build tools for user driver builds)
rm -rf /tmp/dtoverlays

CHROOT
