#!/usr/bin/env bash
# ==============================================================================
# VERIFY POSTGRESQL STREAMING REPLICATION & PATRONI CLUSTER HEALTH
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== KIỂM TRA TÌNH TRẠNG CỤM PATRONI VÀ STREAMING REPLICATION ==="

# 1. KIỂM TRA TRẠNG THÁI CỤM PATRONI TỪ DCS (ETCD)
if command -v patronictl >/dev/null 2>&1 && [[ -f /etc/patroni/patroni.yml ]]; then
    log_info "1. Danh sách thành viên cụm Patroni (patronictl topology):"
    patronictl -c /etc/patroni/patroni.yml list
else
    log_warn "Không tìm thấy patronictl trên máy này. Đang kiểm tra qua REST API hoặc psql..."
fi

# 2. KIỂM TRA VAI TRÒ NODE HIỆN TẠI (PRIMARY HAY STANDBY)
log_info "2. Kiểm tra vai trò node hiện tại qua psql:"
sudo -u postgres psql -x -c "
SELECT 
    inet_server_addr() AS server_ip,
    CASE WHEN pg_is_in_recovery() THEN 'STANDBY (READ-ONLY)' ELSE 'PRIMARY (LEADER)' END AS current_role,
    CASE WHEN NOT pg_is_in_recovery() THEN pg_current_wal_lsn() ELSE NULL END AS primary_current_lsn,
    CASE WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn() ELSE NULL END AS standby_received_lsn,
    CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE NULL END AS standby_replayed_lsn;
" || true

# 3. NẾU LÀ PRIMARY: HIỂN THỊ CHI TIẾT CÁC STANDBY ĐANG NHẬN DỮ LIỆU
log_info "3. Chi tiết các kết nối Streaming Replication (pg_stat_replication):"
sudo -u postgres psql -c "
SELECT 
    application_name,
    client_addr,
    state,
    sync_state,
    sync_priority,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
    ROUND(pg_wal_lsn_diff(sent_lsn, replay_lsn) / 1024.0 / 1024.0, 3) AS lag_mb
FROM pg_stat_replication;
" || true

# 4. KIỂM TRA CÁC REPLICATION SLOTS
log_info "4. Danh sách và trạng thái Replication Slots:"
sudo -u postgres psql -c "
SELECT 
    slot_name,
    plugin,
    slot_type,
    active,
    active_pid,
    wal_status
FROM pg_replication_slots;
" || true

log_success "=== HOÀN TẤT KIỂM TRA REPLICATION ==="
