-- ==============================================================================
-- SQL VERIFICATION SUITE: RESTORE INTEGRITY & ROW COUNTS
-- Dùng để đối chiếu số lượng và tính nhất quán dữ liệu sau khi Restore
-- ==============================================================================

SELECT 'departments' AS table_name, count(*) AS total_rows FROM departments
UNION ALL
SELECT 'doctors', count(*) FROM doctors
UNION ALL
SELECT 'patients', count(*) FROM patients
UNION ALL
SELECT 'appointments', count(*) FROM appointments
UNION ALL
SELECT 'medical_records', count(*) FROM medical_records
UNION ALL
SELECT 'prescriptions', count(*) FROM prescriptions
UNION ALL
SELECT 'prescription_items', count(*) FROM prescription_items
UNION ALL
SELECT 'invoices', count(*) FROM invoices
UNION ALL
SELECT 'users', count(*) FROM users
UNION ALL
SELECT 'audit_logs', count(*) FROM audit_logs;

-- Kiểm tra tính toàn vẹn khóa ngoại (Foreign Keys Integrity)
SELECT 'Orphaned Appointments' AS check_item, count(*) AS violations
FROM appointments a
LEFT JOIN patients p ON a.patient_id = p.patient_id
WHERE p.patient_id IS NULL;

SELECT 'Orphaned Medical Records' AS check_item, count(*) AS violations
FROM medical_records mr
LEFT JOIN patients p ON mr.patient_id = p.patient_id
WHERE p.patient_id IS NULL;
