-- ==============================================================================
-- DATABASE SEED DATA: hospital_db
-- Dữ liệu giả lập chuẩn dùng trong môi trường Lab & Thực hành kiểm thử HA
-- TUYỆT ĐỐI KHÔNG SỬ DỤNG THÔNG TIN BỆNH NHÂN THẬT
-- ==============================================================================

-- 1. CHÈN DANH MỤC KHOA / PHÒNG BAN
INSERT INTO departments (department_code, name, description, building, floor_number, hotline)
VALUES 
    ('EMERG', 'Khoa Cấp Cứu', 'Tiếp nhận và xử trí cấp cứu 24/7 cho mọi đối tượng bệnh nhân', 'Khu A', 1, '024-3825-1115'),
    ('INTMED', 'Khoa Nội Tổng Hợp', 'Khám, chẩn đoán và điều trị nội khoa các bệnh lý mạn tính', 'Khu B', 2, '024-3825-2221'),
    ('SURG', 'Khoa Ngoại Tổng Quát', 'Phẫu thuật ngoại khoa đường tiêu hóa, gan mật và chấn thương', 'Khu B', 3, '024-3825-3334'),
    ('PEDI', 'Khoa Nhi', 'Khám và điều trị chuyên sâu các bệnh lý trẻ em dưới 16 tuổi', 'Khu C', 1, '024-3825-4448'),
    ('CARDIO', 'Khoa Tim Mạch', 'Chẩn đoán và can thiệp điều trị bệnh lý tim mạch, huyết áp', 'Khu C', 3, '024-3825-5559')
ON CONFLICT (department_code) DO NOTHING;

-- 2. CHÈN BÁC SĨ MẪU
INSERT INTO doctors (department_id, employee_code, full_name, specialization, license_number, phone, email, degree)
VALUES 
    (1, 'DOC-EM-001', 'BS. Nguyễn Văn Hùng', 'Hồi sức cấp cứu', 'CCHN-2015-0012', '0912345601', 'hung.nv@hospital.lab', 'Bác sĩ Chuyên khoa II'),
    (1, 'DOC-EM-002', 'BS. Trần Thị Mai', 'Cấp cứu đa khoa', 'CCHN-2018-0045', '0912345602', 'mai.tt@hospital.lab', 'Thạc sĩ Y khoa'),
    (2, 'DOC-IN-001', 'BS. Lê Hoàng Nam', 'Nội tiết - Đái tháo đường', 'CCHN-2012-0089', '0912345603', 'nam.lh@hospital.lab', 'Bác sĩ Chuyên khoa I'),
    (2, 'DOC-IN-002', 'BS. Phạm Thu Trang', 'Nội tiêu hóa', 'CCHN-2016-0120', '0912345604', 'trang.pt@hospital.lab', 'Bác sĩ Chuyên khoa I'),
    (3, 'DOC-SU-001', 'BS. Vũ Tuấn Anh', 'Phẫu thuật tiêu hóa', 'CCHN-2010-0033', '0912345605', 'anh.vt@hospital.lab', 'Tiến sĩ Y học'),
    (3, 'DOC-SU-002', 'BS. Đặng Minh Quân', 'Chấn thương chỉnh hình', 'CCHN-2017-0201', '0912345606', 'quan.dm@hospital.lab', 'Thạc sĩ Y khoa'),
    (4, 'DOC-PE-001', 'BS. Hoàng Kim Oanh', 'Nhi sơ sinh', 'CCHN-2014-0155', '0912345607', 'oanh.hk@hospital.lab', 'Bác sĩ Chuyên khoa I'),
    (4, 'DOC-PE-002', 'BS. Ngô Đức Thắng', 'Nhi hô hấp', 'CCHN-2019-0310', '0912345608', 'thang.nd@hospital.lab', 'Bác sĩ Đa khoa'),
    (5, 'DOC-CA-001', 'BS. Trịnh Quốc Bảo', 'Tim mạch can thiệp', 'CCHN-2008-0005', '0912345609', 'bao.tq@hospital.lab', 'Phó Giáo sư, Tiến sĩ'),
    (5, 'DOC-CA-002', 'BS. Phan Thúy Hạnh', 'Rối loạn nhịp tim', 'CCHN-2013-0077', '0912345610', 'hanh.pt@hospital.lab', 'Thạc sĩ Y khoa')
ON CONFLICT (employee_code) DO NOTHING;

-- 3. CHÈN BỆNH NHÂN GIẢ LẬP (LAB MOCK PATIENTS)
INSERT INTO patients (medical_record_number, full_name, date_of_birth, gender, national_id, health_insurance_id, phone, email, address, blood_type, allergies, emergency_contact_name, emergency_contact_phone)
VALUES 
    ('BN-2026-0001', 'Trần Văn An', '1985-04-12', 'MALE', '001085001234', 'DN4010123456789', '0981000001', 'an.tv@mock.lab', '12 Nguyễn Trãi, Thanh Xuân, Hà Nội', 'O+', 'Không', 'Trần Thị Mẹ', '0981110001'),
    ('BN-2026-0002', 'Nguyễn Thị Bình', '1990-09-23', 'FEMALE', '001190002345', 'GD4010123456790', '0981000002', 'binh.nt@mock.lab', '45 Lê Duẩn, Hoàn Kiếm, Hà Nội', 'A+', 'Dị ứng Penicillin', 'Nguyễn Văn Bố', '0981110002'),
    ('BN-2026-0003', 'Lê Cảnh Chiến', '1978-11-05', 'MALE', '001078003456', 'TE4010123456791', '0981000003', 'chien.lc@mock.lab', '78 Hoàng Hoa Thám, Ba Đình, Hà Nội', 'B+', 'Không', 'Lê Thị Vợ', '0981110003'),
    ('BN-2026-0004', 'Phạm Hồng Dung', '2001-02-18', 'FEMALE', '001201004567', 'SV4010123456792', '0981000004', 'dung.ph@mock.lab', '15 Đại Cồ Việt, Hai Bà Trưng, Hà Nội', 'AB+', 'Không', 'Phạm Văn Bố', '0981110004'),
    ('BN-2026-0005', 'Vũ Quốc Em', '2018-06-30', 'MALE', '001218005678', 'TE4010123456793', '0981000005', 'em.vq@mock.lab', '88 Cầu Giấy, Cầu Giấy, Hà Nội', 'O-', 'Dị ứng Aspirin', 'Vũ Văn Bố', '0981110005'),
    ('BN-2026-0006', 'Đỗ Minh Giang', '1965-12-14', 'MALE', '001065006789', 'HT4010123456794', '0981000006', 'giang.dm@mock.lab', '32 Láng Hạ, Đống Đa, Hà Nội', 'O+', 'Không', 'Đỗ Thị Con', '0981110006'),
    ('BN-2026-0007', 'Bùi Mỹ Hạnh', '1995-07-08', 'FEMALE', '001195007890', 'DN4010123456795', '0981000007', 'hanh.bm@mock.lab', '64 Tây Sơn, Đống Đa, Hà Nội', 'A-', 'Không', 'Bùi Văn Bố', '0981110007'),
    ('BN-2026-0008', 'Hồ Tấn Khang', '1982-03-29', 'MALE', '001082008901', 'DN4010123456796', '0981000008', 'khang.ht@mock.lab', '90 Giải Phóng, Phương Mai, Hà Nội', 'B-', 'Không', 'Hồ Thị Chị', '0981110008'),
    ('BN-2026-0009', 'Lý Hải Long', '1992-10-10', 'MALE', '001092009012', 'DN4010123456797', '0981000009', 'long.lh@mock.lab', '22 Võ Chí Công, Tây Hồ, Hà Nội', 'AB-', 'Không', 'Lý Văn Bố', '0981110009'),
    ('BN-2026-0010', 'Dương Thúy Nga', '1989-08-17', 'FEMALE', '001189010123', 'GD4010123456798', '0981000010', 'nga.dt@mock.lab', '55 Trần Duy Hưng, Cầu Giấy, Hà Nội', 'O+', 'Không', 'Dương Văn Chồng', '0981110010')
ON CONFLICT (medical_record_number) DO NOTHING;

-- 4. CHÈN LỊCH KHÁM MẪU (appointments)
INSERT INTO appointments (appointment_code, patient_id, doctor_id, department_id, scheduled_at, status, reason_for_visit, notes)
VALUES 
    ('APT-20261017-001', 1, 1, 1, '2026-10-17 08:30:00+07', 'COMPLETED', 'Đau thắt ngực cấp tính kèm khó thở', 'Bệnh nhân có tiền sử tăng huyết áp'),
    ('APT-20261017-002', 2, 3, 2, '2026-10-17 09:00:00+07', 'COMPLETED', 'Tái khám đái tháo đường type 2 định kỳ', 'Kiểm tra đường huyết lúc đói và HbA1c'),
    ('APT-20261017-003', 3, 5, 3, '2026-10-17 09:30:00+07', 'COMPLETED', 'Đau bụng hạ sườn phải nghi sỏi mật', 'Yêu cầu siêu âm ổ bụng tổng quát'),
    ('APT-20261017-004', 4, 7, 4, '2026-10-17 10:00:00+07', 'CONFIRMED', 'Ho sốt kéo dài 3 ngày', 'Trẻ mệt mỏi, bú kém'),
    ('APT-20261017-005', 5, 9, 5, '2026-10-17 10:30:00+07', 'CONFIRMED', 'Hồi hộp đánh trống ngực, mệt khi gắng sức', 'Điện tim ECG và siêu âm tim Doppler')
ON CONFLICT (appointment_code) DO NOTHING;

-- 5. CHÈN HỒ SƠ KHÁM BỆNH (medical_records)
INSERT INTO medical_records (appointment_id, patient_id, doctor_id, examination_date, symptoms, clinical_diagnosis, icd10_code, vital_signs, treatment_plan, doctor_notes)
VALUES 
    (1, 1, 1, '2026-10-17 08:45:00+07', 'Đau tức ngực trái lan ra vai, vã mồ hôi', 'Cơn đau thắt ngực không ổn định / Nghi nhồi máu cơ tim', 'I20.0', '{"blood_pressure": "150/95", "heart_rate": 98, "temperature": 36.8, "weight_kg": 72}', 'Nhập viện theo dõi ICU, đo men tim Troponin T, điện tim liên tục', 'Cần ưu tiên cấp cứu khẩn'),
    (2, 2, 3, '2026-10-17 09:15:00+07', 'Ăn nhiều, uống nhiều, sụt cân nhẹ', 'Đái tháo đường type 2 kiểm soát chưa tối ưu', 'E11.9', '{"blood_pressure": "125/80", "heart_rate": 74, "temperature": 37.0, "weight_kg": 58}', 'Điều chỉnh liều Metformin, tư vấn chế độ ăn giảm đường', 'Tái khám sau 1 tháng'),
    (3, 3, 5, '2026-10-17 09:50:00+07', 'Đau tức hạ sườn phải sau bữa ăn nhiều dầu mỡ', 'Viêm túi mật mạn do sỏi túi mật', 'K80.1', '{"blood_pressure": "130/85", "heart_rate": 80, "temperature": 37.2, "weight_kg": 68}', 'Chỉ định phẫu thuật nội soi cắt túi mật phiên', 'Chuẩn bị xét nghiệm tiền phẫu')
ON CONFLICT (appointment_id) DO NOTHING;

-- 6. CHÈN ĐƠN THUỐC MẪU (prescriptions & prescription_items)
INSERT INTO prescriptions (record_id, patient_id, doctor_id, status, instructions)
VALUES 
    (2, 2, 3, 'DISPENSED', 'Uống thuốc đúng giờ sau bữa ăn, không tự ý ngưng thuốc')
ON CONFLICT DO NOTHING;

INSERT INTO prescription_items (prescription_id, medication_name, active_ingredient, dosage, unit, frequency, duration_days, quantity, notes)
VALUES 
    (1, 'Glucophage XR 500mg', 'Metformin Hydrochloride', '500mg', 'Viên', 'Tối 1 viên sau khi ăn no', 30, 30, 'Nuốt nguyên viên, không nhai vỡ'),
    (1, 'Amlor 5mg', 'Amlodipine Besylate', '5mg', 'Viên', 'Sáng 1 viên sau ăn sáng', 30, 30, 'Kiểm tra huyết áp định kỳ');

-- 7. CHÈN HÓA ĐƠN VIỆN PHÍ (invoices)
INSERT INTO invoices (invoice_code, patient_id, appointment_id, total_amount, discount_amount, final_amount, payment_status, payment_method, paid_at, cashier_name)
VALUES 
    ('INV-20261017-001', 1, 1, 550000.00, 440000.00, 110000.00, 'PAID', 'INSURANCE', '2026-10-17 09:30:00+07', 'Thu ngân Nguyễn Thị Lan'),
    ('INV-20261017-002', 2, 2, 320000.00, 256000.00, 64000.00, 'PAID', 'BANK_TRANSFER', '2026-10-17 10:00:00+07', 'Thu ngân Nguyễn Thị Lan')
ON CONFLICT (invoice_code) DO NOTHING;

-- 8. CHÈN TÀI KHOẢN NGƯỜI DÙNG HỆ THỐNG (Mật khẩu băm chuẩn bcrypt bằng pgcrypto)
-- Mật khẩu mặc định trong lab: Hospital@2026!
INSERT INTO users (username, password_hash, full_name, email, role, is_active)
VALUES 
    ('admin_sys', crypt('Hospital@2026!', gen_salt('bf', 10)), 'Quản trị viên Hệ thống', 'sysadmin@hospital.lab', 'ADMIN', TRUE),
    ('bs_hung', crypt('Hospital@2026!', gen_salt('bf', 10)), 'BS. Nguyễn Văn Hùng', 'hung.nv@hospital.lab', 'DOCTOR', TRUE),
    ('letan_lan', crypt('Hospital@2026!', gen_salt('bf', 10)), 'Nguyễn Thị Lan (Lễ tân)', 'lan.reception@hospital.lab', 'RECEPTIONIST', TRUE),
    ('duoc_minh', crypt('Hospital@2026!', gen_salt('bf', 10)), 'Dược sĩ Hoàng Minh', 'minh.pharm@hospital.lab', 'PHARMACIST', TRUE)
ON CONFLICT (username) DO NOTHING;
