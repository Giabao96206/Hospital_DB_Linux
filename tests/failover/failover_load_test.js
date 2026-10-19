// ==============================================================================
// FAILOVER LOAD TEST SUITE: RPO & RTO BENCHMARKING
// Chạy ghi liên tục qua HAProxy (Port 5000) trong lúc sự cố xảy ra
// Ghi nhận chính xác số giao dịch thành công, số lỗi, thời gian gián đoạn (RTO),
// và đối chiếu mất mát dữ liệu (RPO).
// ==============================================================================

const { Pool } = require('pg');
const fs = require('fs');

const pool = new Pool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '5000', 10),
  database: process.env.DB_NAME || 'hospital_db',
  user: process.env.DB_USER || 'hospital_app_user',
  password: process.env.DB_PASSWORD || 'CHANGE_ME_APP_SECRET_2026',
  max: 5,
  connectionTimeoutMillis: 2000
});

const CSV_OUTPUT = 'failover_benchmark_log.csv';
const logStream = fs.createWriteStream(CSV_OUTPUT, { flags: 'w' });
logStream.write('tx_index,timestamp_ms,status,latency_ms,error_code,server_ip\n');

let isRunning = true;
let txIndex = 0;
let successCount = 0;
let failCount = 0;
let firstFailTime = null;
let recoveryTime = null;
let currentServerIp = null;

console.log('==============================================================================');
console.log('🚀 BẮT ĐẦU CHẠY TẢI GHI ĐO ĐẠC RPO & RTO QUA HAPROXY (PORT 5000)');
console.log(`📡 File log chi tiết: ${CSV_OUTPUT}`);
console.log('Nhấn Ctrl+C để dừng kiểm thử bất cứ lúc nào.');
console.log('==============================================================================\n');

async function executeTx(index) {
  const start = Date.now();
  const txUuid = `TX-${Date.now()}-${index}`;

  try {
    const res = await pool.query(
      `INSERT INTO audit_logs (node_source, table_name, action_type, payload)
       VALUES (inet_server_addr()::text, 'rpo_rto_benchmark', 'LOAD_WRITE', $1)
       RETURNING node_source;`,
      [JSON.stringify({ tx_index: index, uuid: txUuid, sent_at: start })]
    );

    const latency = Date.now() - start;
    const ip = res.rows[0].node_source;
    successCount++;

    if (firstFailTime && !recoveryTime) {
      recoveryTime = Date.now();
      const rtoSeconds = ((recoveryTime - firstFailTime) / 1000).toFixed(2);
      console.log(`\n🎉 [PHỤC HỒI THÀNH CÔNG] Dịch vụ đã tiếp nhận ghi trở lại trên node: ${ip}!`);
      console.log(`⏱️ THỜI GIAN GIÁN ĐOẠN ĐO ĐƯỢC (RTO): ${rtoSeconds} GIÂY!\n`);
    }

    if (currentServerIp && currentServerIp !== ip) {
      console.log(`🔄 [FAILOVER PHÁT HIỆN] Giao dịch chuyển từ Primary cũ (${currentServerIp}) sang Primary mới (${ip})!`);
    }
    currentServerIp = ip;

    logStream.write(`${index},${start},SUCCESS,${latency},NONE,${ip}\n`);
    process.stdout.write(`\r[OK] TX #${index} | Node: ${ip} | Latency: ${latency}ms | Thành công: ${successCount} | Lỗi: ${failCount}   `);
  } catch (err) {
    failCount++;
    const latency = Date.now() - start;
    if (!firstFailTime) {
      firstFailTime = Date.now();
      console.log(`\n\n⚠️ [SỰ CỐ BẮT ĐẦU] Giao dịch đầu tiên bị lỗi tại ${new Date(firstFailTime).toLocaleTimeString()}`);
      console.log(`Nguyên nhân: ${err.message} (${err.code || 'NO_CODE'})`);
    }

    logStream.write(`${index},${start},FAILED,${latency},${err.code || 'ERR'},NONE\n`);
    process.stdout.write(`\r[FAIL] TX #${index} | LỖI: ${err.code || err.message} | Thành công: ${successCount} | Lỗi: ${failCount}   `);
  }
}

async function startLoop() {
  while (isRunning) {
    txIndex++;
    await executeTx(txIndex);
    await new Promise(r => setTimeout(r, 200)); // 5 giao dịch / giây
  }
}

startLoop();

function finish() {
  isRunning = false;
  console.log('\n\n==============================================================================');
  console.log('📊 TỔNG KẾT BÀI ĐO ĐẠC RPO & RTO');
  console.log(`- Tổng số giao dịch gửi đi: ${txIndex}`);
  console.log(`- Giao dịch cam kết thành công (Committed): ${successCount}`);
  console.log(`- Giao dịch thất bại trong lúc gián đoạn: ${failCount}`);
  if (firstFailTime && recoveryTime) {
    const rto = ((recoveryTime - firstFailTime) / 1000).toFixed(2);
    console.log(`- Thời gian phục hồi dịch vụ (RTO): ${rto} giây`);
  } else {
    console.log(`- RTO: Không ghi nhận sự cố gián đoạn hoặc chưa phục hồi.`);
  }
  console.log('==============================================================================');
  pool.end();
  logStream.end();
  process.exit(0);
}

process.on('SIGINT', finish);
process.on('SIGTERM', finish);
