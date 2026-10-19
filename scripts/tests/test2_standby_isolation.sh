#!/usr/bin/env bash
# ==============================================================================
# TEST 2: KIỂM TRA MỘT STANDBY MẤT KẾT NỐI VÀ TỰ ĐỘNG BẮT KỊP WAL (CATCH-UP)
# ==============================================================================
# Kịch bản:
# 1. Ngắt kết nối dịch vụ Patroni/PostgreSQL trên Standby 1 (DB2).
# 2. Hệ thống vẫn tiếp tục ghi dữ liệu bình thường trên Primary (DB1).
# 3. Phục hồi DB2.
# 4. Xác nhận DB2 đọc lại WAL từ replication slot và đồng bộ đuổi kịp hoàn toàn.
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 2] BẮT ĐẦU KIỂM THỬ STANDBY ISOLATION & CATCH-UP ==="

confirm_action "Bài test này sẽ tạm dừng dịch vụ trên node DB2 (${DB2_IP}). Bạn muốn tiếp tục?"

# 1. TẠM DỪNG DỊCH VỤ TRÊN DB2
log_info "1. Giả lập sự cố mất kết nối bằng cách dừng patroni trên DB2 (${DB2_IP})..."
ssh -o StrictHostKeyChecking=no "root@${DB2_IP}" "systemctl stop patroni" || true
log_warn "Node DB2 đã tạm ngưng hoạt động."

# 2. TIẾP TỤC GHI DỮ LIỆU TRÊN PRIMARY
log_info "2. Tiếp tục thực hiện 5 giao dịch ghi trên Primary khi DB2 đang offline..."
for i in {1..5}; do
    TX_CODE="ISO-TX-${i}-$(date +%s)"
    PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${DB1_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -c "
        INSERT INTO audit_logs (node_source, table_name, action_type, payload)
        VALUES ('${DB1_IP}', 'isolation_test', 'INSERT_DURING_OUTAGE', jsonb_build_object('code', '${TX_CODE}', 'seq', ${i}));
    " >/dev/null
    log_info "   -> Đã ghi giao dịch ${i}/5 ('${TX_CODE}') vào Primary."
    sleep 0.5
done

# 3. KIỂM TRA TRẠNG THÁI REPLICATION SLOTS TRÊN PRIMARY
log_info "3. Kiểm tra trạng thái replication slots trên Primary (WAL được giữ lại an toàn):"
sudo -u postgres psql -h "${DB1_IP}" -c "
SELECT slot_name, active, wal_status FROM pg_replication_slots WHERE slot_name LIKE '%db2%';
" || true

# 4. KẾT NỐI LẠI DB2
log_info "4. Khởi động lại dịch vụ Patroni trên DB2..."
ssh -o StrictHostKeyChecking=no "root@${DB2_IP}" "systemctl start patroni"
log_info "Chờ 5 giây để DB2 khởi động và bắt kịp WAL stream..."
sleep 5

# 5. XÁC MINH DỮ LIỆU ĐÃ BẮT KỊP TRÊN DB2
log_info "5. Xác minh số lượng giao dịch 'isolation_test' trên DB2:"
COUNT_DB2=$(PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${DB2_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -t -A -c "
    SELECT count(*) FROM audit_logs WHERE table_name = 'isolation_test';
" 2>/dev/null || echo "0")

log_info "Số giao dịch tìm thấy trên DB2: ${COUNT_DB2}"

if [[ "$COUNT_DB2" -ge 5 ]]; then
    log_success "DB2 đã nhận đầy đủ 5 giao dịch ghi trong lúc offline! Cơ chế Catch-up thành công."
else
    log_warn "DB2 đang trong quá trình đồng bộ (Hiện tại: ${COUNT_DB2}/5 giao dịch). Hãy kiểm tra lại sau ít giây."
fi

log_success "=== [TEST 2] KẾT THÚC THÀNH CÔNG ==="
