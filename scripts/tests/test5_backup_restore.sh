#!/usr/bin/env bash
# ==============================================================================
# TEST 5: KIỂM TRA KHÔI PHỤC DỮ LIỆU TỪ PGBACKREST BACKUP
# ==============================================================================
# Kịch bản:
# 1. Thực hiện tạo một bản backup mới nhất trên MON1.
# 2. Khôi phục bản backup vào thư mục môi trường diễn tập cô lập (/var/lib/postgresql/restore_drill).
# 3. Xác minh cấu trúc schema, số bản ghi và tính nhất quán dữ liệu.
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== [TEST 5] BẮT ĐẦU KIỂM THỬ KHÔI PHỤC TỪ BẢN SAO LƯU PGBACKREST ==="

# 1. TẠO BẢN SAO LƯU MỚI TRÊN MON1
log_info "1. Kích hoạt sao lưu toàn phần (Full Backup) trên MON1..."
ssh -o StrictHostKeyChecking=no "root@${MON1_IP}" \
    "sudo -u postgres pgbackrest --stanza=${PGBACKREST_STANZA:-hospital_cluster} --type=full backup"

# 2. CHẠY KỊCH BẢN DIỄN TẬP PHỤC HỒI CÔ LẬP
log_info "2. Thực thi diễn tập phục hồi vào thư mục cách ly..."
ssh -o StrictHostKeyChecking=no "root@${DB1_IP}" \
    "FORCE_CONFIRM=true bash -s" < "${SCRIPT_DIR}/../backup/restore_drill.sh"

log_success "=== [TEST 5] DIỄN TẬP KHÔI PHỤC BACKUP THÀNH CÔNG ==="
