// ==============================================================================
// DOCTORS ROUTE: /api/doctors
// Quản lý danh sách bác sĩ và khoa phòng
// ==============================================================================

const express = require('express');
const router = express.Router();
const db = require('../db');

// GET /api/doctors - Lấy danh sách bác sĩ kèm thông tin khoa
router.get('/', async (req, res, next) => {
  try {
    const departmentId = req.query.department_id;
    let sql = `
      SELECT 
        d.doctor_id,
        d.employee_code,
        d.full_name,
        d.specialization,
        d.license_number,
        d.degree,
        d.phone,
        d.email,
        d.status,
        dept.department_id,
        dept.department_code,
        dept.name AS department_name,
        dept.building,
        dept.floor_number
      FROM doctors d
      JOIN departments dept ON d.department_id = dept.department_id
    `;
    const params = [];

    if (departmentId) {
      sql += ` WHERE d.department_id = $1 `;
      params.push(parseInt(departmentId, 10));
    }

    sql += ` ORDER BY dept.department_id ASC, d.doctor_id ASC `;

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

module.exports = router;
