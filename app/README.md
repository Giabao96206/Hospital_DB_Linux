# Ứng Dụng REST API Quản Lý Bệnh Viện (High Availability Demo)

Hệ thống REST API minh họa phục vụ quản lý thông tin bệnh viện trên máy chủ **APP1 (100.99.89.64 - Tailscale)**, kết nối đến cụm cơ sở dữ liệu PostgreSQL có khả năng tự phục hồi (Patroni + etcd + HAProxy).

---

## 1. Tính Năng Kỹ Thuật Nổi Bật

- **Định tuyến qua HAProxy**: Ứng dụng không bao giờ kết nối cứng trực tiếp tới IP của DB1, DB2 hay DB3 mà kết nối tới `127.0.0.1:5000` (HAProxy). HAProxy sử dụng API check `/primary` của Patroni để đảm bảo các truy vấn ghi luôn được gửi chính xác đến node Primary hiện tại.
- **Failover Resilience (Tự động Reconnect & Retry)**: Trong tầng kết nối CSDL (`src/db.js`), mọi câu truy vấn được bao bọc bởi thuật toán Exponential Backoff Retry. Khi xảy ra failover (mất 5 - 15 giây), các lỗi kết nối như `ECONNREFUSED`, `57P01` (admin_shutdown), hoặc `25006` (read-only transaction) sẽ được bắt và chờ cho đến khi HAProxy chuyển hướng sang Primary mới, ngăn chặn sập tiến trình ứng dụng.
- **Parameterized Queries**: Toàn bộ thao tác SQL sử dụng tham số an toàn (`$1`, `$2`), loại bỏ hoàn toàn nguy cơ SQL Injection.
- **Bảo mật phân quyền (Least Privilege)**: Kết nối CSDL bằng tài khoản `hospital_app_user` – chỉ có quyền DML (SELECT, INSERT, UPDATE, DELETE) trên các bảng nghiệp vụ, không có quyền DDL hay quyền quản trị máy chủ.
- **Bảo mật mật khẩu**: Mật khẩu tài khoản nhân viên y tế được băm bằng giải thuật bcrypt thông qua extension `pgcrypto`.

---

## 2. Danh Sách API Endpoints

| Phương thức | Endpoint | Mô tả |
|---|---|---|
| `GET` | `/health` | Kiểm tra tình trạng hoạt động và tài nguyên của Node.js process |
| `GET` | `/health/db` | Kiểm tra kết nối CSDL, trả về IP node Primary thực tế đang phục vụ |
| `GET` | `/api/patients` | Lấy danh sách bệnh nhân giả lập (hỗ trợ tìm kiếm, phân trang) |
| `POST` | `/api/patients` | Tiếp nhận bệnh nhân mới (ghi trực tiếp vào Primary) |
| `GET` | `/api/patients/:id` | Xem chi tiết thông tin và bệnh án bệnh nhân |
| `GET` | `/api/doctors` | Lấy danh sách bác sĩ và khoa phòng |
| `GET` | `/api/appointments` | Xem danh sách lịch hẹn khám bệnh |
| `POST` | `/api/appointments` | Đặt lịch hẹn khám bệnh mới |
| `GET` | `/api/medical-records`| Xem hồ sơ bệnh án, chẩn đoán ICD-10 và sinh hiệu |

---

## 3. Hướng Dẫn Cài Đặt & Chạy Ứng Dụng

### Yêu cầu tiên quyết:
- Đã cài đặt Node.js 18 LTS hoặc 20 LTS trên máy **APP1**.
- Dịch vụ HAProxy trên APP1 đang chạy và đã kết nối được với cụm DB.

```bash
# 1. Di chuyển vào thư mục ứng dụng
cd /opt/hospital-db-ha/app

# 2. Tạo file cấu hình môi trường từ mẫu
cp .env.example .env
nano .env  # Điều chỉnh mật khẩu DB_PASSWORD nếu cần

# 3. Cài đặt các gói phụ thuộc
npm install

# 4. Khởi chạy ứng dụng (chế độ Production)
npm start

# Hoặc thiết lập chạy nền bằng systemd (xem scripts/app/setup_app_service.sh)
```

---

## 4. Giao Diện Trực Quan (Web Dashboard)

Truy cập trực tiếp trên trình duyệt qua mạng Tailscale: `http://100.99.89.64:3000/`

Giao diện cung cấp:
- Đèn báo trạng thái kết nối CSDL theo thời gian thực.
- Hiển thị trực tiếp **IP của node Primary** đang tiếp nhận dữ liệu.
- Nút bấm **"Chạy 10 Giao Dịch Ghi Liên Tục"** để người kiểm thử quan sát ứng dụng tiếp tục ghi dữ liệu mà không bị crash khi tiến hành tắt đột ngột node DB1.
