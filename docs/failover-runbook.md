# SỔ TAY VẬN HÀNH SỰ CỐ & CHUYỂN DỊCH PRIMARY (FAILOVER RUNBOOK)

Tài liệu quy trình chuẩn (SOP - Standard Operating Procedure) dành cho Quản trị viên CSDL (DBA) và Kỹ sư Vận hành (SRE) khi xử lý sự cố máy chủ Primary hoặc thực hiện bảo trì định kỳ.

---

## 1. Cơ Chế Chuyển Dịch Tự Động (Automatic Failover)

Khi máy chủ Primary (ví dụ: DB1) gặp sự cố phần cứng, mất nguồn hoặc lỗi kernel:
1. **Phát hiện**: Heartbeat gia hạn lease của Patroni tới etcd bị gián đoạn. Sau khoảng thời gian TTL ($30\text{s}$), etcd giải phóng Leader Lock.
2. **Bầu chọn**: Hai node Standby còn lại (DB2 và DB3) phát hiện vị trí Leader trống. Node nào có vị trí WAL (LSN) cao nhất và thỏa mãn điều kiện replication lag sẽ giành Leader Lock trên etcd.
3. **Thăng cấp (Promotion)**: Patroni trên node được chọn ra lệnh PostgreSQL thoát chế độ Recovery (`pg_ctl promote`) và chuyển sang nhận ghi (Read-Write).
4. **Định tuyến (HAProxy)**: Health check `GET /primary` trên cổng 8008 của node cũ chuyển sang `DOWN`. Health check của node mới chuyển sang `UP`. HAProxy ngắt toàn bộ phiên kết nối tới node cũ và chuyển các phiên ghi mới sang node vừa thăng cấp.
5. **Ứng dụng**: Tầng kết nối `pg.Pool` trong ứng dụng Node.js tự động retry theo cơ chế Exponential Backoff, giúp các truy vấn ghi tiếp tục thành công mà ứng dụng không bị sập.

---

## 2. Quy Trình Chuyển Đổi Chủ Động Không Gián Đoạn (Planned Switchover)

Khi cần bảo trì phần cứng, nâng cấp hệ điều hành hoặc cập nhật kernel trên máy chủ Primary mà **không muốn gây downtime đột ngột**:

### Bước 1: Kiểm tra độ trễ đồng bộ trước khi chuyển
Chạy trên bất kỳ máy CSDL nào:
```bash
patronictl -c /etc/patroni/patroni.yml list
```
Đảm bảo các Standby có `Lag = 0` và trạng thái là `running`.

### Bước 2: Thực thi lệnh Switchover qua Patronictl
Chạy lệnh trên máy CSDL:
```bash
sudo patronictl -c /etc/patroni/patroni.yml switchover --master db1 --candidate db2
```
Hệ thống sẽ hỏi xác nhận:
```text
Current cluster topology
+ Member | Host          | Role    | State   | TL | Lag in MB |
+--------+---------------+---------+---------+----+-----------+
| db1    | 100.115.205.94| Leader  | running |  1 |           |
| db2    | 100.97.242.2  | Sync    | running |  1 |         0 |
| db3    | 100.67.87.46  | Replica | running |  1 |         0 |
+--------+---------------+---------+---------+----+-----------+
Candidate ['db2']: db2
When should the switchover take place (e.g. 2026-10-17T19:30 )  [now]: now
Are you sure you want to switch over your cluster to candidate db2? [y/N]: y
```

### Bước 3: Xác minh sau Switchover
1. Kiểm tra lại danh sách thành viên: `db2` trở thành `Leader`, `db1` tự động trở thành `Replica`.
2. Kiểm tra HAProxy trên APP1: Lệnh `curl -s http://100.99.89.64:7000/metrics | grep postgres_primary_back` xác nhận traffic đã chuyển sang DB2.
3. Kiểm tra ứng dụng: Mở giao diện `http://100.99.89.64:3000` kiểm tra IP node Primary hiện tại chuyển thành `100.97.242.2`.
4. Thời gian chuyển đổi chủ động (Controlled Switchover) chỉ mất **dưới 3 đến 5 giây** và RPO = 0.
