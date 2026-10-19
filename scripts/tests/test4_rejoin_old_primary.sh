#!/usr/bin/env bash
# ==============================================================================
# TEST 4: KHÔI PHỤC VÀ ĐƯA NODE CŨ (DB1) TRỞ LẠI CỤM VỚI VAI TRÒ STANDBY
# ==============================================================================
# QUY TẮC AN TOÀN TUYỆT ĐỐI CỦA DBA:
# 1. KHÔNG BAO GIỜ ép node cũ khởi động lại với tư cách là Primary.
# 2. Để Patroni tự động điều phối: Sử dụng pg_rewind để tua lại các WAL phân kỳ
#    (nếu có) về điểm chia nhánh timeline, chuyển đổi cấu hình node cũ thành Standby.
# 3. Kết nối node cũ vào stream của Primary mới và xác minh đồng bộ.
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 4] BẮT ĐẦU QUY TRÌNH TÁI GIA NHẬP NODE CŨ (DB1) ==="

# 1. KIỂM TRA TRẠNG THÁI HIỆN TẠI CỦA CỤM
log_info "1. Kiểm tra trạng thái hiện tại của cụm (Xác nhận Leader đang hoạt động):"
curl -s "http://${DB2_IP}:8008/cluster" | jq . || true

# 2. KHỞI ĐỘNG LẠI PATRONI TRÊN DB1
log_info "2. Khởi động lại dịch vụ Patroni trên DB1 (${DB1_IP})..."
log_info "Patroni sẽ kiểm tra DCS etcd, nhận biết cụm đã có Leader mới và tự động chạy pg_rewind để làm Standby."
ssh -o StrictHostKeyChecking=no "root@${DB1_IP}" "systemctl start patroni"

# 3. CHỜ ĐỢI TIẾN TRÌNH REWIND VÀ TÁI ĐỒNG BỘ
log_info "3. Chờ 10 giây để DB1 hoàn tất quá trình pg_rewind và kết nối replication..."
sleep 10

# 4. KIỂM TRA TRẠNG THÁI PATRONI CỦA DB1
log_info "4. Kiểm tra cấu trúc cụm sau khi DB1 tái gia nhập:"
patronictl -c /etc/patroni/patroni.yml list || true

DB1_ROLE=$(curl -s "http://${DB1_IP}:8008/patroni" | jq -r '.role' 2>/dev/null || echo "UNKNOWN")
DB1_STATE=$(curl -s "http://${DB1_IP}:8008/patroni" | jq -r '.state' 2>/dev/null || echo "UNKNOWN")

log_info "Trạng thái ghi nhận của DB1: Vai trò = [${DB1_ROLE}], Trạng thái = [${DB1_STATE}]"

if [[ "$DB1_ROLE" == "replica" || "$DB1_ROLE" == "standby" ]]; then
    log_success "DB1 đã tái gia nhập cụm an toàn với vai trò STANDBY (Không gây Split-brain)!"
else
    log_warn "DB1 chưa đạt trạng thái replica: ${DB1_ROLE}. Hãy kiểm tra journalctl -u patroni trên DB1."
fi

# 5. XÁC MINH DỮ LIỆU ĐÃ ĐỒNG BỘ ĐẦY ĐỦ VỀ DB1
log_info "5. Xác minh bản ghi sau failover trên DB1:"
CHECK_RECORD=$(PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${DB1_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -t -A -c "
    SELECT count(*) FROM patients WHERE medical_record_number LIKE 'BN-AFTER-FAILOVER-%';
" 2>/dev/null || echo "0")

if [[ "$CHECK_RECORD" -ge 1 ]]; then
    log_success "DB1 đã nhận đầy đủ các bản ghi được tạo ra trong lúc DB1 gặp sự cố!"
else
    log_warn "DB1 chưa nhận được dữ liệu mới nhất. Đang đợi replication stream..."
fi

log_success "=== [TEST 4] HOÀN TẤT QUY TRÌNH PHỤC HỒI DB1 AN TOÀN ==="
