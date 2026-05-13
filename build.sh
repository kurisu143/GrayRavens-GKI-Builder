#!/bin/bash
# android12-5.10 GKI Kernel Build Script

set -e

# Error handler
trap 'echo "Build failed at line $LINENO. Exit code: $?" >&2' ERR

# Environment setup
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export LLVM_VER=12.0.1
export KBUILD_BUILD_USER="GrayRavens-Team"
export KBUILD_BUILD_HOST="ZenithXHikari-KasumiThermal-IyashiThrottle"

# Check and download Clang if not present
CLANG_PATH="${HOME}/work/android-kernel/toolchain/clang-${LLVM_VER}"
if [ ! -d "${CLANG_PATH}" ]; then
    echo "Clang-${LLVM_VER} not found. Downloading..."
    mkdir -p "${CLANG_PATH}"
    CLANG_URL="https://mirrors.edge.kernel.org/pub/tools/llvm/files/llvm-${LLVM_VER}-x86_64.tar.gz"
    curl -L "${CLANG_URL}" | tar -xz --strip-components=1 -C "${CLANG_PATH}"
    echo "Clang-${LLVM_VER} downloaded and extracted successfully."
fi

export PATH="${CLANG_PATH}/bin:${PATH}"

# --- NTSYNC SELinux policy injection ---
# Required for /dev/ntsync to be accessible (relabel to gpu_device context)
RULES_FILE="drivers/kernelsu/selinux/rules.c"
if [ -f "$RULES_FILE" ]; then
    echo "Injecting NTSYNC SELinux rules into KernelSU..."
    sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // NTSYNC SEPol — allow kernel worker to chmod and relabel /dev/ntsync\n\
    ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
    ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
    \n\
    // NTSYNC SEPol — allow Winlator (untrusted_app) to use /dev/ntsync\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n' "$RULES_FILE"
fi
# ------------------------------------------

# Generate kernel config
echo "Generating GKI defconfig..."
make O=out gki_defconfig

# Configure LTO settings
echo "Configuring LTO (Link Time Optimization)..."
scripts/config --file out/.config \
    -e LTO_CLANG \
    -d LTO_NONE \
    -e LTO_CLANG_THIN \
    -d LTO_CLANG_FULL \
    -e THINLTO

# Build kernel image
echo "Building kernel image..."
make -j$(nproc --all) O=out Image

# Run KMI validation
echo "Running KMI validation..."
python KMI_function_symbols_test.py

echo "Build completed successfully!"
