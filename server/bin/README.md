# On derlenmis binary'ler

Kurulum scripti mimariye gore bu dizinden `ss-server` ve `ss-manager` kopyalar.
Kaynak derleme yapmaz (~1 dk kurulum).

| Dizin | Mimari |
|-------|--------|
| `x86_64/` | Intel/AMD 64-bit (Ubuntu 22.04/24.04) |
| `aarch64/` | ARM64 (henuz eklenmedi — sunucuda derlenir) |

Yeniden derlemek icin WSL:

```bash
bash server/build-wsl.sh
```

Zorla kaynak derleme (sunucuda):

```bash
export LIBEV_FORCE_BUILD=1
sudo bash install_server.sh
```
