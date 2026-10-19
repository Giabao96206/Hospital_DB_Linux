#!/usr/bin/env bash
# ==============================================================================
# CLUSTER HEALTH CHECK & DIAGNOSTICS
# Tổng kiểm tra toàn diện tình trạng của cụm 5 máy
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=============================================================================="
log_info "🏥 BÁO CÁO TÌNH TRẠNG SỨC KHỎE HỆ THỐNG CSDL BỆNH VIỆN DỰ PHÒNG HA"
log_info "Thời gian kiểm tra: $(date '+%Y-%m-%d %H:%M:%S')"
log_info "=============================================================================="

# 1. KIỂM TRA ETCD QUORUM TRÊN 3 NODE
log_info "[1/6] Kiểm tra etcd Quorum (Yêu cầu >= 2/3 members online):"
if command -v etcdctl >/dev/null 2>&1; then
    ETCDCTL_API=3 etcdctl --endpoints="http://${DB1_IP}:2379,http://${DB2_IP}:2379,http://${DB3_IP}:2379" endpoint health || log_warn "Một số endpoint etcd không phản hồi."
else
    log_warn "etcdctl chưa được cài trên máy này, bỏ qua kiểm tra trực tiếp."
fi

# 2. KIỂM TRA PATRONI CLUSTER TOPOLOGY
log_info "[2/6] Kiểm tra cấu trúc phân bổ Patroni (Leader & Replicas):"
if command -v patronictl >/dev/null 2>&1 && [[ -f /etc/patroni/patroni.yml ]]; then
    patronictl -c /etc/patroni/patroni.yml list || log_warn "Không thể truy vấn patronictl."
elif curl -s "http://${DB1_IP}:8008/cluster" >/dev/null; then
    curl -s "http://${DB1_IP}:8008/cluster" | jq . || true
else
    log_warn "Không kết nối được tới REST API của Patroni."
fi

# 3. KIỂM TRA HAPROXY ROUTING TRÊN APP1
log_info "[3/6] Kiểm tra định tuyến ghi của HAProxy (Cổng 5000):"
if command -v psql >/dev/null 2>&1; then
    PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${APP1_IP}" -p 5000 -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -c "
        SELECT 
            inet_server_addr() AS actual_primary_ip,
            pg_is_in_recovery() AS is_in_recovery,
            current_database() AS db;
    " || log_error "Không thể kết nối tới PostgreSQL qua HAProxy cổng 5000!"
else
    log_warn "psql chưa cài, bỏ qua kiểm tra cổng 5000."
fi

# 4. KIỂM TRA DUNG LƯỢNG Ổ ĐĨA VÀ NGUY CƠ ĐẦY WAL
log_info "[4/6] Kiểm tra dung lượng ổ đĩa phân vùng gốc (/):"
df -h / | awk 'NR==1 || NR==2'

# 5. KIỂM TRA TIẾN TRÌNH DỊCH VỤ HỆ THỐNG
log_info "[5/6] Trạng thái các dịch vụ systemd then chốt:"
for svc in patroni etcd postgresql haproxy prometheus grafana-server; do
    if systemctl list-unit-files | grep -q "^${svc}\.service"; then
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        echo -e "  - ${svc}.service: \t${STATUS}"
    fi
done

# 6. KIỂM TRA KHO SAO LƯU PGBACKREST NẾU CHẠY TRÊN MON1
if [[ -f /etc/pgbackrest.conf ]] && [[ "$(hostname)" == "mon1" ]]; then
    log_info "[6/6] Tình trạng kho sao lưu pgBackRest:"
    sudo -u postgres pgbackrest --stanza="${PGBACKREST_STANZA:-hospital_cluster}" info || true
fi

log_info "=============================================================================="
log_success "HOÀN TẤT KIỂM TRA SỨC KHỎE CỤM."
