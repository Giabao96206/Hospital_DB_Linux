// ==============================================================================
// HEALTH CHECK ROUTES: /health & /health/db
// Phục vụ giám sát API, HAProxy và xác minh quá trình Failover
// ==============================================================================

const express = require('express');
const router = express.Router();
const db = require('../db');

// Kiểm tra tình trạng API process
router.get('/health', (req, res) => {
  res.json({
    status: 'UP',
    uptimeSeconds: Math.floor(process.uptime()),
    service: 'Hospital HA REST API',
    nodeVersion: process.version,
    memoryUsage: process.memoryUsage(),
    timestamp: new Date().toISOString()
  });
});

// Kiểm tra chi tiết kết nối Database và nhận diện Node Primary hiện tại
router.get('/health/db', async (req, res, next) => {
  try {
    const health = await db.getDbHealth();
    res.json({
      status: 'UP',
      clusterInfo: {
        connectedServerIp: health.database.server_ip,
        connectedPort: health.database.server_port,
        isStandby: health.database.is_standby,
        nodeRole: health.database.role_desc,
        databaseName: health.database.db_name,
        connectedUser: health.database.connected_user,
        databaseTime: health.database.db_time,
        queryLatencyMs: health.latencyMs
      },
      connectionPool: health.pool,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    res.status(503).json({
      status: 'DOWN',
      message: 'Không thể kết nối tới cơ sở dữ liệu qua HAProxy (Cụm đang failover hoặc ngắt kết nối)',
      error: err.message,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
