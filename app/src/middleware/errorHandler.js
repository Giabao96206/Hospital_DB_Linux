// ==============================================================================
// ERROR HANDLER MIDDLEWARE: HOSPITAL REST API
// Đảm bảo không để lộ mật khẩu, chuỗi kết nối CSDL hoặc stack trace nhạy cảm
// ==============================================================================

function errorHandler(err, req, res, next) {
  // Ghi log chi tiết trên máy chủ phục vụ debug nội bộ
  console.error(`[API ERROR] ${req.method} ${req.url} - Error:`, {
    message: err.message,
    code: err.code,
    timestamp: new Date().toISOString()
  });

  const statusCode = err.statusCode || (err.status ? err.status : 500);

  // Phản hồi an toàn cho người dùng client
  res.status(statusCode).json({
    success: false,
    error: {
      message: statusCode === 500 ? 'Lỗi máy chủ nội bộ hoặc cơ sở dữ liệu tạm thời gián đoạn (Đang tự phục hồi)' : err.message,
      errorCode: err.code || 'INTERNAL_ERROR',
      timestamp: new Date().toISOString()
    }
  });
}

module.exports = errorHandler;
