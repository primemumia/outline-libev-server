#!/bin/bash
# PC (WSL) uzerinde ss-server / ss-manager derler; sunucu kurulumu bunlari kullanir.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIN_SRC="${SCRIPT_DIR}/shadowsocks-libev"
WSL_SRC="${WSL_SRC:-$HOME/ss-libev-build}"
OUT_DIR="${SCRIPT_DIR}/bin/x86_64"

if [[ ! -d "${WIN_SRC}/src" ]]; then
    echo "Kaynak bulunamadi: ${WIN_SRC}" >&2
    exit 1
fi

if [[ ! -d "${WSL_SRC}/.git" ]]; then
    echo "shadowsocks-libev klonlaniyor -> ${WSL_SRC}"
    rm -rf "${WSL_SRC}"
    git clone --depth 1 https://github.com/shadowsocks/shadowsocks-libev.git "${WSL_SRC}"
    cd "${WSL_SRC}"
    git submodule update --init --recursive
else
    cd "${WSL_SRC}"
    git pull --ff-only 2>/dev/null || true
    git submodule update --init --recursive 2>/dev/null || true
fi

echo "Patch dosyalari kopyalaniyor..."
cp -a "${WIN_SRC}/src/ip_lock.c" "${WIN_SRC}/src/ip_lock.h" \
      "${WIN_SRC}/src/server.h" "${WIN_SRC}/src/server.c" \
      "${WIN_SRC}/src/manager.c" "${WIN_SRC}/src/manager.h" \
      "${WSL_SRC}/src/"
cp -a "${WIN_SRC}/src/CMakeLists.txt" "${WSL_SRC}/src/CMakeLists.txt"

mkdir -p "${WSL_SRC}/build"
cd "${WSL_SRC}/build"
cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_STATIC=OFF
make -j"$(nproc 2>/dev/null || echo 4)" ss-server-shared ss-manager-shared

mkdir -p "${OUT_DIR}"
cp -f "${WSL_SRC}/build/shared/bin/ss-server" "${OUT_DIR}/"
cp -f "${WSL_SRC}/build/shared/bin/ss-manager" "${OUT_DIR}/"
chmod 755 "${OUT_DIR}/ss-server" "${OUT_DIR}/ss-manager"

echo "BUILD OK"
ls -la "${OUT_DIR}/"
