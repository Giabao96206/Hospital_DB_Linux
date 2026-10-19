-- ==============================================================================
-- DATABASE QUERIES & VERIFICATION SCRIPTS: hospital_db
-- Tuyển tập truy vấn kiểm tra HA, Replication và nghiệp vụ bệnh viện
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. TRUY VẤN KIỂM TRA TRẠNG THÁI NODE (PRIMARY HAY STANDBY)
-- ------------------------------------------------------------------------------
SELECT 
    inet_server_addr() AS server_ip,
    inet_server_port() AS server_port,
    current_database() AS db_name,
    current_user AS connected_user,
    CASE 
        WHEN pg_is_in_recovery() THEN 'STANDBY (READ-ONLY)'
        ELSE 'PRIMARY (READ-WRITE)'
    END AS node_role,
    CASE 
        WHEN NOT pg_is_in_recovery() THEN pg_current_wal_lsn()
        ELSE NULL 
    END AS current_wal_lsn,
    CASE 
        WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn()
        ELSE NULL 
    END AS last_wal_receive_lsn,
    CASE 
        WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn()
        ELSE NULL 
    END AS last_wal_replay_lsn;

-- ------------------------------------------------------------------------------
-- 2. TRUY VẤN GIÁM SÁT STREAMING REPLICATION (CHẠY TRÊN PRIMARY)
-- ------------------------------------------------------------------------------
SELECT 
    application_name,
    client_addr,
    client_port,
    state,
    sync_state,
    sync_priority,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replication_lag_bytes,
    ROUND(pg_wal_lsn_diff(sent_lsn, replay_lsn) / 1024.0 / 1024.0, 3) AS lag_mb
FROM pg_stat_replication;

-- ------------------------------------------------------------------------------
-- 3. TRUY VẤN KIỂM TRA REPLICATION SLOTS
-- ------------------------------------------------------------------------------
SELECT 
    slot_name,
    plugin,
    slot_type,
    active,
    active_pid,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status
FROM pg_replication_slots;

-- ------------------------------------------------------------------------------
-- 4. TRUY VẤN KIỂM TRA WAL RECEIVER (CHẠY TRÊN STANDBY)
-- ------------------------------------------------------------------------------
SELECT 
    pid,
    status,
    receive_start_lsn,
    receive_start_tli,
    received_lsn,
    received_tli,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_lsn,
    latest_end_time,
    sender_host,
    sender_port
FROM pg_stat_wal_receiver;

-- ------------------------------------------------------------------------------
-- 5. TRUY VẤN KIỂM TRA SỐ LƯỢNG KẾT NỐI VÀ HOẠT ĐỘNG
-- ------------------------------------------------------------------------------
SELECT 
    datname,
    count(*) AS total_connections,
    count(*) FILTER (WHERE state = 'active') AS active_queries,
    count(*) FILTER (WHERE state = 'idle') AS idle_connections,
    count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx
FROM pg_stat_activity
WHERE datname = 'hospital_db'
GROUP BY datname;

-- ------------------------------------------------------------------------------
-- 6. TRUY VẤN NGHIỆP VỤ BỆNH VIỆN MẪU
-- ------------------------------------------------------------------------------
-- 6.1. Thống kê số lượng bệnh nhân theo từng Khoa
SELECT 
    d.department_code,
    d.name AS department_name,
    count(DISTINCT a.patient_id) AS total_patients_served,
    count(a.appointment_id) AS total_appointments
FROM departments d
LEFT JOIN appointments a ON d.department_id = a.department_id
GROUP BY d.department_id, d.department_code, d.name
ORDER BY total_appointments DESC;

-- 6.2. Tra cứu lịch sử khám bệnh chi tiết của bệnh nhân
SELECT 
    p.medical_record_number,
    p.full_name AS patient_name,
    mr.examination_date,
    doc.full_name AS doctor_name,
    mr.clinical_diagnosis,
    mr.icd10_code,
    mr.vital_signs->>'blood_pressure' AS blood_pressure,
    mr.vital_signs->>'heart_rate' AS heart_rate,
    inv.final_amount,
    inv.payment_status
FROM patients p
JOIN medical_records mr ON p.patient_id = mr.patient_id
JOIN doctors doc ON mr.doctor_id = doc.doctor_id
LEFT JOIN appointments a ON mr.appointment_id = a.appointment_id
LEFT JOIN invoices inv ON a.appointment_id = inv.appointment_id
ORDER BY mr.examination_date DESC;

-- ------------------------------------------------------------------------------
-- 7. TRUY VẤN GHI NHẬT KÝ TEST FAILOVER VÀ ĐO ĐẠC RPO (Giao dịch mẫu)
-- ------------------------------------------------------------------------------
-- Chèn bản ghi thử nghiệm trước hoặc trong lúc failover
INSERT INTO audit_logs (node_source, table_name, action_type, payload)
VALUES (
    inet_server_addr()::text,
    'failover_test',
    'INSERT_TX',
    jsonb_build_object(
        'test_id', 'TEST-FAILOVER-001',
        'timestamp', clock_timestamp(),
        'message', 'Giao dịch kiểm tra tính toàn vẹn dữ liệu khi chuyển dịch Primary'
    )
) RETURNING log_id, transaction_uuid, created_at;

-- Kiểm tra số bản ghi test đã được ghi nhận và đồng bộ
SELECT 
    node_source,
    count(*) AS total_tx_inserted,
    min(created_at) AS first_tx_time,
    max(created_at) AS last_tx_time
FROM audit_logs
WHERE table_name = 'failover_test'
GROUP BY node_source;
