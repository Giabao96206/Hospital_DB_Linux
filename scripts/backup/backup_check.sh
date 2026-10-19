#!/usr/bin/env bash
# ==============================================================================
# CHECK PGBACKREST BACKUP STATUS & INTEGRITY (RUNS ON MON1)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

STANZA="${PGBACKREST_STANZA:-hospital_cluster}"

log_info "=== KIỂM TRA TRẠNG THÁI KHO LƯU TRỮ PGBACKREST (STANZA: ${STANZA}) ==="

sudo -u postgres pgbackrest --stanza="${STANZA}" info

log_info "Kiểm tra kết nối và tính hợp lệ của Stanza..."
sudo -u postgres pgbackrest --stanza="${STANZA}" check

log_success "Kho sao lưu hoạt động bình thường, WAL archiving được đồng bộ đầy đủ."
