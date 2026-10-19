#!/usr/bin/env bash
# ==============================================================================
# SETUP PGBACKREST BACKUP REPOSITORY SERVER ON MON1 (192.168.10.15)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

log_info "=== THIẾT LẬP KHO SAO LƯU TẬP TRUNG PGBACKREST TRÊN MON1 ==="

# 1. CÀI ĐẶT PGBACKREST VÀ TIỆN ÍCH NÉN
apt-get update -y -qq
apt-get install -y -qq pgbackrest openssh-server openssh-client lz4

# 2. TẠO USER POSTGRES NẾU CHƯA TỒN TẠI TRÊN MON1
if ! id -u postgres >/dev/null 2>&1; then
    log_info "Tạo người dùng hệ thống postgres trên MON1..."
    useradd -m -d /var/lib/postgresql -s /bin/bash postgres
fi

# 3. TẠO THƯ MỤC LƯU TRỮ VÀ NHẬT KÝ SAO LƯU
mkdir -p "${PGBACKREST_REPO_PATH}"
mkdir -p "${PGBACKREST_LOG_PATH}"
chown -R postgres:postgres "${PGBACKREST_REPO_PATH}" "${PGBACKREST_LOG_PATH}"
chmod 750 "${PGBACKREST_REPO_PATH}"

# 4. TẠO KHÓA SSH DÀNH RIÊNG CHO USER POSTGRES (GIAO TIẾP VỚI CÁC DB NODES)
SSH_DIR="/var/lib/postgresql/.ssh"
mkdir -p "${SSH_DIR}"
if [[ ! -f "${SSH_DIR}/id_rsa" ]]; then
    log_info "Tạo cặp SSH Key cho user postgres..."
    sudo -u postgres ssh-keygen -t rsa -b 4096 -f "${SSH_DIR}/id_rsa" -N "" -C "pgbackrest-mon1"
fi
chown -R postgres:postgres "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/id_rsa"
chmod 644 "${SSH_DIR}/id_rsa.pub"

# 5. TRIỂN KHAI CẤU HÌNH /etc/pgbackrest.conf
CONFIG_SRC="${SCRIPT_DIR}/../../config/pgbackrest/pgbackrest-mon1.conf.example"
if [[ -f "$CONFIG_SRC" ]]; then
    cp "$CONFIG_SRC" /etc/pgbackrest.conf
    # Thay thế IP từ .env (hỗ trợ cả Tailscale IP 100.x.y.z và IP LAN)
    sed -i -E "s/^(pg1-host=).*/\1${DB1_IP}/g" /etc/pgbackrest.conf
    sed -i -E "s/^(pg2-host=).*/\1${DB2_IP}/g" /etc/pgbackrest.conf
    sed -i -E "s/^(pg3-host=).*/\1${DB3_IP}/g" /etc/pgbackrest.conf
    PG_VER="${PG_VERSION:-14}"
    DATA_DIR="${PG_DATA_DIR:-/var/lib/postgresql/${PG_VER}/main}"
    sed -i -E "s|^(pg[1-3]-path=).*|\1${DATA_DIR}|g" /etc/pgbackrest.conf
    chown postgres:postgres /etc/pgbackrest.conf
    chmod 640 /etc/pgbackrest.conf
    log_success "Đã triển khai /etc/pgbackrest.conf trên MON1."
fi

log_info "=============================================================================="
log_info "BƯỚC TIẾP THEO BẮT BUỘC:"
log_info "Hãy sao chép Public Key dưới đây và thêm vào file authorized_keys"
log_info "của user postgres trên cả 3 máy: DB1, DB2, DB3:"
echo -e "${YELLOW}"
cat "${SSH_DIR}/id_rsa.pub"
echo -e "${NC}"
log_info "=============================================================================="

log_success "=== KHỞI TẠO PGBACKREST SERVER TRÊN MON1 THÀNH CÔNG ==="
