#!/usr/bin/env bash
# ==============================================================================
# COLLECT CLUSTER LOGS FOR TROUBLESHOOTING & AUDIT
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_ARCHIVE_DIR="/tmp/hospital_ha_logs_${TIMESTAMP}"
TAR_FILE="/tmp/hospital_ha_logs_${TIMESTAMP}.tar.gz"

log_info "=== THU THẬP NHẬT KÝ HỆ THỐNG PHỤC VỤ CHẨN ĐOÁN & BÁO CÁO ==="
mkdir -p "${LOG_ARCHIVE_DIR}"

log_info "Thu thập nhật ký systemd (Journalctl)..."
journalctl -u patroni.service -n 1000 --no-pager > "${LOG_ARCHIVE_DIR}/patroni_journal.log" 2>&1 || true
journalctl -u etcd.service -n 1000 --no-pager > "${LOG_ARCHIVE_DIR}/etcd_journal.log" 2>&1 || true
journalctl -u haproxy.service -n 1000 --no-pager > "${LOG_ARCHIVE_DIR}/haproxy_journal.log" 2>&1 || true

log_info "Thu thập nhật ký PostgreSQL..."
PG_VER="${PG_VERSION:-14}"
if [[ -d "/var/lib/postgresql/${PG_VER}/main/log" ]]; then
    cp -r "/var/lib/postgresql/${PG_VER}/main/log" "${LOG_ARCHIVE_DIR}/postgresql_logs" || true
elif [[ -d /var/log/postgresql ]]; then
    cp -r /var/log/postgresql "${LOG_ARCHIVE_DIR}/postgresql_logs" || true
fi

log_info "Thu thập nhật ký pgBackRest..."
if [[ -d /var/log/pgbackrest ]]; then
    cp -r /var/log/pgbackrest "${LOG_ARCHIVE_DIR}/pgbackrest_logs" || true
fi

log_info "Thu thập trạng thái cụm hiện tại..."
{
    echo "=== DATE: $(date) ==="
    echo "=== HOSTNAME: $(hostname) ==="
    echo "=== IP ADDR ==="
    ip -br a
    echo "=== DISK USAGE ==="
    df -h
    echo "=== PATRONI TOPOLOGY ==="
    patronictl -c /etc/patroni/patroni.yml list 2>&1 || true
} > "${LOG_ARCHIVE_DIR}/system_snapshot.txt"

# Đóng gói tar.gz
tar -czf "${TAR_FILE}" -C /tmp "hospital_ha_logs_${TIMESTAMP}"
rm -rf "${LOG_ARCHIVE_DIR}"

log_success "Đã đóng gói toàn bộ log hệ thống vào tệp: ${TAR_FILE}"
