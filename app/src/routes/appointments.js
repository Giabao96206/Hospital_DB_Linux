// ==============================================================================
// APPOINTMENTS ROUTE: /api/appointments
// Đặt lịch khám và tra cứu lịch hẹn với bảo đảm ACID qua PostgreSQL Primary
// ==============================================================================

const express = require('express');
const router = express.Router();
const { body, query, validationResult } = require('express-validator');
const db = require('../db');

// 1. GET /api/appointments - Tra cứu danh sách lịch khám
router.get('/', async (req, res, next) => {
  try {
    const status = req.query.status;
    const date = req.query.date;

    let sql = `
      SELECT 
        a.appointment_id,
        a.appointment_code,
        a.scheduled_at,
        a.status,
        a.reason_for_visit,
        a.notes,
        p.patient_id,
        p.medical_record_number,
        p.full_name AS patient_name,
        p.phone AS patient_phone,
        doc.doctor_id,
        doc.full_name AS doctor_name,
        doc.specialization,
        dept.name AS department_name
      FROM appointments a
      JOIN patients p ON a.patient_id = p.patient_id
      JOIN doctors doc ON a.doctor_id = doc.doctor_id
      JOIN departments dept ON a.department_id = dept.department_id
    `;
    const params = [];

    const conditions = [];
    if (status) {
      params.push(status);
      conditions.push(` a.status = $${params.length} `);
    }
    if (date) {
      params.push(date);
      conditions.push(` DATE(a.scheduled_at) = $${params.length} `);
    }

    if (conditions.length > 0) {
      sql += ' WHERE ' + conditions.join(' AND ');
    }

    sql += ' ORDER BY a.scheduled_at DESC LIMIT 50 ';

    const result = await db.query(sql, params);

    res.json({
      success: true,
      data: result.rows,
      count: result.rowCount,
      executionDurationMs: result.duration
    });
  } catch (err) {
    next(err);
  }
});

// 2. POST /api/appointments - Đăng ký lịch khám mới
router.post(
  '/',
  [
    body('patient_id').isInt({ min: 1 }).withMessage('ID bệnh nhân không hợp lệ'),
    body('doctor_id').isInt({ min: 1 }).withMessage('ID bác sĩ không hợp lệ'),
    body('department_id').isInt({ min: 1 }).withMessage('ID khoa không hợp lệ'),
    body('scheduled_at').isISO8601().withMessage('Thời gian hẹn định dạng ISO8601'),
    body('reason_for_visit').notEmpty().withMessage('Lý do khám không được để trống').trim()
  ],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ success: false, errors: errors.array() });
      }

      const { patient_id, doctor_id, department_id, scheduled_at, reason_for_visit, notes } = req.body;

      // Sinh mã lịch hẹn duy nhất: APT-YYYYMMDD-XXXX
      const datePart = new Date().toISOString().slice(0, 10).replace(/-/g, '');
      const randomSuffix = Math.floor(1000 + Math.random() * 9000);
      const code = `APT-${datePart}-${randomSuffix}`;

      const insertSql = `
        INSERT INTO appointments (
          appointment_code, patient_id, doctor_id, department_id, scheduled_at, status, reason_for_visit, notes
        )
        VALUES ($1, $2, $3, $4, $5, 'PENDING', $6, $7)
        RETURNING *;
      `;
      const params = [code, patient_id, doctor_id, department_id, scheduled_at, reason_for_visit, notes || null];

      const result = await db.query(insertSql, params);

      // Ghi nhận vào audit log phục vụ kiểm tra failover & replication
      await db.query(
        `INSERT INTO audit_logs (node_source, table_name, action_type, record_id, payload)
         VALUES (inet_server_addr()::text, 'appointments', 'INSERT', $1, $2)`,
        [result.rows[0].appointment_id, JSON.stringify({ code, patient_id, scheduled_at })]
      );

      res.status(201).json({
        success: true,
        message: 'Tạo lịch khám thành công',
        data: result.rows[0],
        executionDurationMs: result.duration
      });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
