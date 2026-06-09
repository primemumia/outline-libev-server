# Libev Server Kurulum Scripti

Outline `install_server.sh` benzeri tek komutla shadowsocks-libev sunucu kurulumu.

## Hızlı kurulum (GitHub yüklendikten sonra)

```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/KULLANICI/REPO/main/server/install_scripts/install_server.sh)"
```

veya:

```bash
curl -fsSL https://raw.githubusercontent.com/KULLANICI/REPO/main/server/install_scripts/install_server.sh | sudo bash
```

## Özelleştirme

```bash
# Farklı repo / dal
export LIBEV_REPO="kullanici/repo-adi"
export LIBEV_BRANCH="main"

# Public IP manuel
sudo bash install_server.sh --hostname 1.2.3.4

# Port değiştirme
sudo bash install_server.sh --api-port 8087 --manager-port 6001
```

## Kurulum sonrası

| Bileşen | Konum |
|---------|--------|
| Management API | `http://127.0.0.1:8087/{secret}` |
| Access config | `/opt/libev-server/access.txt` |
| CLI | `libev add key isim` |
| ss-manager | UDP `127.0.0.1:6001` |
| Port havuzu | 444–999 |

## Bot entegrasyonu

Kurulum sonunda yazdırılan JSON'u bot `config.json` içindeki `outline_apis` dizisine ekleyin (`type: libev`).

## GitHub'a yükleme

Repo kök yapısı:

```
repo/
  server/
    install_scripts/
      install_server.sh
      README.md
    shadowsocks-libev/    # patch'li kaynak + submodule
    ss-api/
    shadowsocks-manager.service
    ss-api.service
```

`install_server.sh` içinde varsayılan repo adını güncelleyin:

```bash
readonly LIBEV_REPO="${LIBEV_REPO:-KULLANICI/REPO-ADI}"
```
