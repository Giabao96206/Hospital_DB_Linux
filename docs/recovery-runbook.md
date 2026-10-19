# SỔ TAY PHỤC HỒI HỆ THỐNG VÀ TÁI GIA NHẬP CỤM (RECOVERY RUNBOOK)

Hướng dẫn kỹ thuật giải quyết các tình huống phục hồi sau sự cố, tái đồng bộ node cũ, xử lý phân kỳ timeline và khôi phục Quorum DCS.

---

## 1. Quy Trình Phục Hồi Node Cũ Làm Standby

Khi máy chủ DB1 (sau khi bị sập hoặc bảo trì xong) được bật lại:

> [!CAUTION]
> **QUY TẮC SỐNG CÒN:** Tuyệt đối KHÔNG chạy lệnh `pg_ctl start` trực tiếp hoặc cố gắng thăng cấp DB1 làm Primary! Việc này sẽ tạo ra 2 Primary cùng nhận ghi (Split-brain) và phá hủy tính toàn vẹn dữ liệu bệnh viện.

### Các bước thực hiện chuẩn:
1. Đảm bảo dịch vụ `etcd` trên DB1 đã khởi động và gia nhập lại cụm:
   ```bash
   sudo systemctl status etcd
   ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 endpoint health
   ```
2. Khởi động dịch vụ Patroni:
   ```bash
   sudo systemctl start patroni
   ```
3. **Cơ chế tự động của Patroni**:
   - Patroni trên DB1 sẽ kết nối tới etcd, nhận biết rằng cụm đã có một Leader hợp lệ (ví dụ DB2).
   - Patroni so sánh LSN và Timeline của PostgreSQL cục bộ với Leader.
   - Nếu có các giao dịch uncommitted hoặc phân kỳ timeline, Patroni sẽ tự động gọi tiện ích `pg_rewind` kết nối sang DB2 để cuộn lại data_dir về điểm chia nhánh.
   - Sau đó, Patroni khởi động PostgreSQL ở chế độ Standby (`standby.signal`) và kết nối vào stream của DB2.
4. Kiểm tra xác nhận:
   ```bash
   sudo patronictl -c /etc/patroni/patroni.yml list
   # DB1 phải có Role là 'Replica' và State là 'running'.
   ```

---

## 2. Xử Lý Tái Khởi Tạo Standby Khi Bị Lỗi Nặng (`patronictl reinit`)

Trong trường hợp đĩa cứng của một Standby bị bad sector hoặc timeline bị lỗi quá sâu mà `pg_rewind` không thể tự xử lý:

```bash
# Thực hiện trên bất kỳ node nào còn khỏe mạnh:
sudo patronictl -c /etc/patroni/patroni.yml reinit hospital-ha-cluster <tên_member_lỗi>

# Ví dụ tái khởi tạo DB3:
sudo patronictl -c /etc/patroni/patroni.yml reinit hospital-ha-cluster db3
```
*Lệnh này sẽ xóa data directory trên node đích, gọi `pg_basebackup` sao chép lại toàn bộ trạng thái chuẩn từ Primary hiện tại và cấu hình lại streaming replication tự động.*

---

## 3. Khôi Phục Cụm Khi Mất Quorum etcd

Cụm etcd 3 thành viên cần tối thiểu 2 thành viên online để đạt Quorum. Nếu 2 máy (ví dụ DB1 và DB2) đồng thời mất điện, chỉ còn DB3 online:
- Cụm etcd rơi vào trạng thái read-only DCS, Patroni sẽ khóa ghi toàn bộ để đảm bảo an toàn.
- **Cách khôi phục**:
  1. Ưu tiên khởi động lại ít nhất 1 node đã sập (DB1 hoặc DB2) để đạt lại Quorum 2/3.
  2. Nếu phần cứng của 2 máy kia hỏng hoàn toàn và buộc phải vận hành khẩn cấp chỉ với DB3:
     ```bash
     # Trên DB3: Buộc etcd xóa bỏ các thành viên cũ và tạo lại cụm 1 node duy nhất
     sudo systemctl stop etcd
     sudo -u etcd etcd --force-new-cluster --config-file=/etc/etcd/etcd.conf.yml &
     # Sau đó cập nhật lại DCS để Patroni thăng cấp DB3
     ```
