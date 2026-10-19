#!/usr/bin/env bash
# ==============================================================================
# SETUP ETCD CLUSTER NODE (DB1, DB2, DB3)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

NODE_NAME="${1:-$(hostname)}"
log_info "=== THIẾT LẬP THÀNH VIÊN ETCD CHO NODE: ${NODE_NAME} ==="

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

log_info "Cài đặt etcd-server và etcd-client..."
apt-get update -y -qq
apt-get install -y -qq etcd-server etcd-client

log_info "Dừng dịch vụ etcd để ghi cấu hình..."
systemctl stop etcd || true

# Tạo thư mục dữ liệu cho etcd
mkdir -p /var/lib/etcd/hospital-ha.etcd
chown -R etcd:etcd /var/lib/etcd

log_info "Tạo file cấu hình /etc/etcd/etcd.conf.yml cho ${NODE_NAME} (${NODE_IP})..."
mkdir -p /etc/etcd
cat <<EOF > /etc/etcd/etcd.conf.yml
name: '${NODE_NAME}'
data-dir: '/var/lib/etcd/hospital-ha.etcd'
listen-peer-urls: 'http://${NODE_IP}:${ETCD_PEER_PORT}'
listen-client-urls: 'http://${NODE_IP}:${ETCD_CLIENT_PORT},http://127.0.0.1:${ETCD_CLIENT_PORT}'
initial-advertise-peer-urls: 'http://${NODE_IP}:${ETCD_PEER_PORT}'
advertise-client-urls: 'http://${NODE_IP}:${ETCD_CLIENT_PORT}'
initial-cluster: '${ETCD_INITIAL_CLUSTER}'
initial-cluster-token: '${ETCD_CLUSTER_TOKEN}'
initial-cluster-state: 'new'

auto-compaction-retention: '1'
snapshot-count: 10000
heartbeat-interval: 250
election-timeout: 1250
quota-backend-bytes: 2147483648
EOF

chown -R etcd:etcd /etc/etcd
chmod 644 /etc/etcd/etcd.conf.yml

# Tạo systemd override để etcd đọc cấu hình từ /etc/etcd/etcd.conf.yml
mkdir -p /etc/systemd/system/etcd.service.d
cat <<EOF > /etc/systemd/system/etcd.service.d/override.conf
[Service]
ExecStart=
ExecStart=/usr/bin/etcd --config-file=/etc/etcd/etcd.conf.yml
EOF

systemctl daemon-reload
systemctl enable --now etcd

log_info "Chờ etcd khởi động và thiết lập kết nối peer..."
sleep 3

# Kiểm tra tình trạng etcd
log_info "Kiểm tra danh sách thành viên etcd cluster:"
ETCDCTL_API=3 etcdctl --endpoints="http://127.0.0.1:${ETCD_CLIENT_PORT}" member list -w table || true

log_info "Kiểm tra tình trạng sức khỏe etcd endpoint:"
ETCDCTL_API=3 etcdctl --endpoints="http://127.0.0.1:${ETCD_CLIENT_PORT}" endpoint health || true

log_success "=== THIẾT LẬP ETCD TRÊN ${NODE_NAME} THÀNH CÔNG ==="
