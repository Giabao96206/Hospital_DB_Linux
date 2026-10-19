#!/usr/bin/env bash
# ==============================================================================
# INITIALIZE HOSPITAL DATABASE & ROLES ON PRIMARY NODE (DB1)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/00_env_loader.sh"

require_root

log_info "=== BẮT ĐẦU KHỞI TẠO CƠ SỞ DỮ LIỆU BỆNH VIỆN TRÊN $(hostname) ==="

# 1. KIỂM TRA POSTGRESQL CÓ ĐANG CHẠY VÀ LÀ PRIMARY HAY KHÔNG
IS_IN_RECOVERY=$(sudo -u postgres psql -t -A -c "SELECT pg_is_in_recovery();" 2>/dev/null || echo "error")

if [[ "$IS_IN_RECOVERY" == "error" ]]; then
    log_error "PostgreSQL chưa khởi chạy hoặc không thể kết nối tới port 5432!"
    log_error "Vui lòng đảm bảo Patroni service đã chạy: systemctl status patroni"
    exit 1
fi

if [[ "$IS_IN_RECOVERY" == "t" ]]; then
    log_error "Node hiện tại đang là STANDBY (Read-Only)! Thao tác DDL chỉ được thực thi trên PRIMARY (Leader)."
    log_info "Kiểm tra leader hiện tại bằng lệnh: patronictl -c /etc/patroni/patroni.yml list"
    exit 1
fi

log_success "Xác nhận: Node $(hostname) là PRIMARY (Read-Write Leader)."

# 2. TẠO DATABASE HOSPITAL_DB NẾU CHƯA TỒN TẠI
DB_EXISTS=$(sudo -u postgres psql -t -A -c "SELECT 1 FROM pg_database WHERE datname = 'hospital_db';" 2>/dev/null || echo "0")

if [[ "$DB_EXISTS" != "1" ]]; then
    log_info "Tạo mới cơ sở dữ liệu: hospital_db..."
    sudo -u postgres psql -c "CREATE DATABASE hospital_db WITH ENCODING 'UTF8' LC_COLLATE = 'en_US.UTF-8' LC_CTYPE = 'en_US.UTF-8';" || \
    sudo -u postgres psql -c "CREATE DATABASE hospital_db WITH ENCODING 'UTF8';"
    log_success "Cơ sở dữ liệu hospital_db đã được tạo."
else
    log_info "Cơ sở dữ liệu hospital_db đã tồn tại."
fi

# 3. NẠP SCHEMA (BẢNG, CHỈ MỤC, TRIGGER VÀ PHÂN QUYỀN)
SCHEMA_FILE="${SCRIPT_DIR}/../../database/schema.sql"
if [[ -f "$SCHEMA_FILE" ]]; then
    log_info "Nạp cấu trúc bảng và phân quyền từ ${SCHEMA_FILE}..."
    
    # Tạo bản tạm thời với mật khẩu chính xác từ .env
    TMP_SCHEMA=$(mktemp)
    cp "$SCHEMA_FILE" "$TMP_SCHEMA"
    sed -i "s/Hospital@2026!AppPass/${APP_DB_PASSWORD:-Hospital@2026!AppPass}/g" "$TMP_SCHEMA"
    sed -i "s/Hospital@2026!Read/${POSTGRES_READONLY_PASSWORD:-Hospital@2026!Read}/g" "$TMP_SCHEMA"
    
    sudo -u postgres psql -d hospital_db -f "$TMP_SCHEMA" > /dev/null
    rm -f "$TMP_SCHEMA"
    log_success "Nạp schema và phân quyền cho hospital_app_user & hospital_readonly hoàn tất."
else
    log_error "Không tìm thấy file schema: ${SCHEMA_FILE}"
    exit 1
fi

# 4. NẠP DỮ LIỆU MẪU (SEED DATA)
SEED_FILE="${SCRIPT_DIR}/../../database/seed.sql"
if [[ -f "$SEED_FILE" ]]; then
    log_info "Nạp dữ liệu giả lập y tế từ ${SEED_FILE}..."
    sudo -u postgres psql -d hospital_db -f "$SEED_FILE" > /dev/null
    log_success "Nạp dữ liệu mẫu hoàn tất."
fi

# 5. XÁC MINH SỐ LƯỢNG BẢN GHI
log_info "Kiểm tra thống kê dữ liệu sau khởi tạo:"
sudo -u postgres psql -d hospital_db -c "
SELECT 'departments' AS table_name, count(*) AS total_records FROM departments
UNION ALL
SELECT 'doctors', count(*) FROM doctors
UNION ALL
SELECT 'patients', count(*) FROM patients
UNION ALL
SELECT 'appointments', count(*) FROM appointments
UNION ALL
SELECT 'medical_records', count(*) FROM medical_records
UNION ALL
SELECT 'inpatient_admissions', count(*) FROM inpatient_admissions
UNION ALL
SELECT 'prescriptions', count(*) FROM prescriptions
UNION ALL
SELECT 'bills', count(*) FROM bills;
"

log_success "=== KHỞI TẠO CSDL BỆNH VIỆN HOÀN TẤT VÀ SẴN SÀNG REPLICATION ==="
