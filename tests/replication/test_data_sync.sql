-- ==============================================================================
-- SQL TEST SCRIPT: VERIFY DATA SYNCHRONIZATION ACROSS ALL NODES
-- ==============================================================================

-- 1. Kiểm tra LSN và trạng thái khôi phục
SELECT 
    inet_server_addr() AS node_ip,
    pg_is_in_recovery() AS is_standby,
    CASE WHEN NOT pg_is_in_recovery() THEN pg_current_wal_lsn() ELSE NULL END AS current_wal_lsn,
    CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() ELSE NULL END AS last_replayed_lsn;

-- 2. Thống kê số lượng bản ghi trong các bảng nghiệp vụ chính
SELECT 'patients' AS entity, count(*) AS count FROM patients
UNION ALL
SELECT 'appointments', count(*) FROM appointments
UNION ALL
SELECT 'medical_records', count(*) FROM medical_records
UNION ALL
SELECT 'prescriptions', count(*) FROM prescriptions
UNION ALL
SELECT 'invoices', count(*) FROM invoices
UNION ALL
SELECT 'audit_logs', count(*) FROM audit_logs;
