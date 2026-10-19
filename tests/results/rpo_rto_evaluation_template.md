# Khung Đo Đạc, Đánh Giá RPO và RTO Thực Nghiệm

Tài liệu hướng dẫn phương pháp đo lường, công thức toán học và biểu mẫu ghi nhận các chỉ số độ tin cậy của Hệ thống CSDL Bệnh viện Dự phòng HA (5 máy Ubuntu Server 24.04).

---

## 1. Định Nghĩa & Cơ Sở Lý Thuyết

### 1.1. RPO (Recovery Point Objective - Điểm phục hồi mục tiêu)
- **Định nghĩa**: Khoảng thời gian dữ liệu giao dịch hoặc số lượng giao dịch đã được xác nhận (committed) bị mất mát tối đa mà tổ chức y tế có thể chấp nhận được khi xảy ra sự cố phần cứng/mạng đột ngột.
- **Phương pháp đo**:
  $$\text{RPO (Giao dịch)} = \text{Số giao dịch báo thành công với Client} - \text{Số giao dịch tìm thấy trên Primary mới}$$
  $$\text{RPO (Thời gian)} = T_{\text{sự cố}} - T_{\text{giao dịch cuối cùng được đồng bộ}}$$
- **Phụ thuộc cấu hình**:
  - **Chế độ Bất đồng bộ (Asynchronous Replication - mặc định)**: Transaction commit ngay khi ghi vào WAL của Primary mà không cần chờ Standby phản hồi. RPO thực tế thường nằm trong khoảng từ vài mili-giây đến vài giây ($0 \le \text{RPO} \le \text{Replication Lag}$).
  - **Chế độ Đồng bộ (Synchronous Replication - `synchronous_mode: true`)**: Transaction chỉ commit khi ít nhất 1 Standby đã nhận và ghi WAL. Khi đó $\text{RPO} = 0$, tuy nhiên độ trễ ghi (write latency) sẽ tăng lên do phụ thuộc Round-Trip Time (RTT) mạng.

### 1.2. RTO (Recovery Time Objective - Thời gian phục hồi mục tiêu)
- **Định nghĩa**: Khoảng thời gian tối đa từ lúc máy chủ Primary gặp sự cố (ngừng hoạt động) đến khi dịch vụ CSDL được khôi phục và tiếp tục cho phép ứng dụng đọc/ghi dữ liệu bình thường.
- **Phương pháp đo**:
  $$\text{RTO} = T_{\text{dịch vụ ghi trở lại bình thường}} - T_{\text{thời điểm Primary bắt đầu crash}}$$
- **Các thành phần cấu thành RTO trong mô hình Patroni + etcd + HAProxy**:
  1. $t_{\text{detect}}$: Thời gian phát hiện sự cố qua etcd lease TTL (mặc định cấu hình: $30\text{s}$, loop_wait: $10\text{s}$).
  2. $t_{\text{election}}$: Thời gian bầu chọn Leader mới qua thuật toán Raft consensus ($\approx 1 - 3\text{s}$).
  3. $t_{\text{promotion}}$: Thời gian PostgreSQL Standby thực hiện promote lên Primary ($\approx 1 - 2\text{s}$).
  4. $t_{\text{routing}}$: Thời gian HAProxy health check (`/primary`) nhận diện backend mới (mặc định: `inter 3s rise 2` $\approx 6\text{s}$).
  5. $t_{\text{reconnect}}$: Thời gian ứng dụng Node.js retry kết nối thành công ($\approx 1 - 3\text{s}$).
  $$\text{RTO} = t_{\text{detect}} + t_{\text{election}} + t_{\text{promotion}} + t_{\text{routing}} + t_{\text{reconnect}}$$
  *Trong môi trường Lab thực tế, RTO thường dao động trong khoảng 15 – 35 giây.*

---

## 2. Bảng Ghi Nhận Kết Quả Đo Đạc Thực Nghiệm

*(Ghi nhận trực tiếp từ các bài kiểm thử thực tế trên 5 máy lab)*

| Bài kiểm thử | Kịch bản thử nghiệm | RPO thực tế (Số TX mất) | RTO thực tế (Thời gian downtime) | Replication Lag lúc đo | Trạng thái nghiệm thu |
|---|---|---|---|---|---|
| **Test 1** | Đồng bộ Streaming Replication bình thường | 0 | 0 s (Không gián đoạn) | < 100 KB (0 ms) | ĐẠT / CHỜ TEST |
| **Test 2** | DB2 (Standby) mất kết nối 30s rồi khôi phục | 0 | 0 s (Primary vẫn ghi) | 0 sau catch-up | ĐẠT / CHỜ TEST |
| **Test 3** | DB1 (Primary) bị crash đột ngột (`pkill -9`) | `[Điền thực tế]` | `[Điền thực tế]` s | N/A | ĐẠT / CHỜ TEST |
| **Test 4** | Khôi phục DB1 tái gia nhập với vai trò Standby | 0 | 0 s (Cụm vẫn chạy) | < 50 KB | ĐẠT / CHỜ TEST |
| **Test 5** | Khôi phục khẩn cấp từ bản sao lưu pgBackRest | Tùy thời điểm backup | `[Điền thực tế]` s (Restore drill) | N/A | ĐẠT / CHỜ TEST |
| **Test 6** | Máy MON1 (Backup/Monitoring) offline | 0 | 0 s (DB độc lập) | N/A | ĐẠT / CHỜ TEST |
| **Test 7** | Phân vùng mạng (Network Partition Split-brain) | 0 | `[Điền thực tế]` s | N/A | ĐẠT / CHỜ TEST |

---

## 3. Biểu Mẫu Ghi Log Chi Tiết Cho Từng Lần Chạy Thử

### Lần chạy kiểm thử số: `____`
- **Ngày thực hiện**: `YYYY-MM-DD HH:MM:SS`
- **Người thực hiện**: `[Tên sinh viên / Kỹ sư DBA]`
- **Môi trường lab**: 5 máy Ubuntu Server 24.04 LTS (RAM: `___ GB`, CPU: `___ vCPU`, Switch mạng: `___ Mbps`)
- **Chế độ Patroni**: `synchronous_mode: [false | true]`
- **Tốc độ gửi tải ghi (`failover_load_test.js`)**: `___ giao dịch / giây`

#### Nhật ký tiến trình:
1. Thời điểm bắt đầu gửi tải: `T0 = ________________________`
2. Thời điểm ngắt nguồn / tắt tiến trình DB1: `T1 = ________________________`
3. Thời điểm giao dịch đầu tiên nhận lỗi kết nối: `T2 = ________________________`
4. Thời điểm Patroni ghi nhận Leader mới: `T3 = ________________________`
5. Thời điểm HAProxy chuyển trạng thái UP cho backend mới: `T4 = ________________________`
6. Thời điểm ứng dụng ghi nhận giao dịch thành công đầu tiên: `T5 = ________________________`

#### Kết quả tính toán:
- $\text{RTO} = T5 - T1 = \underline{\hspace{2cm}}$ giây.
- Tổng số giao dịch Client nhận HTTP 200/SUCCESS: $\underline{\hspace{2cm}}$ giao dịch.
- Số giao dịch tìm thấy trong bảng `audit_logs` trên Primary mới: $\underline{\hspace{2cm}}$ giao dịch.
- Chênh lệch $\text{RPO} = \underline{\hspace{2cm}}$ giao dịch.
- Nhận xét kỹ thuật: `_______________________________________________________________`
