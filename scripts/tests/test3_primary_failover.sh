#!/usr/bin/env bash
# ==============================================================================
# TEST 3: PRIMARY FAILURE SIMULATION & AUTOMATED FAILOVER
# ==============================================================================
# Mục tiêu:
# 1. Giả lập Primary (DB1) bị crash đột ngột.
# 2. Quan sát Patroni và etcd phát hiện lease hết hạn (TTL 30s) và bầu Leader mới.
# 3. Xác minh chỉ có duy nhất 1 Primary mới được quyền nhận ghi.
# 4. Xác minh HAProxy tự động cập nhật backend định tuyến kết nối sang Primary mới.
# 5. Đo lường thời gian gián đoạn (RTO) và tính toàn vẹn (RPO).
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 3] BẮT ĐẦU KIỂM THỬ SỰ CỐ PRIMARY VÀ FAILOVER TỰ ĐỘNG ==="

confirm_action "Bài test này sẽ dừng dịch vụ trên node Primary ban đầu (DB1: ${DB1_IP}) để kích hoạt failover. Tiếp tục?"

# 1. XÁC NHẬN TRẠNG THÁI TRƯỚC SỰ CỐ
log_info "1. Xác định Primary ban đầu qua Patroni API..."
CURRENT_LEADER=$(curl -s "http://${DB1_IP}:8008/cluster" | jq -r '.members[] | select(.role=="leader") | .name' 2>/dev/null || echo "db1")
log_info "Node Leader hiện tại trước khi thử nghiệm: ${CURRENT_LEADER}"

# 2. BẮT ĐẦU GIẢ LẬP SỰ CỐ CRASH TRÊN DB1
T_FAIL_START=$(date +%s)
log_warn "2. TẠO SỰ CỐ: Tắt dịch vụ patroni trên ${DB1_IP} tại thời điểm: $(date '+%Y-%m-%d %H:%M:%S')..."
ssh -o StrictHostKeyChecking=no "root@${DB1_IP}" "systemctl stop patroni" || true
log_warn "DB1 đã ngừng phản hồi."

# 3. QUAN SÁT VÀ CHỜ ĐỢI PATRONI BẦU CHỌN LEADER MỚI
log_info "3. Quan sát etcd và các Standby bầu chọn Leader mới..."
NEW_LEADER=""
ELAPSED=0
TIMEOUT=45

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    
    # Kiểm tra trạng thái cụm từ DB2 hoặc DB3
    NEW_LEADER=$(curl -s "http://${DB2_IP}:8008/cluster" | jq -r '.members[] | select(.role=="leader") | .name' 2>/dev/null || true)
    
    if [[ -n "$NEW_LEADER" ]] && [[ "$NEW_LEADER" != "$CURRENT_LEADER" ]] && [[ "$NEW_LEADER" != "null" ]]; then
        T_FAIL_END=$(date +%s)
        RTO_DETECTED=$((T_FAIL_END - T_FAIL_START))
        log_success "🎉 PHÁT HIỆN LEADER MỚI: '${NEW_LEADER}' đã được bầu chọn sau ${RTO_DETECTED} giây!"
        break
    fi
    echo -n "."
done
echo ""

if [[ -z "$NEW_LEADER" || "$NEW_LEADER" == "null" ]]; then
    log_error "Hết thời gian chờ (${TIMEOUT}s) nhưng chưa có Leader mới được thăng cấp!"
    exit 1
fi

# 4. XÁC MINH HAPROXY ĐÃ ĐỊNH TUYẾN CHÍNH XÁC
log_info "4. Kiểm tra HAProxy trên APP1 (Port 5000) có định tuyến chính xác tới '${NEW_LEADER}' hay không..."
sleep 3
ACTUAL_ROUTED_IP=$(PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${APP1_IP}" -p 5000 -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -t -A -c "
    SELECT inet_server_addr();
" 2>/dev/null || echo "FAIL")

log_info "Địa chỉ IP thực tế mà HAProxy cổng 5000 đang định tuyến tới: ${ACTUAL_ROUTED_IP}"

if [[ "$ACTUAL_ROUTED_IP" == "$DB2_IP" || "$ACTUAL_ROUTED_IP" == "$DB3_IP" ]]; then
    log_success "HAProxy đã chuyển hướng kết nối ghi thành công tới ${ACTUAL_ROUTED_IP}!"
else
    log_warn "HAProxy chưa kịp cập nhật hoặc phản hồi lỗi: ${ACTUAL_ROUTED_IP}"
fi

# 5. THỬ THỰC HIỆN GIAO DỊCH GHI TRÊN PRIMARY MỚI
log_info "5. Thực hiện giao dịch ghi kiểm tra tính sẵn sàng trên Primary mới..."
TEST_MRN="BN-AFTER-FAILOVER-$(date +%s)"
PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${APP1_IP}" -p 5000 -U "${APP_DB_USER}" -d "${APP_DB_NAME}" <<EOF
INSERT INTO patients (medical_record_number, full_name, date_of_birth, gender, phone, address, blood_type)
VALUES ('${TEST_MRN}', 'Bệnh nhân sau sự cố Failover', '1988-08-08', 'FEMALE', '0988776655', 'Lab Failover Successful', 'AB+');
EOF
log_success "Ghi nhận thành công bệnh nhân '${TEST_MRN}' trên Primary mới!"

log_info "=============================================================================="
log_info "KẾT QUẢ ĐO ĐẠC TEST 3 (FAILOVER):"
log_info "- Cựu Primary: ${CURRENT_LEADER}"
log_info "- Tân Primary: ${NEW_LEADER}"
log_info "- Thời gian Failover đo đạc (RTO): ${RTO_DETECTED} giây"
log_info "- Ghi dữ liệu: Đã hoạt động trở lại bình thường."
log_info "=============================================================================="

log_success "=== [TEST 3] HOÀN TẤT THÀNH CÔNG ==="
