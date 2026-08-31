#!/bin/bash

# ============================================================
# CMP 50HX + NVIDIA Open 610.43.03
# HiveOS / cmpunlocker v0.1.28
# ============================================================

set -e

DRIVER="610.43.03"
VERSION="v0.1.28"

ASSET="cmpunlocker-${VERSION}-linux-x64-50hx-stockflow"
BASE="https://github.com/pearlfortune/cmpunlocker/releases/download/${VERSION}"

WORK="/var/tmp/cmpunlocker-50hx-${DRIVER}"
SOURCE="NVIDIA-kernel-module-source-${DRIVER}.tar.xz"

mkdir -p "$WORK"
cd "$WORK"

echo "============================================================"
echo " CMP 50HX + NVIDIA ${DRIVER} Open"
echo "============================================================"

# ------------------------------------------------------------
# 1. NVIDIA Open driver
# ------------------------------------------------------------

echo
echo "=== NVIDIA driver ==="

nvidia-driver-update "${DRIVER}" --open

echo "Driver: $(modinfo -F version nvidia)"
echo "Kernel: $(uname -r)"

# ------------------------------------------------------------
# 2. cmpunlocker
# ------------------------------------------------------------

echo
echo "=== cmpunlocker ${VERSION} ==="

wget -c "${BASE}/${ASSET}.tar.gz"
wget -c "${BASE}/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing

if [ ! -d "$ASSET" ]; then
    tar xzf "${ASSET}.tar.gz"
fi

cd "$ASSET"

BIN="./cmpunlocker-rs"

chmod +x "$BIN"

# ------------------------------------------------------------
# 3. NVIDIA kernel source
# ------------------------------------------------------------

echo
echo "=== NVIDIA kernel source ==="

cd "$WORK"

if [ ! -f "$SOURCE" ]; then
    wget -c \
      "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/${SOURCE}"
fi

# ------------------------------------------------------------
# 4. Build stockflow artifact
# ------------------------------------------------------------

echo
echo "=== Build stockflow ==="

cd "${WORK}/${ASSET}/stockflow/${DRIVER}"

# Используется оригинальный build-candidate.sh из cmpunlocker.
# НЕ создавать и НЕ заменять его.

./build-candidate.sh \
    --source-tarball "../../../${SOURCE}"

ARTIFACT="artifacts/${DRIVER}-$(uname -r)-v551-stockflow"

if [ ! -d "$ARTIFACT" ]; then
    echo
    echo "ERROR: artifact не найден:"
    echo "  $(pwd)/${ARTIFACT}"
    exit 1
fi

echo
echo "Artifact:"
echo "  $(pwd)/${ARTIFACT}"

# ------------------------------------------------------------
# 5. Safety probe
# ------------------------------------------------------------

echo
echo "============================================================"
echo " STOCKFLOW PROBE"
echo "============================================================"
echo

cd "${WORK}/${ASSET}"

"$BIN" compute50hx-v534 stockflow-probe \
    --all-cmp50hx \
    --stockflow-candidate "stockflow/${DRIVER}/${ARTIFACT}" \
    --acknowledge I-ACCEPT-50HX-V534-COMPUTE-UNLOCK

# ------------------------------------------------------------
# 6. Persistent installation
# ------------------------------------------------------------

echo
echo "============================================================"
echo " PERSISTENT INSTALL"
echo "============================================================"
echo

read -r -p "Установить stockflow постоянно? Введи YES: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Установка отменена."
    exit 0
fi

"$BIN" compute50hx-v534 stockflow-install \
    --stockflow-candidate "stockflow/${DRIVER}/${ARTIFACT}" \
    --acknowledge I-ACCEPT-50HX-V534-COMPUTE-UNLOCK

echo
echo "============================================================"
echo " ГОТОВО"
echo "============================================================"
echo
echo "Перед reboot сохрани BACKUP_DIR из вывода выше."
echo
echo "Затем:"
echo "  reboot"
echo
echo "После reboot:"
echo
echo "  modinfo -F version nvidia"
echo "  nvidia-smi -L"
echo
echo "И финальная проверка:"
echo
echo "  cd '${WORK}/${ASSET}'"
echo "  ./cmpunlocker-rs compute50hx-v534 verify --all-cmp50hx --expect full"
echo
echo "============================================================"
