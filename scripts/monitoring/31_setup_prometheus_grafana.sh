#!/usr/bin/env bash
# ==============================================================================
# SETUP PROMETHEUS & GRAFANA MONITORING SERVER ON MON1 (192.168.10.15)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

log_info "=== THIẾT LẬP MÁY CHỦ GIÁM SÁT PROMETHEUS VÀ GRAFANA TRÊN MON1 ==="

# 1. CÀI ĐẶT PROMETHEUS
log_info "Cài đặt Prometheus..."
apt-get update -y -qq
apt-get install -y -qq prometheus

# Triển khai cấu hình Prometheus
PROM_CONFIG_SRC="${SCRIPT_DIR}/../../config/prometheus/prometheus.yml.example"
ALERT_RULES_SRC="${SCRIPT_DIR}/../../config/prometheus/alert_rules.yml"

if [[ -f "$PROM_CONFIG_SRC" ]]; then
    cp "$PROM_CONFIG_SRC" /etc/prometheus/prometheus.yml
    # Thay thế các IP từ .env (hỗ trợ cả Tailscale IP 100.x.y.z và IP LAN)
    sed -i "s/192.168.10.11/${DB1_IP}/g; s/100.115.205.94/${DB1_IP}/g" /etc/prometheus/prometheus.yml
    sed -i "s/192.168.10.12/${DB2_IP}/g; s/100.97.242.2/${DB2_IP}/g" /etc/prometheus/prometheus.yml
    sed -i "s/192.168.10.13/${DB3_IP}/g; s/100.67.87.46/${DB3_IP}/g" /etc/prometheus/prometheus.yml
    sed -i "s/192.168.10.14/${APP1_IP}/g; s/100.99.89.64/${APP1_IP}/g" /etc/prometheus/prometheus.yml
    sed -i "s/192.168.10.15/${MON1_IP}/g; s/100.87.112.76/${MON1_IP}/g" /etc/prometheus/prometheus.yml
fi
if [[ -f "$ALERT_RULES_SRC" ]]; then
    cp "$ALERT_RULES_SRC" /etc/prometheus/alert_rules.yml
fi

chown -R prometheus:prometheus /etc/prometheus
systemctl restart prometheus
systemctl enable prometheus
log_success "Prometheus đang chạy tại: http://${MON1_IP}:9090"

# 2. CÀI ĐẶT GRAFANA
log_info "Cài đặt Grafana..."
apt-get install -y -qq apt-transport-https software-properties-common wget

mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | tee /etc/apt/sources.list.d/grafana.list

apt-get update -y -qq
apt-get install -y -qq grafana

# 3. THIẾT LẬP CỔNG CHO GRAFANA (CỔNG 3001 ĐỂ TRÁNH TRÙNG CỔNG APP 3000)
sed -i 's/^;http_port = 3000/http_port = 3001/' /etc/grafana/grafana.ini

# 4. PROVISIONING DATASOURCE VÀ DASHBOARD TỰ ĐỘNG
log_info "Tự động thiết lập Datasource và import Dashboard mẫu..."
mkdir -p /etc/grafana/provisioning/datasources
mkdir -p /etc/grafana/provisioning/dashboards
mkdir -p /etc/grafana/dashboards

DS_SRC="${SCRIPT_DIR}/../../config/grafana/provisioning/datasources/datasource.yml"
DP_SRC="${SCRIPT_DIR}/../../config/grafana/provisioning/dashboards/dashboard_provider.yml"
DASH_SRC="${SCRIPT_DIR}/../../config/grafana/dashboards/hospital_ha_overview.json"

if [[ -f "$DS_SRC" ]]; then
    cp "$DS_SRC" /etc/grafana/provisioning/datasources/
fi
if [[ -f "$DP_SRC" ]]; then
    cp "$DP_SRC" /etc/grafana/provisioning/dashboards/
fi
if [[ -f "$DASH_SRC" ]]; then
    cp "$DASH_SRC" /etc/grafana/dashboards/
fi

chown -R root:grafana /etc/grafana
systemctl daemon-reload
systemctl enable grafana-server
systemctl restart grafana-server

log_success "=============================================================================="
log_success "GIÁM SÁT GRAFANA ĐÃ KHỞI CHẠY THÀNH CÔNG!"
log_success "- URL Grafana: http://${MON1_IP}:3001"
log_success "- Tài khoản mặc định: admin / admin (hoặc theo cấu hình)"
log_success "- Dashboard 'Hospital PostgreSQL HA Cluster Dashboard' đã được nạp sẵn."
log_success "=============================================================================="
