// ==============================================================================
// RESILIENT POSTGRESQL CONNECTION POOL WITH FAILOVER AUTO-RETRY
// Kết nối PostgreSQL thông qua HAProxy (Port 5000)
// Tự động retry khi xảy ra Failover hoặc chuyển dịch vai trò Primary
// ==============================================================================

const { Pool } = require('pg');
require('dotenv').config();

const dbConfig = {
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '5000', 10),
  database: process.env.DB_NAME || 'hospital_db',
  user: process.env.DB_USER || 'hospital_app_user',
  password: process.env.DB_PASSWORD || 'CHANGE_ME_APP_SECRET_2026',
  max: parseInt(process.env.DB_POOL_MAX || '20', 10),
  idleTimeoutMillis: parseInt(process.env.DB_POOL_IDLE_TIMEOUT_MS || '10000', 10),
  connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT_MS || '3000', 10),
  application_name: 'hospital_node_api'
};

const pool = new Pool(dbConfig);

// Lắng nghe sự kiện lỗi kết nối từ client idle trong pool
pool.on('error', (err, client) => {
  console.error('[DB POOL] Lỗi bất ngờ trên client rảnh rỗi (Có thể do Primary failover):', err.message);
});

// Danh sách các mã lỗi PostgreSQL hoặc socket chỉ báo sự cố Failover
const RETRYABLE_ERRORS = [
  'ECONNREFUSED',
  'ECONNRESET',
  'ETIMEDOUT',
  '57P01', // admin_shutdown
  '57P02', // crash_shutdown
  '57P03', // cannot_connect_now
  '25006', // read_only_sql_transaction (xảy ra khi node cũ bị giáng cấp xuống standby)
  '08006', // connection_failure
  '08001', // sqlclient_unable_to_establish_sqlconnection
  '08004'  // sqlserver_rejected_establishment_of_sqlconnection
];

function isRetryable(err) {
  if (!err) return false;
  if (err.code && RETRYABLE_ERRORS.includes(err.code)) return true;
  const msg = err.message || '';
  return msg.includes('Connection terminated') || 
         msg.includes('Connection refused') || 
         msg.includes('read-only') ||
         msg.includes('closed');
}

const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

/**
 * Thực thi câu truy vấn với cơ chế retry tự động khi xảy ra failover
 * @param {string} text - SQL query (sử dụng parameterized queries $1, $2)
 * @param {Array} params - Mảng tham số an toàn
 * @param {number} maxRetries - Số lần thử lại tối đa khi node failover
 */
async function queryWithRetry(text, params = [], maxRetries = 8) {
  let attempt = 0;
  let delay = parseInt(process.env.DB_RETRY_DELAY_MS || '1500', 10);

  while (attempt <= maxRetries) {
    try {
      const start = Date.now();
      const res = await pool.query(text, params);
      const duration = Date.now() - start;
      return { ...res, duration };
    } catch (err) {
      attempt++;
      if (attempt > maxRetries || !isRetryable(err)) {
        console.error(`[DB ERROR] Truy vấn thất bại vĩnh viễn (Lần thử ${attempt}/${maxRetries}):`, err.message);
        throw err;
      }

      console.warn(`[DB FAILOVER RETRY] Phát hiện gián đoạn kết nối (${err.code || err.message}). Lần thử ${attempt}/${maxRetries}. Đang đợi HAProxy định tuyến Primary mới sau ${delay}ms...`);
      await sleep(delay);
      delay = Math.min(delay * 1.5, 6000); // Exponential backoff tối đa 6s
    }
  }
}

/**
 * Kiểm tra trạng thái sức khỏe chi tiết của Database
 */
async function getDbHealth() {
  const start = Date.now();
  const sql = `
    SELECT 
      inet_server_addr() AS server_ip,
      inet_server_port() AS server_port,
      current_database() AS db_name,
      current_user AS connected_user,
      pg_is_in_recovery() AS is_standby,
      CASE 
        WHEN pg_is_in_recovery() THEN 'STANDBY (READ-ONLY)'
        ELSE 'PRIMARY (READ-WRITE)'
      END AS role_desc,
      version() AS pg_version,
      clock_timestamp() AS db_time;
  `;
  const result = await queryWithRetry(sql, [], 3);
  const latencyMs = Date.now() - start;

  return {
    status: 'ONLINE',
    latencyMs,
    pool: {
      total: pool.totalCount,
      idle: pool.idleCount,
      waiting: pool.waitingCount
    },
    database: result.rows[0]
  };
}

module.exports = {
  pool,
  query: queryWithRetry,
  getDbHealth
};
