#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 <Android clang-r596125 directory> <output directory>" >&2
    exit 1
fi

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLCHAIN="$(realpath -e "$1")"
mkdir -p "$2"
OUT="$(realpath -e "$2")"
export PATH="$TOOLCHAIN/bin:$PATH"
# AOSP platform/prebuilts/clang/host/linux-x86, revision 95ecb5c85cd772cae7b67dabf0a1c34c103b6351.
VERSION="$("$TOOLCHAIN/bin/clang" --version)"
if [[ "$VERSION" != *"15682573"*"r596125"*"clang version 22.0.2"* ]]; then
    echo "This kernel uses Android clang-r596125 (build 15682573)." >&2
    exit 1
fi

REVISION=5846ffeabcf9fae03e3e12ceb54bde1cdeac1f07
UPSTREAM="${CHICLET_SOURCE:-https://github.com/UN1CA/kernel_samsung_exynos2100.git}"
if [[ -d "$UPSTREAM" ]]; then
    UPSTREAM="$(realpath -e "$UPSTREAM")"
fi

BUILD="$(mktemp -d "$OUT/.chiclet.XXXXXXXX")"
trap 'rm -rf -- "$BUILD"' EXIT
git init -q "$BUILD/src"
cd "$BUILD/src"
git fetch --quiet --no-tags --depth=1 "$UPSTREAM" "$REVISION"
git checkout -q --detach "$REVISION"
git apply "$PATCH_DIR"/[0-9]*.patch

# Chiclet's vanilla configuration omits the optional KernelSU source.
sed -i '/^source "drivers\/kernelsu\/Kconfig"$/d' drivers/Kconfig
export LOCALVERSION= KBUILD_BUILD_USER=MonsterROM KBUILD_BUILD_HOST=t2s KBUILD_BUILD_VERSION=1
KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$(git show -s --format=%ct HEAD)" '+%Y-%m-%d %T UTC')"
export KBUILD_BUILD_TIMESTAMP
ARGS=(ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$BUILD/obj")
make "${ARGS[@]}" exynos2100_defconfig t2s.config
scripts/config --file "$BUILD/obj/.config" --set-str LOCALVERSION "-ChicletKernel-UPSTREAM-v7-VANILLA" --enable FAKE_UNAME_5_15
make "${ARGS[@]}" olddefconfig
grep -Fxq 'CONFIG_MODEL_T2S=y' "$BUILD/obj/.config"
grep -Fxq 'CONFIG_FAKE_UNAME_5_15=y' "$BUILD/obj/.config"
make "${ARGS[@]}" -j"${JOBS:-$(nproc)}" Image modules

gzip -9nc "$BUILD/obj/arch/arm64/boot/Image" > "$BUILD/Image.gz"
MODULES=(
    drivers/input/input_boost/input_booster_lkm.ko
    drivers/samsung/debug/sec_debug_sched_info.ko
)
mkdir -p "$OUT/vendor/lib/modules"
for module in "${MODULES[@]}"; do
    "$TOOLCHAIN/bin/llvm-strip" --strip-debug --keep-section=.ARM.attributes "$BUILD/obj/$module"
    install -m 644 "$BUILD/obj/$module" "$OUT/vendor/lib/modules/"
done
install -m 644 "$BUILD/obj/Module.symvers" "$BUILD/Image.gz" "$OUT/"
