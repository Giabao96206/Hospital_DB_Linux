# HƯỚNG DẪN XỬ LÝ SỰ CỐ THƯỜNG GẶP (TROUBLESHOOTING GUIDE)

Tổng hợp các tình huống lỗi thực tế có thể phát sinh trong quá trình triển khai và vận hành cụm CSDL Bệnh viện HA cùng phương pháp khắc phục chuẩn xác.

---

## 1. Sự Cố etcd Mất Quorum (Chỉ Còn 1 Thành Viên Hoạt Động)

- **Triệu chứng**:
  - Lệnh `etcdctl endpoint health` báo lỗi timeout hoặc không phản hồi.
  - Log Patroni xuất hiện: `etcd3.exceptions.ConnectionFailed: ...`
  - Các node PostgreSQL tự động chuyển sang Read-Only hoặc dừng hoạt động để bảo vệ dữ liệu.
- **Nguyên nhân**:
  - Ít nhất 2 trong số 3 thành viên etcd (ví dụ DB1 và DB2) bị ngắt kết nối hoặc tắt máy.
  - Tường lửa (UFW) chặn nhầm cổng `2380` (Peer traffic) giữa các node.
- **Cách khắc phục**:
  1. Kiểm tra tường lửa trên cả 3 máy:
     ```bash
     sudo ufw status verbose
     # Đảm bảo cổng 2380 được allow giữa các IP của 3 DB nodes
     ```
  2. Khởi động lại dịch vụ etcd trên các máy bị sập:
     ```bash
     sudo systemctl restart etcd
     ```
  3. Nếu 2 máy kia hỏng hoàn toàn phần cứng và muốn ép node còn lại (DB3) tiếp tục chạy:
     ```bash
     sudo systemctl stop etcd
     sudo -u etcd etcd --force-new-cluster --config-file=/etc/etcd/etcd.conf.yml
     ```

---

## 2. HAProxy Trả Về Lỗi 503 Service Unavailable Khi Ứng Dụng Kết Nối

- **Triệu chứng**:
  - Ứng dụng Node.js báo: `Server returned 503` hoặc `connection refused`.
  - Trang thống kê HAProxy (Port 7000) hiển thị backend `postgres_primary_back` màu đỏ (DOWN).
- **Nguyên nhân**:
  - Không có node nào trong cụm trả về HTTP `200 OK` cho health check `GET /primary` trên cổng 8008.
  - Patroni chưa khởi động hoặc cụm đang trong quá trình chuyển giao Leader.
- **Cách khắc phục**:
  1. Kiểm tra trực tiếp endpoint Patroni từ APP1:
     ```bash
     curl -i http://100.115.205.94:8008/primary
     curl -i http://100.97.242.2:8008/primary
     curl -i http://100.67.87.46:8008/primary
     ```
  2. Nếu không có máy nào trả về `200`: Kiểm tra xem có node nào đang giữ vai trò Leader không:
     ```bash
     patronictl -c /etc/patroni/patroni.yml list
     ```
  3. Nếu trạng thái là `unlocked`, có thể do etcd bị nghẽn mạng hoặc clock giữa các máy bị lệch quá lớn khiến lease bị hủy. Đồng bộ lại thời gian bằng `sudo systemctl restart chrony`.

---

## 3. Lỗi Tràn Ổ Đĩa Do Archive Command Của pgBackRest Bị Nghẽn

- **Triệu chứng**:
  - Phân vùng `/var/lib/postgresql` tăng nhanh dung lượng bất thường.
  - Thư mục `pg_wal` chứa hàng trăm file WAL chưa được giải phóng.
  - Log PostgreSQL có thông báo: `archive command "pgbackrest ... archive-push" failed with exit code 1`.
- **Nguyên nhân**:
  - Máy MON1 bị đầy đĩa hoặc dịch vụ SSH giữa user `postgres` bị lỗi xác thực.
  - Sai quyền sở hữu trên thư mục `/var/lib/pgbackrest` của MON1.
- **Cách khắc phục**:
  1. Kiểm tra xác thực SSH không cần mật khẩu từ DB node sang MON1:
     ```bash
     sudo -u postgres ssh -o BatchMode=yes postgres@100.87.112.76 "echo OK"
     ```
     Nếu thất bại, kiểm tra lại file `/var/lib/postgresql/.ssh/authorized_keys` trên MON1 và DB nodes.
  2. Kiểm tra dung lượng ổ đĩa trên MON1:
     ```bash
     df -h /var/lib/pgbackrest
     ```
  3. Chạy lệnh kiểm tra stanza từ DB node:
     ```bash
     sudo -u postgres pgbackrest --stanza=hospital_cluster check
     ```

---

## 4. Node Cũ Không Thể Tái Gia Nhập Cụm Do Lỗi Timeline Phân Kỳ

- **Triệu chứng**:
  - Khi bật lại DB1, log Patroni báo: `pg_rewind failed` hoặc node liên tục khởi động lại (CrashLoop).
- **Nguyên nhân**:
  - PostgreSQL đã được cấu hình mà chưa bật `wal_log_hints = on` hoặc không bật data-checksums lúc initdb.
  - Các file WAL cũ cần thiết để tua lại đã bị dọn dẹp mất.
- **Cách khắc phục**:
  1. Kiểm tra tham số `wal_log_hints` trong `patroni.yml`: Phải đảm bảo giá trị là `on`.
  2. Sử dụng lệnh tái khởi tạo an toàn của Patroni để kéo lại bản snapshot chuẩn từ Primary hiện tại:
     ```bash
     sudo patronictl -c /etc/patroni/patroni.yml reinit hospital-ha-cluster db1
     ```
     Patroni sẽ tự động dọn dẹp dữ liệu phân kỳ cũ và chạy `pg_basebackup` an toàn.
