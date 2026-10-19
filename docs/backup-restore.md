# CHIẾN LƯỢC SAO LƯU & KHÔI PHỤC CƠ SỞ DỮ LIỆU VỚI PGBACKREST

Hướng dẫn toàn diện về thiết lập Stanza, sao lưu đa cấp độ (Full/Diff/Incr), lưu trữ WAL liên tục và phục hồi theo thời gian (PITR) cho hệ thống Bệnh viện.

---

## 1. Nguyên Tắc Thiết Kế: Backup Độc Lập Với HA Replication

> [!IMPORTANT]
> **Streaming Replication KHÔNG PHẢI là Backup!**
> - Replication chỉ giúp chống lại sự cố phần cứng của máy chủ Primary. Nếu một nhân viên hoặc lỗi ứng dụng chạy câu lệnh xóa nhầm (`DROP TABLE appointments` hoặc `DELETE FROM patients`), lệnh xóa đó sẽ được đồng bộ tức thời (trong mili-giây) sang cả hai Standby!
> - Do đó, bắt buộc phải có một giải pháp sao lưu độc lập, lưu trữ ngoài cụm CSDL (đặt tại **MON1 - 100.87.112.76**) bằng **pgBackRest**.

---

## 2. Các Cấp Độ Sao Lưu Trong pgBackRest

1. **Full Backup (Sao lưu toàn phần)**:
   - Sao chép toàn bộ dữ liệu database cluster.
   - Là điểm gốc tham chiếu cho mọi bản sao lưu tiếp theo.
   - Tần suất khuyến nghị: Thực hiện định kỳ hàng tuần hoặc hàng tháng.
2. **Differential Backup (Sao lưu vi sai)**:
   - Chỉ sao lưu những khối dữ liệu (blocks) bị thay đổi so với bản **Full Backup gần nhất**.
   - Thời gian thực thi nhanh hơn, tiết kiệm dung lượng đĩa.
   - Tần suất khuyến nghị: Thực hiện hàng ngày vào nửa đêm.
3. **Continuous WAL Archiving (Lưu trữ nhật ký giao dịch liên tục)**:
   - Thông qua tham số `archive_command = 'pgbackrest --stanza=hospital_cluster archive-push %p'`, mỗi khi một file WAL (16MB) được đóng lại trên Primary, nó sẽ được đẩy ngay sang kho lưu trữ trên MON1 qua kết nối SSH.
   - Nhờ lưu đầy đủ WAL, hệ thống có khả năng phục hồi về bất kỳ giây phút nào trước khi sự cố xảy ra (Point-in-Time Recovery - PITR).

---

## 3. Chính Sách Lưu Trữ (Retention Policy)

Cấu hình trong `/etc/pgbackrest.conf` trên máy MON1:
```ini
[global]
repo1-retention-full=2      # Giữ lại 2 bản Full backup gần nhất
repo1-retention-diff=7      # Giữ lại 7 bản Differential backup
repo1-retention-archive=2   # Giữ các file WAL tương ứng với 2 bản full backup
```
pgBackRest tự động dọn dẹp (expire) các bản backup và file WAL cũ hơn ngưỡng trên để đảm bảo ổ đĩa không bị đầy mà không làm mất tính toàn vẹn của chuỗi phục hồi.

---

## 4. Quy Trình Khôi Phục Về Một Thời Điểm (Point-in-Time Recovery - PITR)

Giả sử vào lúc **2026-10-17 14:30:00**, một lập trình viên vô tình thực hiện thao tác xóa nhầm dữ liệu. Để khôi phục CSDL về trạng thái **2026-10-17 14:29:00** (1 phút trước sự cố):

### Bước 1: Dừng cụm Patroni trên các node CSDL
```bash
sudo systemctl stop patroni
```

### Bước 2: Dọn dẹp data directory hiện tại (Sao lưu lại thư mục cũ để đề phòng)
```bash
sudo mv /var/lib/postgresql/14/main /var/lib/postgresql/14/main.corrupted
sudo mkdir -p /var/lib/postgresql/14/main
sudo chown postgres:postgres /var/lib/postgresql/14/main
sudo chmod 700 /var/lib/postgresql/14/main
```

### Bước 3: Thực hiện lệnh Restore PITR bằng pgBackRest
Thực hiện với quyền user `postgres`:
```bash
sudo -u postgres pgbackrest \
    --stanza=hospital_cluster \
    --type=time \
    --target="2026-10-17 14:29:00+07" \
    --target-action=promote \
    restore
```

pgBackRest sẽ tự động:
1. Tìm bản Full/Diff backup thích hợp trước mốc thời gian đó.
2. Giải nén dữ liệu vào `/var/lib/postgresql/14/main`.
3. Tải các file WAL từ kho lưu trữ và phát lại (replay) các transaction cho tới đúng thời điểm `14:29:00` thì dừng lại.

### Bước 4: Khởi động lại dịch vụ và xác minh dữ liệu
```bash
sudo systemctl start patroni
sudo -u postgres psql -d hospital_db -c "SELECT count(*) FROM patients;"
```

---

## 5. Lưu Ý Về Sao Lưu Ngoài Địa Điểm (Off-site Backup)

Kho sao lưu trên MON1 giải quyết được bài toán hỏng CSDL logic và sự cố máy chủ cục bộ. Tuy nhiên, nếu toàn bộ trung tâm dữ liệu (Datacenter/Phòng lab) gặp sự cố cháy nổ hoặc ngập nước:
- Cần thiết lập tiến trình `rsync` hoặc đồng bộ thư mục `/var/lib/pgbackrest` lên đám mây (Cloud Object Storage: S3, GCS) hoặc một máy chủ đặt tại chi nhánh khác.
