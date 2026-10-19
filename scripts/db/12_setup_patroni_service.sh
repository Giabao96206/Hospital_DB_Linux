#!/usr/bin/env bash
# ==============================================================================
# SETUP PATRONI SERVICE ON DB NODES (DB1, DB2, DB3)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

NODE_NAME="${1:-$(hostname)}"
log_info "=== THIẾT LẬP PATRONI SERVICE CHO NODE: ${NODE_NAME} ==="

case "$NODE_NAME" in
    db1)
        NODE_IP="${DB1_IP}"
        ;;
    db2)
        NODE_IP="${DB2_IP}"
        ;;
    db3)
        NODE_IP="${DB3_IP}"
        ;;
    *)
        log_error "Tên node '${NODE_NAME}' không hợp lệ! Chỉ chấp nhận: db1, db2, db3."
        exit 1
        ;;
esac

CONFIG_SOURCE="${SCRIPT_DIR}/../../config/patroni/${NODE_NAME}.yml.example"

if [[ ! -f "$CONFIG_SOURCE" ]]; then
    log_error "Không tìm thấy file mẫu cấu hình: ${CONFIG_SOURCE}"
    exit 1
fi

log_info "Đang triển khai cấu hình Patroni vào /etc/patroni/patroni.yml..."
cp "${CONFIG_SOURCE}" /etc/patroni/patroni.yml

# Thay thế các placeholder bằng giá trị thực tế từ .env (hỗ trợ cả Tailscale IP 100.x.y.z)
sed -i "s/CHANGE_ME_POSTGRES_SECRET_2026/${POSTGRES_ADMIN_PASSWORD}/g" /etc/patroni/patroni.yml
sed -i "s/CHANGE_ME_REPL_SECRET_2026/${PG_REP_PASSWORD}/g" /etc/patroni/patroni.yml

# Thay thế các địa chỉ IP trong template bằng IP thực tế từ .env
sed -i "s/100.115.205.94/${DB1_IP}/g" /etc/patroni/patroni.yml || true
sed -i "s/100.97.242.2/${DB2_IP}/g" /etc/patroni/patroni.yml || true
sed -i "s/100.67.87.46/${DB3_IP}/g" /etc/patroni/patroni.yml || true
sed -i "s|100.64.0.0/10|${CLUSTER_SUBNET}|g" /etc/patroni/patroni.yml || true
sed -i "s/192.168.10.11/${DB1_IP}/g" /etc/patroni/patroni.yml || true
sed -i "s/192.168.10.12/${DB2_IP}/g" /etc/patroni/patroni.yml || true
sed -i "s/192.168.10.13/${DB3_IP}/g" /etc/patroni/patroni.yml || true
sed -i "s|192.168.10.0/24|${CLUSTER_SUBNET}|g" /etc/patroni/patroni.yml || true
sed -i "s/synchronous_mode: false/synchronous_mode: ${PATRONI_SYNCHRONOUS_MODE}/g" /etc/patroni/patroni.yml

# Thay thế đường dẫn phiên bản PostgreSQL (14 hoặc 16)
PG_VER="${PG_VERSION:-14}"
DATA_DIR="${PG_DATA_DIR:-/var/lib/postgresql/${PG_VER}/main}"
BIN_DIR="${PG_BIN_DIR:-/usr/lib/postgresql/${PG_VER}/bin}"
sed -i "s|/var/lib/postgresql/16/main|${DATA_DIR}|g" /etc/patroni/patroni.yml
sed -i "s|/usr/lib/postgresql/16/bin|${BIN_DIR}|g" /etc/patroni/patroni.yml

# Thiết lập quyền sở hữu và bảo mật nghiêm ngặt (chỉ postgres đọc/ghi)
chown postgres:postgres /etc/patroni/patroni.yml
chmod 600 /etc/patroni/patroni.yml
log_success "Đã bảo vệ file cấu hình /etc/patroni/patroni.yml (chmod 600)."

# Tạo file .pgpass cho người dùng postgres
log_info "Tạo file xác thực /var/lib/postgresql/.pgpass..."
cat <<EOF > /var/lib/postgresql/.pgpass
127.0.0.1:*:*:${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}
${NODE_IP}:*:*:${POSTGRES_ADMIN_USER}:${POSTGRES_ADMIN_PASSWORD}
*:*:*:${PG_REP_USER}:${PG_REP_PASSWORD}
EOF
chown postgres:postgres /var/lib/postgresql/.pgpass
chmod 600 /var/lib/postgresql/.pgpass

# Tạo Systemd Service cho Patroni
log_info "Tạo systemd unit file /etc/systemd/system/patroni.service..."
cat <<EOF > /etc/systemd/system/patroni.service
[Unit]
Description=Patroni Orchestrator for PostgreSQL High Availability
After=syslog.target network.target etcd.service
Requires=network.target

[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/bin/patroni /etc/patroni/patroni.yml
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=process
TimeoutSec=30
Restart=no

# Giới hạn tài nguyên cho tiến trình CSDL
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable patroni.service
systemctl restart patroni.service

log_info "Đang chờ Patroni khởi tạo cụm hoặc tham gia cluster (10s)..."
sleep 10

# Kiểm tra trạng thái Patroni
log_info "Trạng thái cụm Patroni hiện tại:"
patronictl -c /etc/patroni/patroni.yml list || true

log_success "=== HOÀN TẤT CẤU HÌNH PATRONI TRÊN ${NODE_NAME} ==="
