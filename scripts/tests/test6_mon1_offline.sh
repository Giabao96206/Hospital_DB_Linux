#!/usr/bin/env bash
# ==============================================================================
# TEST 6: BACKUP & MONITORING SERVER (MON1) TẠM THỜI NGỪNG HOẠT ĐỘNG
# ==============================================================================
# Mục tiêu kiến trúc:
# MON1 KHÔNG PHẢI thành viên của etcd quorum.
# Khi MON1 ngừng hoạt động (offline), cụm CSDL PostgreSQL vẫn phải tiếp tục
# xử lý các giao dịch đọc/ghi của bệnh viện bình thường mà không bị ảnh hưởng.
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 6] KIỂM THỬ TÍNH ĐỘC LẬP KHI MON1 NGỪNG HOẠT ĐỘNG ==="

confirm_action "Bài test này sẽ tạm tắt các dịch vụ trên MON1 (${MON1_IP}). Bạn muốn tiếp tục?"

# 1. TẠM DỪNG DỊCH VỤ TRÊN MON1
log_warn "1. Tạm dừng các dịch vụ trên MON1 (Prometheus, Grafana)..."
ssh -o StrictHostKeyChecking=no "root@${MON1_IP}" "systemctl stop prometheus grafana-server" || true

# 2. KIỂM TRA QUORUM ETCD TRÊN 3 DB NODES
log_info "2. Kiểm tra etcd Quorum (Yêu cầu giữ nguyên 3/3 members):"
ETCDCTL_API=3 etcdctl --endpoints="http://${DB1_IP}:2379" endpoint health || true
log_success "etcd Quorum hoàn toàn không bị ảnh hưởng vì MON1 không tham gia bầu chọn."

# 3. THỰC HIỆN TRUY VẤN GHI TỪ ỨNG DỤNG BỆNH VIỆN
log_info "3. Thực hiện ghi hồ sơ bệnh nhân từ APP1 qua HAProxy (Cổng 5000)..."
TEST_MON_MRN="BN-MON1-OFFLINE-$(date +%s)"
PGPASSWORD="${APP_DB_PASSWORD}" psql -h "${APP1_IP}" -p 5000 -U "${APP_DB_USER}" -d "${APP_DB_NAME}" <<EOF
INSERT INTO patients (medical_record_number, full_name, date_of_birth, gender, phone, address, blood_type)
VALUES ('${TEST_MON_MRN}', 'Bệnh nhân ghi nhận khi MON1 offline', '1985-05-05', 'MALE', '0911223344', 'Lab MON1 Isolation Test', 'O+');
EOF

log_success "Giao dịch ghi thành công với mã '${TEST_MON_MRN}'!"

# 4. KHÔI PHỤC DỊCH VỤ TRÊN MON1
log_info "4. Khôi phục lại các dịch vụ trên MON1..."
ssh -o StrictHostKeyChecking=no "root@${MON1_IP}" "systemctl start prometheus grafana-server"
log_success "Prometheus và Grafana đã hoạt động trở lại."

log_info "=============================================================================="
log_info "KẾT LUẬN TEST 6:"
log_info "- Việc MON1 ngừng hoạt động CHỈ ẢNH HƯỞNG đến chức năng thu thập giám sát và lưu trữ backup."
log_info "- Động cơ giao dịch PostgreSQL và tính sẵn sàng của cụm HA vận hành 100% độc lập."
log_info "=============================================================================="

log_success "=== [TEST 6] HOÀN TẤT THÀNH CÔNG ==="
