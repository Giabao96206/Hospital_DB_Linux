#!/usr/bin/env bash
# ==============================================================================
# EXECUTE FULL BACKUP VIA PGBACKREST (RUNS ON MON1)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== BẮT ĐẦU QUY TRÌNH SAO LƯU TOÀN PHẦN (FULL BACKUP) TRÊN MON1 ==="

STANZA="${PGBACKREST_STANZA:-hospital_cluster}"

# 1. KIỂM TRA VÀ KHỞI TẠO STANZA NẾU CHƯA TỒN TẠI
log_info "1. Kiểm tra cấu hình Stanza: ${STANZA}..."
if ! sudo -u postgres pgbackrest --stanza="${STANZA}" check >/dev/null 2>&1; then
    log_warn "Stanza '${STANZA}' chưa được khởi tạo hoặc cấu hình mới. Đang chạy stanza-create..."
    sudo -u postgres pgbackrest --stanza="${STANZA}" stanza-create
    log_info "Kiểm tra lại tính kết nối stanza..."
    sudo -u postgres pgbackrest --stanza="${STANZA}" check
fi
log_success "Stanza check OK (Đã kết nối thành công tới Primary hiện tại)."

# 2. THỰC THI FULL BACKUP
START_TIME=$(date +%s)
log_info "2. Đang thực thi: pgbackrest --stanza=${STANZA} --type=full backup..."

sudo -u postgres pgbackrest --stanza="${STANZA}" --type=full --log-level-console=info backup

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_success "Sao lưu Full Backup hoàn tất trong ${DURATION} giây!"

# 3. HIỂN THỊ KẾT QUẢ VÀ TRẠNG THÁI KHO LƯU TRỮ
log_info "3. Thông tin chi tiết các bản sao lưu trong kho:"
sudo -u postgres pgbackrest --stanza="${STANZA}" info

log_success "=== QUY TRÌNH FULL BACKUP KẾT THÚC THÀNH CÔNG ==="
