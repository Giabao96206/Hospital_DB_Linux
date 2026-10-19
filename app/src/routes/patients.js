// ==============================================================================
// PATIENTS ROUTE: /api/patients
// Quản lý hồ sơ bệnh nhân giả lập với Parameterized Queries & Input Validation
// ==============================================================================

const express = require('express');
const router = express.Router();
const { body, query, validationResult } = require('express-validator');
const db = require('../db');

// 1. GET /api/patients - Lấy danh sách bệnh nhân có tìm kiếm và phân trang
router.get(
  '/',
  [
    query('search').optional().trim().escape(),
    query('limit').optional().isInt({ min: 1, max: 100 }).toInt(),
    query('page').optional().isInt({ min: 1 }).toInt()
  ],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ success: false, errors: errors.array() });
      }

      const search = req.query.search || '';
      const limit = req.query.limit || 20;
      const page = req.query.page || 1;
      const offset = (page - 1) * limit;

      let sql = `
        SELECT 
          patient_id,
          medical_record_number,
          full_name,
          date_of_birth,
          gender,
          national_id,
          health_insurance_id,
          phone,
          email,
          address,
          blood_type,
          allergies,
          created_at
        FROM patients
      `;
      const params = [];

      if (search) {
        sql += ` WHERE full_name ILIKE $1 OR medical_record_number ILIKE $1 OR phone ILIKE $1 `;
        params.push(`%${search}%`);
      }

      sql += ` ORDER BY patient_id DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2} `;
      params.push(limit, offset);

      const result = await db.query(sql, params);

      // Đếm tổng số bản ghi
      let countSql = `SELECT count(*) as total FROM patients`;
      const countParams = [];
      if (search) {
        countSql += ` WHERE full_name ILIKE $1 OR medical_record_number ILIKE $1 OR phone ILIKE $1 `;
        countParams.push(`%${search}%`);
      }
      const countResult = await db.query(countSql, countParams);
      const total = parseInt(countResult.rows[0].total, 10);

      res.json({
        success: true,
        data: result.rows,
        pagination: {
          total,
          page,
          limit,
          totalPages: Math.ceil(total / limit)
        },
        executionDurationMs: result.duration
      });
    } catch (err) {
      next(err);
    }
  }
);

// 2. GET /api/patients/:id - Chi tiết bệnh nhân
router.get('/:id', async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) {
      return res.status(400).json({ success: false, message: 'ID bệnh nhân không hợp lệ' });
    }

    const result = await db.query(
      `SELECT * FROM patients WHERE patient_id = $1`,
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy bệnh nhân' });
    }

    res.json({ success: true, data: result.rows[0] });
  } catch (err) {
    next(err);
  }
});

// 3. POST /api/patients - Tạo mới bệnh nhân giả lập
router.post(
  '/',
  [
    body('full_name').notEmpty().withMessage('Họ và tên bắt buộc').trim(),
    body('date_of_birth').isISO8601().withMessage('Ngày sinh định dạng YYYY-MM-DD'),
    body('gender').isIn(['MALE', 'FEMALE', 'OTHER']).withMessage('Giới tính MALE, FEMALE hoặc OTHER'),
    body('phone').isMobilePhone('vi-VN').optional({ checkFalsy: true }).withMessage('Số điện thoại không hợp lệ'),
    body('address').notEmpty().withMessage('Địa chỉ bắt buộc').trim(),
    body('blood_type').optional().isIn(['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'])
  ],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ success: false, errors: errors.array() });
      }

      const {
        full_name,
        date_of_birth,
        gender,
        national_id,
        health_insurance_id,
        phone,
        email,
        address,
        blood_type,
        allergies,
        emergency_contact_name,
        emergency_contact_phone
      } = req.body;

      // Sinh mã bệnh án tự động: BN-YYYYMMDD-XXXX
      const datePart = new Date().toISOString().slice(0, 10).replace(/-/g, '');
      const randomSuffix = Math.floor(1000 + Math.random() * 9000);
      const mrn = `BN-${datePart}-${randomSuffix}`;

      const insertSql = `
        INSERT INTO patients (
          medical_record_number, full_name, date_of_birth, gender,
          national_id, health_insurance_id, phone, email, address,
          blood_type, allergies, emergency_contact_name, emergency_contact_phone
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        RETURNING *;
      `;
      const params = [
        mrn,
        full_name,
        date_of_birth,
        gender,
        national_id || null,
        health_insurance_id || null,
        phone || '0900000000',
        email || null,
        address,
        blood_type || 'O+',
        allergies || 'Chưa ghi nhận',
        emergency_contact_name || null,
        emergency_contact_phone || null
      ];

      const result = await db.query(insertSql, params);

      // Ghi log kiểm toán phục vụ bài kiểm thử đo lường RPO
      await db.query(
        `INSERT INTO audit_logs (node_source, table_name, action_type, record_id, payload)
         VALUES (inet_server_addr()::text, 'patients', 'INSERT', $1, $2)`,
        [result.rows[0].patient_id, JSON.stringify({ mrn, full_name })]
      );

      res.status(201).json({
        success: true,
        message: 'Tạo hồ sơ bệnh nhân thành công',
        data: result.rows[0],
        executionDurationMs: result.duration
      });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
