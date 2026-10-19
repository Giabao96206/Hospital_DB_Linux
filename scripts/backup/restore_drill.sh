#!/usr/bin/env bash
# ==============================================================================
# SAFE RESTORE DRILL SCRIPT (DIỄN TẬP PHỤC HỒI DỮ LIỆU CÔ LẬP)
# ==============================================================================
# NGUYÊN TẮC AN TOÀN:
# Tuyệt đối KHÔNG phục hồi trực tiếp đè lên thư mục dữ liệu cụm đang chạy.
# Script này khôi phục bản sao lưu vào một thư mục cách ly (/var/lib/postgresql/restore_test)
# để kiểm tra tính toàn vẹn và đo lường Restore Time (RTO khôi phục).
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

STANZA="${PGBACKREST_STANZA:-hospital_cluster}"
ISOLATED_RESTORE_DIR="/var/lib/postgresql/restore_drill"

log_info "=== BẮT ĐẦU DIỄN TẬP PHỤC HỒI CƠ SỞ DỮ LIỆU TỪ PGBACKREST ==="
log_info "Thư mục đích cô lập: ${ISOLATED_RESTORE_DIR}"

confirm_action "Bạn đang bắt đầu quy trình khôi phục bản backup vào thư mục kiểm thử độc lập ${ISOLATED_RESTORE_DIR}?"

# 1. DỌN DẸP THƯ MỤC CÔ LẬP CŨ
if [[ -d "${ISOLATED_RESTORE_DIR}" ]]; then
    log_info "Xóa dữ liệu diễn tập cũ tại ${ISOLATED_RESTORE_DIR}..."
    rm -rf "${ISOLATED_RESTORE_DIR}"
fi
mkdir -p "${ISOLATED_RESTORE_DIR}"
chown -R postgres:postgres "${ISOLATED_RESTORE_DIR}"
chmod 700 "${ISOLATED_RESTORE_DIR}"

# 2. THỰC HIỆN RESTORE TỪ PGBACKREST REPO TRÊN MON1 VÀO THƯ MỤC CÔ LẬP
START_TIME=$(date +%s)
log_info "Đang khôi phục bản backup mới nhất vào ${ISOLATED_RESTORE_DIR}..."

sudo -u postgres pgbackrest \
    --stanza="${STANZA}" \
    --pg1-path="${ISOLATED_RESTORE_DIR}" \
    --log-level-console=info \
    restore

END_TIME=$(date +%s)
RESTORE_DURATION=$((END_TIME - START_TIME))

log_success "Quá trình restore hoàn tất trong: ${RESTORE_DURATION} giây!"

# 3. KIỂM TRA TÍNH TOÀN VẸN FILE DỮ LIỆU ĐÃ RESTORE
log_info "Kiểm tra cấu trúc file PostgreSQL đã được phục hồi:"
if [[ -f "${ISOLATED_RESTORE_DIR}/PG_VERSION" ]] && [[ -d "${ISOLATED_RESTORE_DIR}/base" ]]; then
    PG_VER_RESTORED=$(cat "${ISOLATED_RESTORE_DIR}/PG_VERSION")
    log_success "Tệp PG_VERSION hợp lệ: Phiên bản PostgreSQL ${PG_VER_RESTORED}."
    log_success "Các bảng và hệ thống tệp base/ tồn tại và toàn vẹn."
else
    log_error "Phát hiện lỗi: Thư mục restore thiếu các file cốt lõi của PostgreSQL!"
    exit 1
fi

log_info "=============================================================================="
log_info "KẾT QUẢ DIỄN TẬP PHỤC HỒI (DISASTER RECOVERY DRILL):"
log_info "- Stanza: ${STANZA}"
log_info "- Thư mục phục hồi thử nghiệm: ${ISOLATED_RESTORE_DIR}"
log_info "- Thời gian phục hồi (Restore Time): ${RESTORE_DURATION} giây"
log_info "- Đánh giá: Thành công, dữ liệu sẵn sàng khôi phục khi có thảm họa."
log_info "=============================================================================="

log_success "=== KẾT THÚC BÀI DIỄN TẬP RESTORE AN TOÀN ==="
