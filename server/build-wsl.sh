#!/bin/bash
set -e

WIN_SRC="/mnt/c/Users/prime/Desktop/test out/server/shadowsocks-libev"
WSL_SRC="$HOME/ss-libev-build"

cp -a "$WIN_SRC/src/ip_lock.c" "$WIN_SRC/src/ip_lock.h" "$WIN_SRC/src/server.h" "$WIN_SRC/src/server.c" "$WIN_SRC/src/manager.c" "$WIN_SRC/src/manager.h" "$WSL_SRC/src/"

cd "$WSL_SRC/build"
make -j4 ss-server-shared ss-manager-shared

mkdir -p "/mnt/c/Users/prime/Desktop/test out/server/bin/x86_64"
cp -f "$WSL_SRC/build/shared/bin/ss-server" "/mnt/c/Users/prime/Desktop/test out/server/bin/x86_64/"
cp -f "$WSL_SRC/build/shared/bin/ss-manager" "/mnt/c/Users/prime/Desktop/test out/server/bin/x86_64/"

echo "BUILD OK"
ls -la "/mnt/c/Users/prime/Desktop/test out/server/bin/x86_64/"
