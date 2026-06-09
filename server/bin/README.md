# On derlenmis binary'ler

Sunucu kurulumu **yalnizca** bu dizindeki `ss-server` ve `ss-manager` dosyalarini kullanir; kaynak derleme yapilmaz.

| Dizin | Mimari |
|-------|--------|
| `x86_64/` | Intel/AMD 64-bit (Ubuntu 22.04/24.04) |
| `aarch64/` | ARM64 (henuz eklenmedi) |

Gelistirici makinede (WSL) yeniden derlemek:

```bash
bash server/build-wsl.sh
git add server/bin/x86_64/ss-server server/bin/x86_64/ss-manager
git commit -m "Prebuilt binary guncelle"
git push
```

Canli port durumu `/run/shadowsocks-manager/` altinda tutulur (RAM/tmpfs, reboot sonrasi silinir).
