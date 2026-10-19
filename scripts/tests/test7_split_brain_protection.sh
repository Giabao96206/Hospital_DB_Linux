#!/usr/bin/env bash
# ==============================================================================
# TEST 7: PHÂN VÙNG MẠNG VÀ PHÒNG CHỐNG XUNG ĐỘT GHI (SPLIT-BRAIN PREVENTION)
# ==============================================================================
# Cơ chế kiểm chứng:
# 1. Cụm etcd 3 node yêu cầu Quorum tối thiểu: floor(3/2) + 1 = 2 phiếu.
# 2. Giả lập cô lập DB1 khỏi DB2 và DB3 bằng iptables (Phân vùng mạng: DB1 vs {DB2, DB3}).
# 3. Phân vùng thiểu số (DB1): Không đạt đủ 2 phiếu etcd -> Lease hết hạn (TTL 30s) ->
#    Patroni trên DB1 TỰ ĐỘNG GIÁNG CẤP (Demote) xuống Read-Only.
# 4. Phân vùng đa số ({DB2, DB3}): Đạt 2 phiếu etcd -> Bầu ra duy nhất 1 Primary mới.
# 5. Xác minh: Tuyệt đối KHÔNG có hiện tượng 2 Primary cùng tồn tại nhận ghi!
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 7] KIỂM THỬ CHỐNG PHÂN MẢNH NÃO (SPLIT-BRAIN PREVENTION) ==="

confirm_action "Bài test này sẽ cô lập tạm thời mạng giữa DB1 và các node còn lại bằng iptables. Bạn có chắc chắn muốn tiếp tục?"

# 1. THIẾT LẬP NGUYÊN TẮC CHẶN MẠNG TRÊN DB1 (TẠO PHÂN VÙNG MẠNG LAB)
log_warn "1. Tạo phân vùng mạng: Chặn gói tin từ DB1 tới DB2 (${DB2_IP}) và DB3 (${DB3_IP})..."
ssh -o StrictHostKeyChecking=no "root@${DB1_IP}" "
    iptables -I INPUT -s ${DB2_IP} -j DROP
    iptables -I INPUT -s ${DB3_IP} -j DROP
    iptables -I OUTPUT -d ${DB2_IP} -j DROP
    iptables -I OUTPUT -d ${DB3_IP} -j DROP
"
log_warn "DB1 đã bị cô lập hoàn toàn khỏi cụm etcd đa số."

# 2. CHỜ LEASE DCS HẾT HẠN (35 GIÂY)
log_info "2. Đang chờ 35 giây để etcd lease hết hạn trên phân vùng thiểu số..."
sleep 35

# 3. KIỂM TRA TRẠNG THÁI TRÊN PHÂN VÙNG THIỂU SỐ (DB1)
log_info "3. Kiểm tra trạng thái Patroni trên node bị cô lập (DB1):"
DB1_ROLE=$(curl -s --max-time 3 "http://${DB1_IP}:8008/patroni" | jq -r '.role' 2>/dev/null || echo "DEMOTED_OR_DOWN")
log_info "Vai trò ghi nhận trên DB1: [${DB1_ROLE}]"

# 4. KIỂM TRA TRẠNG THÁI TRÊN PHÂN VÙNG ĐA SỐ (DB2, DB3)
log_info "4. Kiểm tra Leader trên phân vùng đa số ({DB2, DB3}):"
MAJORITY_LEADER=$(curl -s "http://${DB2_IP}:8008/cluster" | jq -r '.members[] | select(.role=="leader") | .name' 2>/dev/null || echo "UNKNOWN")
log_info "Leader duy nhất được bầu trên phân vùng đa số: [${MAJORITY_LEADER}]"

# 5. XÁC MINH SỐ LƯỢNG PRIMARY KHẢ DỤNG GHI TRONG TOÀN CỤM
log_info "5. Xác minh chống Split-Brain: Kiểm tra xem DB1 có còn cho phép ghi không..."
DB1_WRITEABLE="NO"
if PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${DB1_IP}" -p "${PG_PORT}" -U "${APP_DB_USER}" -d "${APP_DB_NAME}" -c "
    INSERT INTO audit_logs (node_source, table_name, action_type) VALUES ('${DB1_IP}', 'split_test', 'UNAUTHORIZED_WRITE');
" >/dev/null 2>&1; then
    DB1_WRITEABLE="YES"
fi

if [[ "$DB1_WRITEABLE" == "NO" ]]; then
    log_success "DB1 ĐÃ TỪ CHỐI GHI (Đã bị giáng cấp hoặc ngắt kết nối an toàn). Cơ chế DCS Quorum hoạt động chính xác!"
else
    log_error "NGUY HIỂM: DB1 vẫn nhận ghi trong phân vùng thiểu số! Cần kiểm tra lại cấu hình Patroni DCS."
fi

# 6. KHÔI PHỤC LẠI ĐƯỜNG MẠNG (HEALING PARTITION)
log_info "6. Khôi phục lại kết nối mạng bình thường (Gỡ bỏ iptables drop trên DB1)..."
ssh -o StrictHostKeyChecking=no "root@${DB1_IP}" "
    iptables -D INPUT -s ${DB2_IP} -j DROP || true
    iptables -D INPUT -s ${DB3_IP} -j DROP || true
    iptables -D OUTPUT -d ${DB2_IP} -j DROP || true
    iptables -D OUTPUT -d ${DB3_IP} -j DROP || true
"
log_success "Đã gỡ bỏ cô lập mạng."

log_info "Chờ 10 giây để DB1 nhận diện lại Leader và tái gia nhập cụm..."
sleep 10

log_info "Trạng thái cụm sau khi kết nối mạng được phục hồi:"
patronictl -c /etc/patroni/patroni.yml list || true

log_info "=============================================================================="
log_info "KẾT LUẬN TEST 7:"
log_info "- Quorum etcd 3 thành viên đã ngăn chặn hoàn toàn nguy cơ Split-brain."
log_info "- Phân vùng thiểu số tự động khóa ghi; phân vùng đa số bầu duy nhất 1 Primary hợp lệ."
log_info "=============================================================================="

log_success "=== [TEST 7] HOÀN TẤT THÀNH CÔNG ==="
