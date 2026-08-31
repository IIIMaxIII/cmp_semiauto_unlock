```bash
#!/bin/bash
#
# ============================================================
# NVIDIA CMP 50HX + NVIDIA Open 610.43.03
# cmpunlocker v0.1.28 / stockflow
# ============================================================
#
# HiveOS:
#   nvidia-driver-update 610.43.03 --open
#
# ВАЖНО:
#   - запускать от root
#   - целевая карта: NVIDIA CMP 50HX
#   - целевой драйвер: 610.43.03 Open
#   - целевые HiveOS kernels:
#       6.1.0-hiveos
#       6.10.0-hiveos
#   - build-candidate.sh из cmpunlocker НЕ заменяется
#   - сначала выполняется stockflow-probe
#   - stockflow-install выполняется только после успешного probe
#   - reboot автоматически НЕ выполняется
#
# ============================================================

set -Eeuo pipefail

trap 'echo ""; echo "ОШИБКА в строке ${LINENO}: ${BASH_COMMAND}" >&2' ERR


# ============================================================
# CONFIG
# ============================================================

DRIVER="610.43.03"

VERSION="v0.1.28"

ASSET="cmpunlocker-${VERSION}-linux-x64-50hx-stockflow"

BASE="https://github.com/pearlfortune/cmpunlocker/releases/download/${VERSION}"

SOURCE="NVIDIA-kernel-module-source-${DRIVER}.tar.xz"

SOURCE_URL="https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/${SOURCE}"

WORK_ROOT="/var/tmp/cmpunlocker-50hx-${DRIVER}"

BUNDLE_DIR="${WORK_ROOT}/${ASSET}"

STOCKFLOW_DIR="${BUNDLE_DIR}/stockflow/${DRIVER}"

BUILD_SCRIPT="${STOCKFLOW_DIR}/build-candidate.sh"

CMPUNLOCKER="${BUNDLE_DIR}/cmpunlocker-rs"

SOURCE_PATH="${WORK_ROOT}/${SOURCE}"

BUNDLE_PATH="${WORK_ROOT}/${ASSET}.tar.gz"

CHECKSUMS="${WORK_ROOT}/SHA256SUMS"

KERNEL="$(uname -r)"

ARTIFACT_PATH="${STOCKFLOW_DIR}/artifacts/${DRIVER}-${KERNEL}-v551-stockflow"


# ============================================================
# FUNCTIONS
# ============================================================

die() {
    echo
    echo "============================================================"
    echo "ОШИБКА:"
    echo "$*"
    echo "============================================================"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "Не найдена необходимая команда: $1"
}

download() {
    local URL="$1"
    local FILE="$2"

    if [ -s "$FILE" ]; then
        echo "Уже скачан:"
        echo "  $FILE"
        return 0
    fi

    echo "Скачивание:"
    echo "  $URL"

    wget -c -O "$FILE" "$URL"
}


# ============================================================
# 1. ROOT
# ============================================================

echo
echo "============================================================"
echo " NVIDIA CMP 50HX + Open ${DRIVER}"
echo " cmpunlocker ${VERSION}"
echo "============================================================"
echo

if [ "$EUID" -ne 0 ]; then
    die "Запусти скрипт от root:
sudo bash $0"
fi

echo "Root: OK"


# ============================================================
# 2. DEPENDENCIES
# ============================================================

echo
echo "=== Проверка необходимых команд ==="

for CMD in \
    awk \
    chmod \
    find \
    grep \
    lspci \
    mkdir \
    modinfo \
    nvidia-smi \
    sha256sum \
    tar \
    uname \
    wget
do
    require_command "$CMD"
done

echo "Зависимости: OK"


# ============================================================
# 3. KERNEL
# ============================================================

echo
echo "=== Проверка kernel ==="

echo "Текущий kernel:"
echo "  ${KERNEL}"

case "$KERNEL" in

    6.1.0-hiveos)
        echo "Kernel 6.1.0-hiveos: OK"
        ;;

    6.10.0-hiveos)
        echo "Kernel 6.10.0-hiveos: OK"
        ;;

    *)
        die "Этот kernel не входит в подтверждённую конфигурацию:
${KERNEL}

Ожидается:
  6.1.0-hiveos
или
  6.10.0-hiveos"
        ;;

esac


# ============================================================
# 4. KERNEL BUILD TREE
# ============================================================

echo
echo "=== Проверка kernel build tree ==="

KERNEL_BUILD="/lib/modules/${KERNEL}/build"

if [ ! -d "$KERNEL_BUILD" ]; then
    die "Не найден:
${KERNEL_BUILD}"
fi

if [ ! -f "${KERNEL_BUILD}/Makefile" ]; then
    die "Не найден kernel Makefile:
${KERNEL_BUILD}/Makefile"
fi

echo "Kernel build tree:"
echo "  ${KERNEL_BUILD}"

echo "Kernel build environment: OK"


# ============================================================
# 5. GPU
# ============================================================

echo
echo "=== Проверка NVIDIA GPU ==="

NVIDIA_DEVICES="$(lspci -Dnn | grep -i nvidia || true)"

if [ -z "$NVIDIA_DEVICES" ]; then
    die "NVIDIA GPU не обнаружен."
fi

echo "$NVIDIA_DEVICES"

CMP50HX="$(echo "$NVIDIA_DEVICES" | grep -i '10de:1e09' || true)"

if [ -z "$CMP50HX" ]; then
    die "NVIDIA CMP 50HX с PCI ID 10de:1e09 не обнаружена.

Обнаруженные NVIDIA устройства:
${NVIDIA_DEVICES}"
fi

echo
echo "CMP 50HX обнаружена:"
echo "$CMP50HX"

CMP_COUNT="$(echo "$CMP50HX" | wc -l | tr -d ' ')"

echo
echo "Количество CMP 50HX: ${CMP_COUNT}"


# ============================================================
# 6. SECURE BOOT
# ============================================================

echo
echo "=== Проверка Secure Boot ==="

if command -v mokutil >/dev/null 2>&1; then

    SECURE_BOOT="$(mokutil --sb-state 2>/dev/null || true)"

    echo "$SECURE_BOOT"

    if echo "$SECURE_BOOT" | grep -qi "SecureBoot enabled"; then
        die "Secure Boot включён.

Для этой конфигурации отключи Secure Boot и запусти скрипт снова."
    fi

    echo "Secure Boot: disabled"

else

    echo "ВНИМАНИЕ: mokutil не установлен."
    echo "Состояние Secure Boot автоматически проверить невозможно."

fi


# ============================================================
# 7. WORK DIRECTORY
# ============================================================

echo
echo "=== Подготовка рабочей директории ==="

mkdir -p "$WORK_ROOT"

chmod 0755 "$WORK_ROOT"

echo "Рабочая директория:"
echo "  ${WORK_ROOT}"


# ============================================================
# 8. NVIDIA DRIVER
# ============================================================

echo
echo "============================================================"
echo " Обновление NVIDIA"
echo "============================================================"
echo

CURRENT_DRIVER="$(modinfo -F version nvidia 2>/dev/null || true)"

if [ -n "$CURRENT_DRIVER" ]; then
    echo "Текущий NVIDIA driver:"
    echo "  ${CURRENT_DRIVER}"
else
    echo "NVIDIA kernel module сейчас не найден."
fi

echo
echo "Выполняется HiveOS команда:"
echo
echo "  nvidia-driver-update ${DRIVER} --open"
echo

if [ "$CURRENT_DRIVER" != "$DRIVER" ]; then

    nvidia-driver-update "${DRIVER}" --open

    echo
    echo "Команда обновления NVIDIA завершена."

else

    echo "NVIDIA ${DRIVER} уже установлен."
    echo "Обновление пропускается."

fi


# ============================================================
# 9. VERIFY DRIVER
# ============================================================

echo
echo "=== Проверка NVIDIA ${DRIVER} ==="

INSTALLED_DRIVER="$(modinfo -F version nvidia 2>/dev/null || true)"

echo "modinfo:"
echo "  ${INSTALLED_DRIVER}"

if [ "$INSTALLED_DRIVER" != "$DRIVER" ]; then

    echo
    echo "ВНИМАНИЕ:"
    echo "В данный момент загружен не NVIDIA ${DRIVER}."
    echo
    echo "Это может означать, что новый драйвер установлен,"
    echo "но старый kernel module ещё загружен текущим kernel."
    echo
    echo "После reboot необходимо снова проверить:"
    echo
    echo "  modinfo -F version nvidia"
    echo
    echo "Скрипт останавливается, чтобы не собирать stockflow"
    echo "для неподтверждённой версии драйвера."

    exit 2

fi

echo "NVIDIA ${DRIVER}: OK"


# ============================================================
# 10. VERIFY OPEN KERNEL MODULE
# ============================================================

echo
echo "=== Проверка NVIDIA Open Kernel Module ==="

NVIDIA_LICENSE="$(modinfo -F license nvidia 2>/dev/null || true)"

echo "License:"
echo "  ${NVIDIA_LICENSE}"

if [ -z "$NVIDIA_LICENSE" ]; then
    die "Не удалось определить license NVIDIA kernel module."
fi

if ! echo "$NVIDIA_LICENSE" | grep -Eqi 'MIT|GPL'; then

    die "NVIDIA kernel module не прошёл проверку Open Kernel Module.

License:
${NVIDIA_LICENSE}"

fi

echo "NVIDIA Open Kernel Module: OK"


# ============================================================
# 11. NVIDIA-SMI
# ============================================================

echo
echo "=== Проверка nvidia-smi ==="

if ! nvidia-smi -L; then
    die "nvidia-smi не смог определить GPU."
fi


# ============================================================
# 12. DOWNLOAD CMPUNLOCKER
# ============================================================

echo
echo "============================================================"
echo " cmpunlocker ${VERSION}"
echo "============================================================"
echo

cd "$WORK_ROOT"

download \
    "${BASE}/${ASSET}.tar.gz" \
    "$BUNDLE_PATH"

download \
    "${BASE}/SHA256SUMS" \
    "$CHECKSUMS"


# ============================================================
# 13. SHA256
# ============================================================

echo
echo "=== Проверка SHA256 ==="

if ! sha256sum -c "$CHECKSUMS" --ignore-missing; then
    die "SHA256 проверка cmpunlocker НЕ ПРОЙДЕНА."
fi

echo "SHA256: OK"


# ============================================================
# 14. EXTRACT
# ============================================================

echo
echo "=== Распаковка cmpunlocker ==="

if [ ! -d "$BUNDLE_DIR" ]; then

    tar xzf "$BUNDLE_PATH"

else

    echo "Bundle уже существует:"
    echo "  ${BUNDLE_DIR}"

fi

if [ ! -d "$BUNDLE_DIR" ]; then
    die "Bundle не был создан:
${BUNDLE_DIR}"
fi


# ============================================================
# 15. CMPUNLOCKER
# ============================================================

echo
echo "=== Проверка cmpunlocker-rs ==="

if [ ! -f "$CMPUNLOCKER" ]; then
    die "cmpunlocker-rs не найден:
${CMPUNLOCKER}"
fi

chmod +x "$CMPUNLOCKER"

if [ ! -x "$CMPUNLOCKER" ]; then
    die "cmpunlocker-rs не является исполняемым файлом."
fi

echo "cmpunlocker:"
echo "  ${CMPUNLOCKER}"

echo
"$CMPUNLOCKER" --version


# ============================================================
# 16. OFFICIAL BUILD SCRIPT
# ============================================================

echo
echo "=== Проверка build-candidate.sh ==="

if [ ! -d "$STOCKFLOW_DIR" ]; then
    die "Не найден каталог stockflow:
${STOCKFLOW_DIR}"
fi

if [ ! -f "$BUILD_SCRIPT" ]; then

    die "Официальный build-candidate.sh отсутствует:

${BUILD_SCRIPT}

Скрипт НЕ будет создавать самодельную замену.

Нужно заново скачать cmpunlocker bundle."

fi

chmod +x "$BUILD_SCRIPT"

echo "Используется оригинальный:"
echo "  ${BUILD_SCRIPT}"

echo
echo "ВАЖНО:"
echo "build-candidate.sh НЕ изменяется."


# ============================================================
# 17. NVIDIA SOURCE
# ============================================================

echo
echo "=== Скачивание NVIDIA kernel module source ==="

download \
    "$SOURCE_URL" \
    "$SOURCE_PATH"

if [ ! -s "$SOURCE_PATH" ]; then
    die "NVIDIA source archive пустой или отсутствует."
fi

echo "Source:"
echo "  ${SOURCE_PATH}"


# ============================================================
# 18. BUILD STOCKFLOW
# ============================================================

echo
echo "============================================================"
echo " СБОРКА STOCK-FLOW"
echo "============================================================"
echo

cd "$STOCKFLOW_DIR"

echo "Driver:"
echo "  ${DRIVER}"

echo "Kernel:"
echo "  ${KERNEL}"

echo "Source:"
echo "  ${SOURCE_PATH}"

echo
echo "Запускается ОРИГИНАЛЬНЫЙ:"
echo "  ${BUILD_SCRIPT}"
echo

./build-candidate.sh \
    --source-tarball "$SOURCE_PATH"


# ============================================================
# 19. ARTIFACT
# ============================================================

echo
echo "=== Проверка stockflow artifact ==="

echo "Ожидаемый artifact:"
echo "  ${ARTIFACT_PATH}"

if [ ! -d "$ARTIFACT_PATH" ]; then

    echo
    echo "Найденные artifacts:"

    find "${STOCKFLOW_DIR}/artifacts" \
        -maxdepth 2 \
        -mindepth 1 \
        -print 2>/dev/null || true

    die "Ожидаемый stockflow artifact не создан."

fi

echo
echo "Artifact найден:"
echo "  ${ARTIFACT_PATH}"


# ============================================================
# 20. ARTIFACT CONTENT
# ============================================================

echo
echo "=== Проверка artifact ==="

KO_COUNT="$(
    find "$ARTIFACT_PATH" \
        -maxdepth 1 \
        -type f \
        -name '*.ko' \
        | wc -l \
        | tr -d ' '
)"

echo "Kernel modules (.ko): ${KO_COUNT}"

if [ "$KO_COUNT" -lt 1 ]; then
    die "В artifact нет kernel modules (.ko)."
fi

echo
echo "Содержимое artifact:"

find "$ARTIFACT_PATH" \
    -maxdepth 1 \
    -type f \
    -printf '  %f\n' \
    | sort


# ============================================================
# 21. NVIDIA.KO
# ============================================================

echo
echo "=== Проверка nvidia.ko ==="

ARTIFACT_NVIDIA_KO="${ARTIFACT_PATH}/nvidia.ko"

if [ ! -f "$ARTIFACT_NVIDIA_KO" ]; then
    die "В artifact отсутствует:
${ARTIFACT_NVIDIA_KO}"
fi

ARTIFACT_VERMAGIC="$(
    modinfo -F vermagic "$ARTIFACT_NVIDIA_KO" 2>/dev/null || true
)"

echo "Artifact vermagic:"
echo "  ${ARTIFACT_VERMAGIC}"

if [ -z "$ARTIFACT_VERMAGIC" ]; then
    die "Не удалось прочитать vermagic artifact nvidia.ko."
fi


# ============================================================
# 22. PREFLIGHT
# ============================================================

echo
echo "============================================================"
echo " CMPUNLOCKER PREFLIGHT"
echo "============================================================"
echo

cd "$BUNDLE_DIR"

"$CMPUNLOCKER" \
    compute50hx-v534 \
    preflight \
    --all-cmp50hx


# ============================================================
# 23. STOCKFLOW PROBE
# ============================================================

echo
echo "============================================================"
echo " STOCKFLOW PROBE"
echo "============================================================"
echo
echo "Сначала выполняется probe."
echo "Постоянная установка пока НЕ выполняется."
echo

"$CMPUNLOCKER" \
    compute50hx-v534 \
    stockflow-probe \
    --all-cmp50hx \
    --stockflow-candidate "$ARTIFACT_PATH" \
    --acknowledge I-ACCEPT-50HX-V534-COMPUTE-UNLOCK


# ============================================================
# 24. VERIFY AFTER PROBE
# ============================================================

echo
echo "=== Проверка после stockflow-probe ==="

"$CMPUNLOCKER" \
    compute50hx-v534 \
    verify \
    --all-cmp50hx \
    --expect full


# ============================================================
# 25. FINAL CONFIRMATION
# ============================================================

echo
echo "============================================================"
echo " PROBE УСПЕШЕН"
echo "============================================================"
echo
echo "Конфигурация:"
echo
echo "  GPU:"
echo "    CMP 50HX x${CMP_COUNT}"
echo
echo "  NVIDIA:"
echo "    ${DRIVER} Open"
echo
echo "  Kernel:"
echo "    ${KERNEL}"
echo
echo "  cmpunlocker:"
echo "    ${VERSION}"
echo
echo "  Artifact:"
echo "    ${ARTIFACT_PATH}"
echo
echo "============================================================"
echo
echo "Следующая команда выполнит ПОСТОЯННУЮ установку"
echo "stockflow kernel modules."
echo
echo "Reboot автоматически выполняться НЕ БУДЕТ."
echo
echo "После установки cmpunlocker покажет BACKUP_DIR."
echo "Сохрани его на случай восстановления."
echo
echo "============================================================"
echo

read -r -p "Для продолжения введи YES: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then

    echo
    echo "Установка отменена."
    echo "stockflow-probe был выполнен."
    echo "Постоянная установка НЕ выполнялась."
    exit 0

fi


# ============================================================
# 26. STOCKFLOW INSTALL
# ============================================================

echo
echo "============================================================"
echo " STOCKFLOW INSTALL"
echo "============================================================"
echo

"$CMPUNLOCKER" \
    compute50hx-v534 \
    stockflow-install \
    --stockflow-candidate "$ARTIFACT_PATH" \
    --acknowledge I-ACCEPT-50HX-V534-COMPUTE-UNLOCK


# ============================================================
# 27. SAVE INFO
# ============================================================

echo
echo "=== Сохранение информации об установке ==="

INSTALL_INFO="${WORK_ROOT}/installation-info.txt"

{
    echo "CMP 50HX stockflow installation"
    echo
    echo "Date: $(date -Is)"
    echo "Driver: ${DRIVER}"
    echo "Kernel: ${KERNEL}"
    echo "cmpunlocker: ${VERSION}"
    echo "Artifact: ${ARTIFACT_PATH}"
    echo
    echo "NVIDIA version:"
    modinfo -F version nvidia 2>/dev/null || true
    echo
    echo "NVIDIA module:"
    modinfo -n nvidia 2>/dev/null || true
    echo
    echo "NVIDIA license:"
    modinfo -F license nvidia 2>/dev/null || true
    echo
    echo "GPU:"
    nvidia-smi -L 2>/dev/null || true
} > "$INSTALL_INFO"

echo
echo "Информация сохранена:"
echo "  ${INSTALL_INFO}"


# ============================================================
# 28. FINAL
# ============================================================

echo
echo "============================================================"
echo " УСТАНОВКА ЗАВЕРШЕНА"
echo "============================================================"
echo
echo "NVIDIA:"
echo "  ${DRIVER} Open"
echo
echo "GPU:"
echo "  CMP 50HX x${CMP_COUNT}"
echo
echo "Kernel:"
echo "  ${KERNEL}"
echo
echo "cmpunlocker:"
echo "  ${VERSION}"
echo
echo "Artifact:"
echo "  ${ARTIFACT_PATH}"
echo
echo "============================================================"
echo
echo "ВАЖНО:"
echo
echo "Reboot НЕ выполнялся автоматически."
echo
echo "Найди и сохрани BACKUP_DIR, который вывел"
echo "cmpunlocker во время stockflow-install."
echo
echo "После reboot проверь:"
echo
echo "  modinfo -F version nvidia"
echo "  modinfo -F license nvidia"
echo "  modinfo -n nvidia"
echo "  nvidia-smi -L"
echo
echo "Затем:"
echo
echo "  cd '${BUNDLE_DIR}'"
echo
echo "  ./cmpunlocker-rs compute50hx-v534 verify --all-cmp50hx --expect full"
echo
echo "============================================================"
echo
echo "Для reboot:"
echo
echo "  reboot"
echo
echo "============================================================"
```
