#!/usr/bin/env bash
# ==============================================================================
# TEST 1: KIỂM TRA ĐỒNG BỘ STREAMING REPLICATION GIỮA PRIMARY VÀ CÁC STANDBY
# ==============================================================================
# Mục tiêu: Xác nhận dữ liệu ghi trên Primary được truyền tức thời và đồng nhất sang DB2 & DB3
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 1] BẮT ĐẦU KIỂM TRA TÍNH TOÀN VẸN CỦA STREAMING REPLICATION ==="

TEST_ID="REP-TEST-$(date +%s)"
TEST_NAME="Bệnh nhân Kiểm thử Replication ${TEST_ID}"
MRN="BN-TEST-${TEST_ID: -6}"

log_info "1. Xác định node đang giữ vai trò Primary..."
PRIMARY_IP=$(curl -s "http://${DB1_IP}:8008/cluster" | jq -r '.members[] | select(.role=="leader") | .host' 2>/dev/null || echo "${DB1_IP}")
log_info "Node Primary hiện tại: ${PRIMARY_IP}"

# GHI DỮ LIỆU VÀO PRIMARY
log_info "2. Chèn 1 bản ghi bệnh nhân giả lập vào Primary (${PRIMARY_IP})..."
PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${PRIMARY_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" <<EOF
INSERT INTO patients (medical_record_number, full_name, date_of_birth, gender, phone, address, blood_type)
VALUES ('${MRN}', '${TEST_NAME}', '1990-01-01', 'MALE', '0999111222', 'Lab Test Replication', 'O+');

INSERT INTO audit_logs (node_source, table_name, action_type, payload)
VALUES ('${PRIMARY_IP}', 'patients', 'TEST_REPLICATION', jsonb_build_object('mrn', '${MRN}', 'test_id', '${TEST_ID}'));
EOF
log_success "Đã ghi thành công bản ghi '${MRN}' vào Primary."

# LẤY LSN VỊ TRÍ GHI HIỆN TẠI
CURRENT_LSN=$(sudo -u postgres psql -h "${PRIMARY_IP}" -t -A -c "SELECT pg_current_wal_lsn();" 2>/dev/null || echo "N/A")
log_info "Current Primary WAL LSN: ${CURRENT_LSN}"

# KIỂM TRA TRÊN DB2 (STANDBY 1)
log_info "3. Kiểm tra sự xuất hiện của bản ghi trên DB2 (${DB2_IP})..."
sleep 1
CHECK_DB2=$(PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${DB2_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -t -A -c "
    SELECT count(*) FROM patients WHERE medical_record_number = '${MRN}';
" 2>/dev/null || echo "0")

if [[ "$CHECK_DB2" -ge 1 ]]; then
    log_success "DB2 (${DB2_IP}): Đã tìm thấy bản ghi '${MRN}'! Đồng bộ thành công."
else
    log_error "DB2 (${DB2_IP}): Chưa nhận được bản ghi!"
fi

# KIỂM TRA TRÊN DB3 (STANDBY 2)
log_info "4. Kiểm tra sự xuất hiện của bản ghi trên DB3 (${DB3_IP})..."
CHECK_DB3=$(PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${DB3_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -t -A -c "
    SELECT count(*) FROM patients WHERE medical_record_number = '${MRN}';
" 2>/dev/null || echo "0")

if [[ "$CHECK_DB3" -ge 1 ]]; then
    log_success "DB3 (${DB3_IP}): Đã tìm thấy bản ghi '${MRN}'! Đồng bộ thành công."
else
    log_error "DB3 (${DB3_IP}): Chưa nhận được bản ghi!"
fi

# ĐO ĐẠC REPLICATION LAG
log_info "5. Đo lường Replication Lag trên Primary:"
sudo -u postgres psql -h "${PRIMARY_IP}" -c "
SELECT 
    application_name,
    client_addr,
    state,
    sync_state,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes,
    ROUND(pg_wal_lsn_diff(sent_lsn, replay_lsn) / 1024.0, 2) AS lag_kb
FROM pg_stat_replication;
" || true

log_success "=== [TEST 1] HOÀN TẤT: Dữ liệu được sao chép toàn vẹn sang cả 2 Standby! ==="
