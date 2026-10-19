#!/usr/bin/env bash
# ==============================================================================
# INSTALL POSTGRESQL & PATRONI ON DB NODES (DB1, DB2, DB3)
# Tương thích cả Ubuntu 22.04 LTS (Jammy) và Ubuntu 24.04 LTS (Noble)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

# Tự động nhận diện phiên bản Ubuntu (jammy = 22.04, noble = 24.04)
UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || grep 'VERSION_CODENAME' /etc/os-release | cut -d= -f2)"
log_info "Hệ điều hành phát hiện: Ubuntu (${UBUNTU_CODENAME})"

# Nếu chạy Ubuntu 22.04 và chưa đặt PG_VERSION trong .env, mặc định hạ xuống PostgreSQL 14
PG_VER="${PG_VERSION:-14}"
if [[ "$UBUNTU_CODENAME" == "jammy" && "$PG_VER" == "16" ]]; then
    log_info "Bạn đang dùng Ubuntu 22.04 (Jammy). Có thể dùng PostgreSQL 14 (chuẩn gốc) hoặc PostgreSQL 16 qua PGDG Jammy."
fi

log_info "=== BẮT ĐẦU CÀI ĐẶT POSTGRESQL ${PG_VER} VÀ PATRONI ==="

# 1. DỌN DẸP REPOSITORY BỊ XUNG ĐỘT (NẾU CÓ TỪ LẦN TRƯỚC)
rm -f /etc/apt/sources.list.d/pgdg.list
dpkg --configure -a || true
apt-get clean

# 2. CẤU HÌNH KHO GÓI PGDG THEO ĐÚNG CODENAME CỦA HỆ ĐIỀU HÀNH
log_info "Cài đặt khóa ký và cấu hình kho PGDG cho ${UBUNTU_CODENAME}..."
install -d /etc/apt/keyrings
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg --yes

echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt ${UBUNTU_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list

apt-get update -y -qq

# 3. CÀI ĐẶT CÁC GÓI PHẦN MỀM BẮT BUỘC
log_info "Cài đặt PostgreSQL ${PG_VER}, Patroni và các thư viện liên quan..."
apt-get install -y -qq \
    "postgresql-${PG_VER}" \
    "postgresql-contrib-${PG_VER}" \
    "postgresql-client-${PG_VER}" \
    patroni \
    python3-etcd \
    python3-psycopg2 \
    pgbackrest \
    lz4

# 4. DỪNG VÀ HỦY CỤM MAIN MẶC ĐỊNH
# Patroni cần trực tiếp khởi tạo và quản trị data_dir. Cụm mặc định do apt tạo ra
# sẽ gây xung đột cổng 5432 và thư mục dữ liệu nếu không được xóa trước.
log_info "Dừng và hủy cụm PostgreSQL mặc định do apt tự tạo..."
if pg_lsclusters | grep -q "${PG_VER}.*main"; then
    pg_dropcluster "${PG_VER}" main --stop || true
    log_success "Đã xóa cụm PostgreSQL ${PG_VER} mặc định thành công."
fi

# Tắt tự khởi động dịch vụ postgresql tiêu chuẩn của hệ thống
# Vì Patroni sẽ là tiến trình cha trực tiếp quản lý PostgreSQL!
systemctl stop postgresql || true
systemctl disable postgresql || true
log_success "Đã vô hiệu hóa dịch vụ postgresql.service tiêu chuẩn (để Patroni làm chủ)."

# 5. CHUẨN BỊ THƯ MỤC CẤU HÌNH CHO PATRONI & DỮ LIỆU
log_info "Khởi tạo thư mục /etc/patroni..."
mkdir -p /etc/patroni
chown -R postgres:postgres /etc/patroni
chmod 700 /etc/patroni

TARGET_DATA_DIR="${PG_DATA_DIR:-/var/lib/postgresql/${PG_VER}/main}"
mkdir -p "${TARGET_DATA_DIR}"
chown -R postgres:postgres /var/lib/postgresql
chmod 700 "${TARGET_DATA_DIR}"

log_success "=== CÀI ĐẶT POSTGRESQL ${PG_VER} & PATRONI HOÀN TẤT ==="
