#!/usr/bin/env bash
# ==============================================================================
# SETUP PGBACKREST CLIENT ON DB NODES (DB1, DB2, DB3)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

log_info "=== THIẾT LẬP PGBACKREST CLIENT TRÊN $(hostname) ==="

# 1. CÀI ĐẶT PGBACKREST
apt-get update -y -qq
apt-get install -y -qq pgbackrest openssh-server openssh-client lz4

# 2. CẤU HÌNH SSH AUTHORIZED_KEYS CHO USER POSTGRES
SSH_DIR="/var/lib/postgresql/.ssh"
mkdir -p "${SSH_DIR}"
touch "${SSH_DIR}/authorized_keys"
chown -R postgres:postgres "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"

# 3. TRIỂN KHAI /etc/pgbackrest.conf TỪ MẪU CLIENT
CONFIG_SRC="${SCRIPT_DIR}/../../config/pgbackrest/pgbackrest-db.conf.example"
if [[ -f "$CONFIG_SRC" ]]; then
    cp "$CONFIG_SRC" /etc/pgbackrest.conf
    # Thay thế IP của MON1 từ .env (hỗ trợ cả Tailscale IP 100.x.y.z và IP LAN)
    sed -i -E "s/^(repo1-host=).*/\1${MON1_IP}/g" /etc/pgbackrest.conf
    PG_VER="${PG_VERSION:-14}"
    DATA_DIR="${PG_DATA_DIR:-/var/lib/postgresql/${PG_VER}/main}"
    sed -i -E "s|^(pg1-path=).*|\1${DATA_DIR}|g" /etc/pgbackrest.conf
    chown postgres:postgres /etc/pgbackrest.conf
    chmod 640 /etc/pgbackrest.conf
    log_success "Đã triển khai /etc/pgbackrest.conf trên $(hostname)."
fi

# 4. TẠO THƯ MỤC NHẬT KÝ
mkdir -p /var/log/pgbackrest
chown -R postgres:postgres /var/log/pgbackrest

log_info "Hướng dẫn: Để cho phép MON1 kết nối sao lưu tự động,"
log_info "hãy dán nội dung id_rsa.pub từ MON1 vào file: ${SSH_DIR}/authorized_keys"

log_success "=== HOÀN TẤT THIẾT LẬP PGBACKREST CLIENT TRÊN $(hostname) ==="
