// ==============================================================================
// HOSPITAL MANAGEMENT REST API SERVER (NODE.JS & EXPRESS)
// Triển khai trên Máy APP1 (100.99.89.64 - Tailscale)
// Kết nối CSDL PostgreSQL Primary qua HAProxy (Port 5000)
// ==============================================================================

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const path = require('path');
const db = require('./src/db');
const errorHandler = require('./src/middleware/errorHandler');

// Import routes
const healthRoutes = require('./src/routes/health');
const patientsRoutes = require('./src/routes/patients');
const doctorsRoutes = require('./src/routes/doctors');
const appointmentsRoutes = require('./src/routes/appointments');
const medicalRecordsRoutes = require('./src/routes/medical_records');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(morgan('combined'));

// Giao diện Web tĩnh phục vụ Demo & Giám sát Live
app.use(express.static(path.join(__dirname, 'public')));

// Đăng ký các API Endpoints
app.use('/', healthRoutes);
app.use('/api/patients', patientsRoutes);
app.use('/api/doctors', doctorsRoutes);
app.use('/api/appointments', appointmentsRoutes);
app.use('/api/medical-records', medicalRecordsRoutes);

// Bắt các route không tồn tại (404)
app.use((req, res, next) => {
  res.status(404).json({
    success: false,
    message: `Không tìm thấy endpoint: ${req.method} ${req.url}`
  });
});

// Central Error Handler
app.use(errorHandler);

// Khởi chạy server và kiểm tra kết nối CSDL ban đầu
const server = app.listen(PORT, async () => {
  console.log(`==============================================================================`);
  console.log(`🏥 HOSPITAL HA API ĐANG CHẠY TẠI CỔNG: http://0.0.0.0:${PORT}`);
  console.log(`🚀 Môi trường: ${process.env.NODE_ENV || 'production'}`);
  console.log(`📡 Kết nối PostgreSQL qua HAProxy: ${process.env.DB_HOST || '127.0.0.1'}:${process.env.DB_PORT || 5000}`);
  console.log(`==============================================================================`);

  try {
    const health = await db.getDbHealth();
    console.log(`[DB INIT] Kết nối thành công tới ${health.database.role_desc} trên IP: ${health.database.server_ip}:${health.database.server_port}`);
  } catch (err) {
    console.warn(`[DB INIT WARN] Chưa thể kết nối tới PostgreSQL (Cụm Patroni có thể chưa khởi động xong):`, err.message);
  }
});

// Xử lý Graceful Shutdown
function gracefulShutdown(signal) {
  console.log(`\n[SHUTDOWN] Nhận tín hiệu ${signal}. Đang đóng HTTP server và Database connection pool...`);
  server.close(async () => {
    try {
      await db.pool.end();
      console.log('[SHUTDOWN] Đã giải phóng toàn bộ kết nối PostgreSQL Pool. Tắt server an toàn.');
      process.exit(0);
    } catch (err) {
      console.error('[SHUTDOWN ERROR] Lỗi khi đóng database pool:', err.message);
      process.exit(1);
    }
  });
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
