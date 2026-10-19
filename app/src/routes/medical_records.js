// ==============================================================================
// MEDICAL RECORDS ROUTE: /api/medical-records
// Tra cứu hồ sơ bệnh án, chẩn đoán ICD-10 và sinh hiệu bệnh nhân
// ==============================================================================

const express = require('express');
const router = express.Router();
const db = require('../db');

// GET /api/medical-records - Danh sách hồ sơ bệnh án gần nhất
router.get('/', async (req, res, next) => {
  try {
    const patientId = req.query.patient_id;
    let sql = `
      SELECT 
        mr.record_id,
        mr.examination_date,
        mr.symptoms,
        mr.clinical_diagnosis,
        mr.icd10_code,
        mr.vital_signs,
        mr.treatment_plan,
        mr.doctor_notes,
        p.patient_id,
        p.medical_record_number,
        p.full_name AS patient_name,
        doc.doctor_id,
        doc.full_name AS doctor_name,
        doc.specialization
      FROM medical_records mr
      JOIN patients p ON mr.patient_id = p.patient_id
      JOIN doctors doc ON mr.doctor_id = doc.doctor_id
    `;
    const params = [];

    if (patientId) {
      sql += ` WHERE mr.patient_id = $1 `;
      params.push(parseInt(patientId, 10));
    }

    sql += ` ORDER BY mr.examination_date DESC LIMIT 50 `;

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
