-- ==============================================================================
-- DATABASE SCHEMA: hospital_db
-- Hệ thống: Quản lý bệnh viện với kiến trúc phân tán & HA (High Availability)
-- Hệ quản trị CSDL: PostgreSQL 16+
-- ==============================================================================

-- 1. BẬT CÁC EXTENSION CẦN THIẾT
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ĐỊNH NGHĨA FUNCTION VÀ TRIGGER TỰ ĐỘNG CẬP NHẬT updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ==============================================================================
-- 3. BẢNG DANH MỤC KHOA / PHÒNG BAN (departments)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS departments (
    department_id SERIAL PRIMARY KEY,
    department_code VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    building VARCHAR(50),
    floor_number INT,
    hotline VARCHAR(20),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TRIGGER trg_departments_updated_at
BEFORE UPDATE ON departments
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 4. BẢNG BÁC SĨ & NHÂN VIÊN Y TẾ (doctors)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS doctors (
    doctor_id SERIAL PRIMARY KEY,
    department_id INT NOT NULL REFERENCES departments(department_id) ON DELETE RESTRICT,
    employee_code VARCHAR(30) NOT NULL UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    specialization VARCHAR(100) NOT NULL,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    degree VARCHAR(50) DEFAULT 'Bác sĩ chuyên khoa',
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ON_LEAVE', 'RESIGNED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_doctors_department_id ON doctors(department_id);
CREATE INDEX idx_doctors_status ON doctors(status);

CREATE TRIGGER trg_doctors_updated_at
BEFORE UPDATE ON doctors
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 5. BẢNG BỆNH NHÂN (patients - Dữ liệu giả lập lab)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS patients (
    patient_id SERIAL PRIMARY KEY,
    medical_record_number VARCHAR(30) NOT NULL UNIQUE, -- Mã số bệnh án (MBN)
    full_name VARCHAR(150) NOT NULL,
    date_of_birth DATE NOT NULL,
    gender VARCHAR(10) NOT NULL CHECK (gender IN ('MALE', 'FEMALE', 'OTHER')),
    national_id VARCHAR(20) UNIQUE, -- Số CCCD giả lập
    health_insurance_id VARCHAR(25) UNIQUE, -- Mã thẻ BHYT giả lập
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100),
    address TEXT NOT NULL,
    blood_type VARCHAR(5) CHECK (blood_type IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    allergies TEXT DEFAULT 'Chưa ghi nhận',
    emergency_contact_name VARCHAR(150),
    emergency_contact_phone VARCHAR(20),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patients_mrn ON patients(medical_record_number);
CREATE INDEX idx_patients_national_id ON patients(national_id);
CREATE INDEX idx_patients_insurance ON patients(health_insurance_id);
CREATE INDEX idx_patients_phone ON patients(phone);

CREATE TRIGGER trg_patients_updated_at
BEFORE UPDATE ON patients
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 6. BẢNG LỊCH HẸN KHÁM (appointments)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS appointments (
    appointment_id SERIAL PRIMARY KEY,
    appointment_code VARCHAR(30) NOT NULL UNIQUE,
    patient_id INT NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    doctor_id INT NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    department_id INT NOT NULL REFERENCES departments(department_id) ON DELETE RESTRICT,
    scheduled_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' 
        CHECK (status IN ('PENDING', 'CONFIRMED', 'CHECKED_IN', 'IN_CONSULTATION', 'COMPLETED', 'CANCELLED')),
    reason_for_visit TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_appointments_patient ON appointments(patient_id);
CREATE INDEX idx_appointments_doctor ON appointments(doctor_id);
CREATE INDEX idx_appointments_scheduled_at ON appointments(scheduled_at);
CREATE INDEX idx_appointments_status ON appointments(status);

CREATE TRIGGER trg_appointments_updated_at
BEFORE UPDATE ON appointments
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 7. BẢNG HỒ SƠ KHÁM BỆNH (medical_records)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS medical_records (
    record_id SERIAL PRIMARY KEY,
    appointment_id INT UNIQUE REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    patient_id INT NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    doctor_id INT NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    examination_date TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    symptoms TEXT NOT NULL,
    clinical_diagnosis TEXT NOT NULL,
    icd10_code VARCHAR(20),
    vital_signs JSONB NOT NULL DEFAULT '{"blood_pressure": "120/80", "heart_rate": 75, "temperature": 37.0, "weight_kg": 65}',
    treatment_plan TEXT NOT NULL,
    doctor_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_med_records_patient ON medical_records(patient_id);
CREATE INDEX idx_med_records_doctor ON medical_records(doctor_id);
CREATE INDEX idx_med_records_date ON medical_records(examination_date);
CREATE INDEX idx_med_records_icd10 ON medical_records(icd10_code);

CREATE TRIGGER trg_medical_records_updated_at
BEFORE UPDATE ON medical_records
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 8. BẢNG ĐƠN THUỐC (prescriptions)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS prescriptions (
    prescription_id SERIAL PRIMARY KEY,
    record_id INT NOT NULL REFERENCES medical_records(record_id) ON DELETE CASCADE,
    patient_id INT NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    doctor_id INT NOT NULL REFERENCES doctors(doctor_id) ON DELETE RESTRICT,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'DISPENSED', 'CANCELLED')),
    instructions TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_prescriptions_record ON prescriptions(record_id);
CREATE INDEX idx_prescriptions_patient ON prescriptions(patient_id);

CREATE TRIGGER trg_prescriptions_updated_at
BEFORE UPDATE ON prescriptions
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 9. BẢNG CHI TIẾT ĐƠN THUỐC (prescription_items)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS prescription_items (
    item_id SERIAL PRIMARY KEY,
    prescription_id INT NOT NULL REFERENCES prescriptions(prescription_id) ON DELETE CASCADE,
    medication_name VARCHAR(150) NOT NULL,
    active_ingredient VARCHAR(150),
    dosage VARCHAR(50) NOT NULL,       -- Ví dụ: 500mg
    unit VARCHAR(20) NOT NULL,         -- Viên, Gói, Lọ
    frequency VARCHAR(100) NOT NULL,   -- Sáng 1 viên, Tối 1 viên sau ăn
    duration_days INT NOT NULL CHECK (duration_days > 0),
    quantity INT NOT NULL CHECK (quantity > 0),
    notes TEXT
);

CREATE INDEX idx_presc_items_prescription ON prescription_items(prescription_id);

-- ==============================================================================
-- 10. BẢNG HÓA ĐƠN VIỆN PHÍ (invoices)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS invoices (
    invoice_id SERIAL PRIMARY KEY,
    invoice_code VARCHAR(30) NOT NULL UNIQUE,
    patient_id INT NOT NULL REFERENCES patients(patient_id) ON DELETE RESTRICT,
    appointment_id INT REFERENCES appointments(appointment_id) ON DELETE SET NULL,
    total_amount NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
    discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (discount_amount >= 0),
    final_amount NUMERIC(12, 2) NOT NULL CHECK (final_amount >= 0),
    payment_status VARCHAR(20) NOT NULL DEFAULT 'UNPAID' CHECK (payment_status IN ('UNPAID', 'PAID', 'REFUNDED', 'CANCELLED')),
    payment_method VARCHAR(30) CHECK (payment_method IN ('CASH', 'CREDIT_CARD', 'BANK_TRANSFER', 'INSURANCE')),
    paid_at TIMESTAMPTZ,
    cashier_name VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_invoices_patient ON invoices(patient_id);
CREATE INDEX idx_invoices_status ON invoices(payment_status);
CREATE INDEX idx_invoices_code ON invoices(invoice_code);

CREATE TRIGGER trg_invoices_updated_at
BEFORE UPDATE ON invoices
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 11. BẢNG TÀI KHOẢN NGƯỜI DÙNG HỆ THỐNG (users - Băm mật khẩu bằng pgcrypto)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    role VARCHAR(30) NOT NULL CHECK (role IN ('ADMIN', 'DOCTOR', 'NURSE', 'RECEPTIONIST', 'PHARMACIST')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_role ON users(role);

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ==============================================================================
-- 12. BẢNG NHẬT KÝ KIỂM TOÁN GIAO DỊCH (audit_logs - Phục vụ đo lường RPO/RTO)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    log_id BIGSERIAL PRIMARY KEY,
    transaction_uuid UUID NOT NULL DEFAULT uuid_generate_v4(),
    node_source VARCHAR(50) NOT NULL, -- Ghi nhận node IP / hostname đang xử lý
    table_name VARCHAR(50) NOT NULL,
    action_type VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE, FAILOVER_TEST
    record_id INT,
    performed_by VARCHAR(50) DEFAULT 'system',
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_logs_tx ON audit_logs(transaction_uuid);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at);

-- ==============================================================================
-- 13. THIẾT LẬP PHÂN QUYỀN THEO NGUYÊN TẮC LEAST PRIVILEGE
-- ==============================================================================
-- Tạo role nếu chưa tồn tại
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'hospital_app_user') THEN
        CREATE ROLE hospital_app_user WITH LOGIN PASSWORD 'Hospital@2026!AppPass';
    ELSE
        ALTER ROLE hospital_app_user WITH PASSWORD 'Hospital@2026!AppPass';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'hospital_readonly') THEN
        CREATE ROLE hospital_readonly WITH LOGIN PASSWORD 'Hospital@2026!Read';
    ELSE
        ALTER ROLE hospital_readonly WITH PASSWORD 'Hospital@2026!Read';
    END IF;
END $$;

-- Phân quyền cho tài khoản ứng dụng API (hospital_app_user):
-- Chỉ cấp quyền CRUD trên các bảng, USAGE trên sequence. KHÔNG CẤP QUYỀN SUPERUSER / DDL.
GRANT CONNECT ON DATABASE hospital_db TO hospital_app_user;
GRANT USAGE ON SCHEMA public TO hospital_app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO hospital_app_user;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO hospital_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO hospital_app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO hospital_app_user;

-- Phân quyền cho tài khoản báo cáo (hospital_readonly)
GRANT CONNECT ON DATABASE hospital_db TO hospital_readonly;
GRANT USAGE ON SCHEMA public TO hospital_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO hospital_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO hospital_readonly;
