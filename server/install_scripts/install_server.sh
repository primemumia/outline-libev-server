#!/bin/bash
#
# shadowsocks-libev server installer (Outline install_server.sh benzeri)
#
# Kullanım:
#   sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/USER/REPO/main/server/install_scripts/install_server.sh)"
#
# veya:
#   curl -fsSL ... | sudo bash
#
# Ortam değişkenleri:
#   LIBEV_REPO          GitHub repo (varsayıilan: primemumia/outline-libev-server)
#   LIBEV_BRANCH        Dal adi (varsayilan: main)
#   LIBEV_INSTALL_DIR   Kurulum kok dizini (varsayilan: /opt/libev-server)
#   LIBEV_WORKDIR       ss-manager workdir (varsayilan: /var/lib/shadowsocks-manager)
#   LIBEV_PORT_START    Port havuzu baslangic (444)
#   LIBEV_PORT_END      Port havuzu bitis (999)
#   LIBEV_FORCE_BUILD   1 ise kaynak derleme (on derlenmis binary yok sayilir)
#
# Bayraklar:
#   --hostname HOST     Sunucu public IP veya domain
#   --api-port PORT     ss-api HTTP portu (varsayilan: 8087, ic ag)
#   --api-tls-port PORT Dis HTTPS API portu (varsayilan: 8080, Outline uyumlu)
#   --manager-port PORT (eski) UDP yerine unix socket kullanilir, yok sayilir
#   --local             GitHub yerine yerel server/ dizinini kullan (out.sh ile)
#   -h, --help          Yardim

set -euo pipefail

readonly LIBEV_REPO="${LIBEV_REPO:-primemumia/outline-libev-server}"
readonly LIBEV_BRANCH="${LIBEV_BRANCH:-main}"
readonly LIBEV_INSTALL_DIR="${LIBEV_INSTALL_DIR:-/opt/libev-server}"
readonly LIBEV_WORKDIR="${LIBEV_WORKDIR:-/var/lib/shadowsocks-manager}"
readonly LIBEV_SS_API_DIR="${LIBEV_SS_API_DIR:-/opt/ss-api}"
readonly LIBEV_SRC_DIR="${LIBEV_SRC_DIR:-/opt/shadowsocks-libev}"
readonly LIBEV_PORT_START="${LIBEV_PORT_START:-444}"
readonly LIBEV_PORT_END="${LIBEV_PORT_END:-999}"
readonly MANAGER_SOCKET="${MANAGER_SOCKET:-${LIBEV_WORKDIR}/manager.sock}"
readonly SSL_DIR="/etc/libev/ssl"

FLAGS_HOSTNAME=""
FLAGS_API_PORT=0
FLAGS_API_TLS_PORT=0
FLAGS_MANAGER_PORT=0
FLAGS_LOCAL=0
LIBEV_SOURCE_DIR="${LIBEV_SOURCE_DIR:-}"
PREBUILT_BIN_DIR=""

FULL_LOG="$(mktemp -t libev_install_logXXXXXX)"
LAST_ERROR="$(mktemp -t libev_install_errXXXXXX)"
readonly FULL_LOG LAST_ERROR

function display_usage() {
    cat <<'EOF'
shadowsocks-libev Server Installer

Kullanim:
  sudo bash install_server.sh [--hostname HOST] [--api-port PORT] [--manager-port PORT]

Ornek (GitHub'dan):
  sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/USER/REPO/main/server/install_scripts/install_server.sh)"

Ortam:
  LIBEV_REPO=primemumia/outline-libev-server
  LIBEV_BRANCH=main
EOF
}

function log_error() {
    echo -e "\033[0;31m$1\033[0m" >&2
    echo "$1" >> "${FULL_LOG}"
}

function log_start_step() {
    local -r str="> $*"
    local -ir lineLength=47
    echo -n "${str}"
    local -ir numDots=$(( lineLength - ${#str} - 1 ))
    if (( numDots > 0 )); then
        echo -n " "
        for _ in $(seq 1 "${numDots}"); do echo -n .; done
    fi
    echo -n " "
}

function log_command() {
    "$@" > >(tee -a "${FULL_LOG}") 2> >(tee -a "${FULL_LOG}" > "${LAST_ERROR}")
}

function run_step() {
    local -r msg="$1"
    log_start_step "${msg}"
    shift 1
    if log_command "$@"; then
        echo "OK"
    else
        return 1
    fi
}

function command_exists() {
    command -v "$@" >/dev/null 2>&1
}

function fetch() {
    curl --silent --show-error --fail --ipv4 "$@"
}

function safe_base64() {
    base64 -w 0 2>/dev/null | tr '/+' '_-' | tr -d '='
}

function generate_api_secret() {
    if [[ -n "${LIBEV_API_SECRET:-}" ]]; then
        readonly LIBEV_API_SECRET
        return 0
    fi
    LIBEV_API_SECRET="$(head -c 24 /dev/urandom | safe_base64)"
    readonly LIBEV_API_SECRET
}

function require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Root olarak calistirin: sudo bash install_server.sh"
        exit 1
    fi
}

function detect_public_ip() {
    local -ar urls=(
        'https://icanhazip.com/'
        'https://ipinfo.io/ip'
        'https://domains.google.com/checkip'
    )
    local ip
    for url in "${urls[@]}"; do
        ip="$(fetch "${url}" | tr -d '[:space:]')" && [[ -n "${ip}" ]] && {
            PUBLIC_HOSTNAME="${ip}"
            return 0
        }
    done
    log_error "Public IP tespit edilemedi. --hostname kullanin."
    return 1
}

function install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y \
        build-essential cmake git autoconf libtool pkg-config \
        libev-dev libpcre2-dev libmbedtls-dev libsodium-dev libc-ares-dev \
        libcap2-bin libsystemd-dev python3 python3-pip curl ca-certificates \
        rsync nginx openssl
}

function cache_prebuilt_from_dir() {
    local src="$1"
    PREBUILT_BIN_DIR="${LIBEV_INSTALL_DIR}/prebuilt/${MACHINE_TYPE}"
    mkdir -p "${PREBUILT_BIN_DIR}"
    install -m 755 "${src}/ss-server" "${PREBUILT_BIN_DIR}/ss-server"
    install -m 755 "${src}/ss-manager" "${PREBUILT_BIN_DIR}/ss-manager"
}

function try_cache_prebuilt() {
    local candidate="$1"
    if [[ -f "${candidate}/ss-server" && -f "${candidate}/ss-manager" ]]; then
        cache_prebuilt_from_dir "${candidate}"
        return 0
    fi
    return 1
}

function fetch_server_sources() {
    mkdir -p "${LIBEV_INSTALL_DIR}" "${LIBEV_WORKDIR}" "${LIBEV_SS_API_DIR}" "${LIBEV_SRC_DIR}" /etc/libev

    if (( FLAGS_LOCAL == 1 )); then
        local src_root="${LIBEV_SOURCE_DIR}"
        if [[ -z "${src_root}" ]]; then
            src_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        fi
        if [[ ! -d "${src_root}/shadowsocks-libev" ]]; then
            log_error "Yerel kaynak bulunamadi: ${src_root}/shadowsocks-libev"
            exit 1
        fi
        rsync -a --delete "${src_root}/shadowsocks-libev/" "${LIBEV_SRC_DIR}/"
        rsync -a "${src_root}/ss-api/" "${LIBEV_SS_API_DIR}/"
        try_cache_prebuilt "${src_root}/bin/${MACHINE_TYPE}" || true
        return 0
    fi

    local clone_dir
    clone_dir="$(mktemp -d /tmp/libev-src.XXXXXX)"
    local repo_url="https://github.com/${LIBEV_REPO}.git"

    git clone --depth 1 --branch "${LIBEV_BRANCH}" --recurse-submodules "${repo_url}" "${clone_dir}"

    if [[ ! -d "${clone_dir}/server/shadowsocks-libev" ]]; then
        log_error "Repo yapisi hatali: server/shadowsocks-libev bulunamadi (${LIBEV_REPO})"
        exit 1
    fi

    rsync -a --delete "${clone_dir}/server/shadowsocks-libev/" "${LIBEV_SRC_DIR}/"
    rsync -a "${clone_dir}/server/ss-api/" "${LIBEV_SS_API_DIR}/"
    try_cache_prebuilt "${clone_dir}/server/bin/${MACHINE_TYPE}" || true

    rm -rf "${clone_dir}"
}

function install_shadowsocks_binaries() {
    if [[ "${LIBEV_FORCE_BUILD:-0}" == "1" ]]; then
        build_shadowsocks_libev
        return 0
    fi

    if [[ -n "${PREBUILT_BIN_DIR}" && -x "${PREBUILT_BIN_DIR}/ss-server" && -x "${PREBUILT_BIN_DIR}/ss-manager" ]]; then
        install -m 755 "${PREBUILT_BIN_DIR}/ss-server" /usr/local/bin/ss-server
        install -m 755 "${PREBUILT_BIN_DIR}/ss-manager" /usr/local/bin/ss-manager
        return 0
    fi

    build_shadowsocks_libev
}

function build_shadowsocks_libev() {
    cd "${LIBEV_SRC_DIR}"
    git submodule update --init --recursive 2>/dev/null || true
    rm -rf build
    mkdir build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DWITH_STATIC=OFF
    local -i jobs
    jobs="$(nproc 2>/dev/null || echo 2)"
    make -j"${jobs}"
    make install
}

function install_python_deps() {
    if ! pip3 install -r "${LIBEV_SS_API_DIR}/requirements.txt" 2>/dev/null; then
        pip3 install --break-system-packages -r "${LIBEV_SS_API_DIR}/requirements.txt" 2>/dev/null || \
            apt-get install -y python3-aiohttp
    fi
    chmod +x "${LIBEV_SS_API_DIR}/libev" "${LIBEV_SS_API_DIR}/libev-cli.py"
    cat > /usr/local/bin/libev <<EOF
#!/bin/bash
exec python3 ${LIBEV_SS_API_DIR}/libev-cli.py "\$@"
EOF
    chmod +x /usr/local/bin/libev
}

function write_configs() {
    rm -f "${MANAGER_SOCKET}"

    cat > /etc/libev/cli.json <<EOF
{
  "manager_address": "${MANAGER_SOCKET}",
  "server_ip": "${PUBLIC_HOSTNAME}",
  "port_store": "${LIBEV_WORKDIR}/ports.json",
  "port_range": {
    "start": ${LIBEV_PORT_START},
    "end": ${LIBEV_PORT_END}
  }
}
EOF
    chmod 600 /etc/libev/cli.json

    cat > /etc/systemd/system/shadowsocks-manager.service <<EOF
[Unit]
Description=Shadowsocks Libev Manager (ss-manager)
After=network.target

[Service]
Type=simple
User=root
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/ss-manager -u --executable /usr/local/bin/ss-server --manager-address ${MANAGER_SOCKET} --workdir ${LIBEV_WORKDIR} -s 0.0.0.0 -m chacha20-ietf-poly1305
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/ss-api.service <<EOF
[Unit]
Description=Shadowsocks Libev HTTP API
After=network.target shadowsocks-manager.service
Requires=shadowsocks-manager.service

[Service]
Type=simple
User=root
WorkingDirectory=${LIBEV_SS_API_DIR}
ExecStart=/usr/bin/python3 ${LIBEV_SS_API_DIR}/ss_api.py --host 127.0.0.1 --port ${API_PORT} --manager-address ${MANAGER_SOCKET} --server-ip ${PUBLIC_HOSTNAME} --api-secret ${LIBEV_API_SECRET} --port-store ${LIBEV_WORKDIR}/ports.json
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

function setup_api_tls() {
    mkdir -p "${SSL_DIR}"
    if [[ ! -f "${SSL_DIR}/cert.pem" ]]; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "${SSL_DIR}/key.pem" \
            -out "${SSL_DIR}/cert.pem" \
            -subj "/CN=${PUBLIC_HOSTNAME}" >/dev/null 2>&1
    fi

    CERT_SHA256="$(openssl x509 -in "${SSL_DIR}/cert.pem" -outform DER | openssl dgst -sha256 | awk '{print toupper($2)}')"
    readonly CERT_SHA256

    PUBLIC_API_URL="https://${PUBLIC_HOSTNAME}:${API_TLS_PORT}/${LIBEV_API_SECRET}"
    readonly PUBLIC_API_URL

    cat > /etc/nginx/sites-available/libev-api <<EOF
server {
    listen ${API_TLS_PORT} ssl;
    listen [::]:${API_TLS_PORT} ssl;
    server_name _;

    ssl_certificate ${SSL_DIR}/cert.pem;
    ssl_certificate_key ${SSL_DIR}/key.pem;

    location / {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/libev-api /etc/nginx/sites-enabled/libev-api
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl enable nginx
    systemctl restart nginx
}

function start_services() {
    systemctl daemon-reload
    systemctl enable shadowsocks-manager ss-api
    systemctl restart shadowsocks-manager
    sleep 2
    systemctl restart ss-api
    sleep 1
}

function wait_for_api() {
    local -i i
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:${API_PORT}/${LIBEV_API_SECRET}/server" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    log_error "ss-api hazir degil (port ${API_PORT})"
    return 1
}

function create_first_access_key() {
    FIRST_KEY_JSON="$(python3 <<PYEOF
import json
import sys
sys.path.insert(0, "${LIBEV_SS_API_DIR}")
from key_store import KeyManager

km = KeyManager.from_config("/etc/libev/cli.json")
try:
    result = km.add_key("default")
except ValueError:
    found = km.find_by_name("default")
    if not found:
        raise
    port, entry = found
    result = km.key_payload(port, entry)
print(json.dumps(result, ensure_ascii=False))
PYEOF
)"
    readonly FIRST_KEY_JSON
}

function write_access_config() {
    readonly ACCESS_CONFIG="${LIBEV_INSTALL_DIR}/access.txt"
    mkdir -p "${LIBEV_INSTALL_DIR}"
    chmod 700 "${LIBEV_INSTALL_DIR}"

    cat > "${ACCESS_CONFIG}" <<EOF
apiUrl:${PUBLIC_API_URL}
certSha256:${CERT_SHA256}
internalApiUrl:http://127.0.0.1:${API_PORT}/${LIBEV_API_SECRET}
serverIp:${PUBLIC_HOSTNAME}
managerAddress:${MANAGER_SOCKET}
type:libev
portRange:${LIBEV_PORT_START}-${LIBEV_PORT_END}
EOF
    chmod 600 "${ACCESS_CONFIG}"
}

function output_install_result() {
    local outline_json
    outline_json="$(printf '{"apiUrl":"%s","certSha256":"%s"}' "${PUBLIC_API_URL}" "${CERT_SHA256}")"

    cat <<EOF

Congratulations! This Libev server is ready to use.

Outline uyumlu API JSON (bot config icin):

${outline_json}

Bot outline_apis ornegi:

{
  "id": "api1",
  "type": "libev",
  "name": "Libev Server",
  "api": {
    "apiUrl": "${PUBLIC_API_URL}",
    "certSha256": "${CERT_SHA256}"
  },
  "server_ip": "${PUBLIC_HOSTNAME}",
  "manager_address": "${MANAGER_SOCKET}",
  "workdir": "${LIBEV_WORKDIR}",
  "keys": []
}

Manuel anahtar komutlari:
  libev add key mumia
  libev del key mumia
  libev list keys
  libev list keys --live
  libev status port 444
  libev status ports
  libev show key mumia

Ilk anahtar (default):
${FIRST_KEY_JSON}

Access config: ${ACCESS_CONFIG}

EOF
}

function finish() {
    local -ir code=$?
    if (( code != 0 )); then
        if [[ -s "${LAST_ERROR}" ]]; then
            log_error "Son hata: $(< "${LAST_ERROR}")"
        fi
        log_error "Kurulum basarisiz. Tam log: ${FULL_LOG}"
    else
        rm -f "${FULL_LOG}"
    fi
    rm -f "${LAST_ERROR}"
}

function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hostname)
                FLAGS_HOSTNAME="$2"
                shift 2
                ;;
            --api-port)
                FLAGS_API_PORT="$2"
                shift 2
                ;;
            --api-tls-port)
                FLAGS_API_TLS_PORT="$2"
                shift 2
                ;;
            --manager-port)
                FLAGS_MANAGER_PORT="$2"
                shift 2
                ;;
            --local)
                FLAGS_LOCAL=1
                shift 1
                ;;
            -h|--help)
                display_usage
                exit 0
                ;;
            *)
                log_error "Bilinmeyen arguman: $1"
                display_usage
                exit 1
                ;;
        esac
    done
}

function main() {
    trap finish EXIT
    parse_args "$@"

    require_root

    MACHINE_TYPE="$(uname -m)"
    if [[ "${MACHINE_TYPE}" != "x86_64" && "${MACHINE_TYPE}" != "aarch64" ]]; then
        log_error "Desteklenmeyen mimari: ${MACHINE_TYPE}"
        exit 1
    fi
    readonly MACHINE_TYPE

    if ! command_exists curl; then
        apt-get update -qq && apt-get install -y curl ca-certificates
    fi
    if ! command_exists git; then
        apt-get update -qq && apt-get install -y git
    fi

    API_PORT="${FLAGS_API_PORT}"
    if (( API_PORT == 0 )); then
        API_PORT=8087
    fi
    readonly API_PORT

    API_TLS_PORT="${FLAGS_API_TLS_PORT}"
    if (( API_TLS_PORT == 0 )); then
        API_TLS_PORT=8080
    fi
    readonly API_TLS_PORT

    if (( FLAGS_MANAGER_PORT != 0 )); then
        echo "> Not: --manager-port kullanilmiyor; unix socket: ${MANAGER_SOCKET}"
    fi

    PUBLIC_HOSTNAME="${FLAGS_HOSTNAME}"
    if [[ -z "${PUBLIC_HOSTNAME}" ]]; then
        run_step "Public IP tespit ediliyor" detect_public_ip
    fi
    readonly PUBLIC_HOSTNAME

    run_step "Bagimliliklar kuruluyor" install_dependencies
    if (( FLAGS_LOCAL == 1 )); then
        run_step "Yerel kaynak kopyalaniyor" fetch_server_sources
    else
        run_step "Kaynak kod indiriliyor (${LIBEV_REPO})" fetch_server_sources
    fi
    if [[ -n "${PREBUILT_BIN_DIR}" ]]; then
        run_step "On derlenmis binary kuruluyor (${MACHINE_TYPE})" install_shadowsocks_binaries
    else
        run_step "shadowsocks-libev derleniyor" install_shadowsocks_binaries
    fi
    run_step "Python bagimliliklari kuruluyor" install_python_deps
    run_step "API secret uretiliyor" generate_api_secret
    run_step "Yapilandirma yaziliyor" write_configs
    run_step "HTTPS API (nginx) kuruluyor" setup_api_tls
    run_step "Servisler baslatiliyor" start_services
    run_step "API bekleniyor" wait_for_api
    run_step "Ilk anahtar olusturuluyor" create_first_access_key
    run_step "Access config yaziliyor" write_access_config

    output_install_result
}

main "$@"
