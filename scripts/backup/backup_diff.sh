#!/usr/bin/env bash
# ==============================================================================
# EXECUTE DIFFERENTIAL BACKUP VIA PGBACKREST (RUNS ON MON1)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

log_info "=== BẮT ĐẦU SAO LƯU VI SAI (DIFFERENTIAL BACKUP) TRÊN MON1 ==="

STANZA="${PGBACKREST_STANZA:-hospital_cluster}"

START_TIME=$(date +%s)
log_info "Đang thực thi: pgbackrest --stanza=${STANZA} --type=diff backup..."

sudo -u postgres pgbackrest --stanza="${STANZA}" --type=diff --log-level-console=info backup

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log_success "Sao lưu Differential Backup hoàn tất trong ${DURATION} giây!"

log_info "Thông tin kho sao lưu:"
sudo -u postgres pgbackrest --stanza="${STANZA}" info
