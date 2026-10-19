#!/usr/bin/env bash
# ==============================================================================
# SETUP HAPROXY ROUTING ON APP1 (192.168.10.14 or Tailscale IP)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

log_info "=== BẮT ĐẦU CÀI ĐẶT & CẤU HÌNH HAPROXY TRÊN $(hostname) ==="

apt-get update -y -qq
apt-get install -y -qq haproxy

HAPROXY_CONF_SRC="${SCRIPT_DIR}/../../config/haproxy/haproxy.cfg.example"
HAPROXY_CONF_DEST="/etc/haproxy/haproxy.cfg"

if [[ ! -f "$HAPROXY_CONF_SRC" ]]; then
    log_error "Không tìm thấy file mẫu cấu hình: ${HAPROXY_CONF_SRC}"
    exit 1
fi

log_info "Triển khai file cấu hình ${HAPROXY_CONF_DEST}..."
cp "$HAPROXY_CONF_SRC" "$HAPROXY_CONF_DEST"

# Thay thế các IP từ .env (hỗ trợ cả Tailscale IP 100.x.y.z và mạng LAN)
sed -i "s/192.168.10.11/${DB1_IP}/g; s/100.115.205.94/${DB1_IP}/g" "$HAPROXY_CONF_DEST"
sed -i "s/192.168.10.12/${DB2_IP}/g; s/100.97.242.2/${DB2_IP}/g" "$HAPROXY_CONF_DEST"
sed -i "s/192.168.10.13/${DB3_IP}/g; s/100.67.87.46/${DB3_IP}/g" "$HAPROXY_CONF_DEST"
sed -i "s/192.168.10.14/${APP1_IP}/g; s/100.99.89.64/${APP1_IP}/g" "$HAPROXY_CONF_DEST"
sed -i "s/Hospital@2026!Stats/${HAPROXY_STATS_PASSWORD}/g; s/CHANGE_ME_STATS_SECRET_2026/${HAPROXY_STATS_PASSWORD}/g" "$HAPROXY_CONF_DEST"

log_info "Kiểm tra cú pháp cấu hình HAProxy..."
haproxy -c -f "$HAPROXY_CONF_DEST"
log_success "Cú pháp HAProxy hoàn toàn hợp lệ."

systemctl daemon-reload
systemctl enable --now haproxy
systemctl restart haproxy

log_success "=== HAPROXY ĐÃ KHỞI CHẠY THÀNH CÔNG ==="
log_info "- Cổng định tuyến Primary (Write): 127.0.0.1:5000 & ${APP1_IP}:5000"
log_info "- Cổng định tuyến Standby (Read): 127.0.0.1:5001 & ${APP1_IP}:5001"
log_info "- Trang thống kê HAProxy: http://${APP1_IP}:7000/ (User: admin / Pass: ${HAPROXY_STATS_PASSWORD})"
