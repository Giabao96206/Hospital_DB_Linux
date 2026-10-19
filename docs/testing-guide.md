# HƯỚNG DẪN THỰC THI 7 BÀI KIỂM THỬ THỰC HÀNH TRÊN MÔI TRƯỜNG LAB

Tài liệu hướng dẫn chi tiết từng bước thực thi, lệnh gọi, kết quả kỳ vọng và các biện pháp phục hồi cho 7 bài kiểm thử bắt buộc trong phòng thí nghiệm.

---

## BÀI TEST 1: Kiểm Tra Đồng Bộ Streaming Replication

- **Mục tiêu**: Đảm bảo mọi giao dịch ghi trên Primary được nhân bản tức thời và đồng nhất sang cả 2 Standby.
- **Trạng thái ban đầu**: Cụm 3 node hoạt động ổn định (DB1: Leader, DB2: Replica/Sync, DB3: Replica).
- **Lệnh thực thi**:
  ```bash
  # Chạy trên máy DB1 hoặc APP1:
  sudo bash /opt/hospital-db-ha/scripts/tests/test1_verify_replication.sh
  ```
- **Kết quả mong đợi**:
  - Bản ghi bệnh nhân giả lập được chèn thành công trên DB1.
  - Sau dưới 1 giây, truy vấn trên DB2 và DB3 đều trả về bản ghi tương ứng.
  - `pg_stat_replication` hiển thị `state = streaming`, `replication_lag_bytes < 100KB`.
- **Cách khôi phục**: Không cần khôi phục (dữ liệu kiểm tra được giữ lại trong `audit_logs`).

---

## BÀI TEST 2: Một Standby Mất Kết Nối & Tự Bắt Kịp WAL (Catch-up)

- **Mục tiêu**: Xác nhận khi 1 Standby bị mất điện hoặc đứt mạng, Primary vẫn nhận ghi bình thường; khi Standby online trở lại, nó tự động tải các WAL còn thiếu từ replication slot mà không bị phân kỳ.
- **Trạng thái ban đầu**: Cả 3 node online.
- **Lệnh thực thi**:
  ```bash
  sudo bash /opt/hospital-db-ha/scripts/tests/test2_standby_isolation.sh
  ```
- **Kết quả mong đợi**:
  - Dịch vụ Patroni trên DB2 bị tắt.
  - DB1 tiếp tục ghi nhận 5 giao dịch test mới.
  - Replication slot `db2` trên DB1 chuyển sang trạng thái giữ lại WAL (`wal_status = reserved/extended`).
  - Khi DB2 được khởi động lại, DB2 nhận đủ 5 giao dịch và lag trở về 0.
- **Cách khôi phục**: Đảm bảo `systemctl status patroni` trên DB2 ở trạng thái `active (running)`.

---

## BÀI TEST 3: Sự Cố Máy Chủ Primary & Tự Động Chuyển Dịch (Failover)

- **Mục tiêu**: Đánh giá khả năng tự động thăng cấp Standby khi Primary crash, đo đạc thời gian gián đoạn dịch vụ (RTO) và lượng giao dịch mất mát (RPO).
- **Trạng thái ban đầu**: Ứng dụng Node.js trên APP1 đang chạy hoặc script tạo tải `failover_load_test.js` đang gửi truy vấn ghi liên tục.
- **Lệnh thực thi**:
  ```bash
  # Cửa sổ 1 (Trên APP1): Chạy tải ghi đo đạc
  node /opt/hospital-db-ha/tests/failover/failover_load_test.js

  # Cửa sổ 2 (Trên máy quản trị): Kích hoạt sự cố crash trên DB1
  sudo bash /opt/hospital-db-ha/scripts/tests/test3_primary_failover.sh
  ```
- **Kết quả mong đợi**:
  - DB1 bị dừng đột ngột.
  - Sau khoảng 30s (TTL), etcd giải phóng lease và bầu chọn DB2 hoặc DB3 làm Leader mới.
  - HAProxy cổng 5000 chuyển hướng sang Primary mới.
  - Script trên Cửa sổ 1 ghi nhận giao dịch ghi thành công trở lại và xuất giá trị RTO ($\approx 15 - 35\text{s}$).
- **Cách khôi phục**: Chuyển tiếp sang Bài Test 4 để khôi phục DB1.

---

## BÀI TEST 4: Khôi Phục DB1 Tái Gia Nhập Cụm Với Vai Trò Standby

- **Mục tiêu**: Đưa node Primary cũ trở lại hoạt động mà không gây xung đột ghi (Split-brain), cho phép `pg_rewind` tự động đồng bộ timeline.
- **Trạng thái ban đầu**: DB2 (hoặc DB3) đang là Primary; DB1 đang tắt.
- **Lệnh thực thi**:
  ```bash
  sudo bash /opt/hospital-db-ha/scripts/tests/test4_rejoin_old_primary.sh
  ```
- **Kết quả mong đợi**:
  - DB1 khởi động lại với Patroni.
  - Patroni tự động chạy `pg_rewind` nếu timeline của DB1 phân kỳ.
  - DB1 chuyển thành `Role: Replica`, trạng thái `running`.
  - Cụm quay trở lại trạng thái đủ 3 node (1 Leader, 2 Replicas).

---

## BÀI TEST 5: Diễn Tập Khôi Phục Từ Bản Sao Lưu Độc Lập (Restore Drill)

- **Mục tiêu**: Kiểm tra tính toàn vẹn của kho backup trên MON1 bằng cách khôi phục vào thư mục cách ly mà không làm ảnh hưởng đến CSDL đang vận hành.
- **Trạng thái ban đầu**: Đã có ít nhất 1 bản full backup trên MON1.
- **Lệnh thực thi**:
  ```bash
  sudo bash /opt/hospital-db-ha/scripts/tests/test5_backup_restore.sh
  ```
- **Kết quả mong đợi**:
  - pgBackRest giải nén toàn bộ database vào `/var/lib/postgresql/restore_drill`.
  - Kiểm tra `PG_VERSION` khớp với PostgreSQL 16.
  - Toàn bộ các bảng nghiệp vụ bệnh viện được khôi phục nguyên vẹn.
- **Cách khôi phục**: Thư mục diễn tập được tự động dọn dẹp sau khi kiểm tra xong.

---

## BÀI TEST 6: Máy Chủ Giám Sát & Sao Lưu (MON1) Tạm Dừng Hoạt Động

- **Mục tiêu**: Chứng minh cụm CSDL PostgreSQL vận hành hoàn toàn độc lập với máy MON1.
- **Trạng thái ban đầu**: Toàn bộ 5 máy đang hoạt động.
- **Lệnh thực thi**:
  ```bash
  sudo bash /opt/hospital-db-ha/scripts/tests/test6_mon1_offline.sh
  ```
- **Kết quả mong đợi**:
  - Dịch vụ Prometheus và Grafana trên MON1 bị tắt.
  - Quorum etcd trên {DB1, DB2, DB3} vẫn đạt 3/3 members.
  - Ứng dụng Node.js trên APP1 vẫn thêm mới bệnh nhân và đặt lịch khám thành công 100%.
  - Kết luận: MON1 chỉ đóng vai trò hỗ trợ, không phải SPOF của cụm CSDL.

---

## BÀI TEST 7: Phân Vùng Mạng & Phòng Chống Split-Brain

- **Mục tiêu**: Xác nhận khi phân vùng mạng xảy ra (1 node bị tách rời khỏi 2 node), Quorum etcd sẽ bảo vệ hệ thống không bị 2 Primary nhận ghi cùng lúc.
- **Trạng thái ban đầu**: DB1 đang là Leader.
- **Lệnh thực thi**:
  ```bash
  sudo bash /opt/hospital-db-ha/scripts/tests/test7_split_brain_protection.sh
  ```
- **Kết quả mong đợi**:
  - DB1 bị chặn mạng với DB2 và DB3.
  - etcd trên DB1 chỉ còn 1/3 phiếu -> Mất quorum -> Patroni trên DB1 tự động giáng cấp (Demote) xuống Read-Only.
  - DB2 và DB3 có 2/3 phiếu -> Giữ Quorum -> Bầu 1 Leader mới.
  - Khi cố gắng ghi vào DB1, PostgreSQL từ chối với lỗi Read-Only.
  - Không có xung đột dữ liệu (Zero Split-Brain).
  - Khi gỡ chặn mạng, DB1 tự động đồng bộ lại và làm Standby.
