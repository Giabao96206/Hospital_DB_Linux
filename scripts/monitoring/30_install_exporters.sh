#!/usr/bin/env bash
# ==============================================================================
# INSTALL PROMETHEUS EXPORTERS BASED ON NODE ROLE
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

ROLE="${1:-}"

if [[ -z "$ROLE" ]]; then
    CURRENT_HOST="$(hostname)"
    case "$CURRENT_HOST" in
        db1|db2|db3) ROLE="db" ;;
        app1)        ROLE="app" ;;
        mon1)        ROLE="mon" ;;
        *)           ROLE="common" ;;
    esac
fi

log_info "=== CÀI ĐẶT PROMETHEUS EXPORTERS CHO ROLE: ${ROLE^^} ==="

apt-get update -y -qq

# 1. CÀI ĐẶT NODE_EXPORTER TRÊN TẤT CẢ CÁC MÁY (PORT 9100)
log_info "Cài đặt prometheus-node-exporter để thu thập CPU, RAM, Disk, Network..."
apt-get install -y -qq prometheus-node-exporter
systemctl enable --now prometheus-node-exporter
log_success "node_exporter đang chạy tại port 9100."

# 2. CÀI ĐẶT POSTGRES_EXPORTER NẾU LÀ DB NODE (PORT 9187)
if [[ "$ROLE" == "db" ]]; then
    log_info "Cài đặt prometheus-postgres-exporter trên DB node..."
    apt-get install -y -qq prometheus-postgres-exporter || true

    # Tạo user giám sát trong PostgreSQL nếu là Primary node
    log_info "Đang tạo user postgres_exporter (role pg_monitor)..."
    sudo -u postgres psql -c "
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postgres_exporter') THEN
            CREATE ROLE postgres_exporter WITH LOGIN PASSWORD 'Exp0rt3r_S3cr3t_2026';
            GRANT pg_monitor TO postgres_exporter;
        END IF;
    END \$\$;
    " || true

    # Cấu hình biến môi trường kết nối cho exporter
    mkdir -p /etc/default
    cat <<EOF > /etc/default/prometheus-postgres-exporter
DATA_SOURCE_NAME="postgresql://postgres_exporter:Exp0rt3r_S3cr3t_2026@127.0.0.1:5432/postgres?sslmode=disable"
EOF
    systemctl restart prometheus-postgres-exporter || true
    log_success "postgres_exporter cấu hình hoàn tất (Port 9187)."
fi

# 3. CÀI ĐẶT HAPROXY EXPORTER NẾU LÀ APP NODE
if [[ "$ROLE" == "app" ]]; then
    log_info "Kích hoạt Prometheus Metrics trên HAProxy..."
    # HAProxy 2.8+ trên Ubuntu 24.04 đã có sẵn service prometheus-exporter
    # thông qua chỉ thị 'http-request use-service prometheus-exporter if { path /metrics }' trên cổng 7000.
    log_success "HAProxy exporter đã tích hợp sẵn tại http://${APP1_IP:-100.99.89.64}:7000/metrics"
fi

log_success "=== HOÀN TẤT CÀI ĐẶT EXPORTERS TRÊN $(hostname) ==="
