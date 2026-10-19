# Bảng Ma Trận Đánh Giá Kết Quả Kiểm Thử (Lab Test Execution Matrix)

| Mã kiểm thử | Tên kịch bản | Điều kiện ban đầu | Thao tác thực hiện | Kỳ vọng kỹ thuật | Kết quả thực tế | Trạng thái |
|---|---|---|---|---|---|---|
| **TC-01** | Kiểm tra Replication ban đầu | DB1: Primary, DB2: Standby, DB3: Standby | Chèn 1 bệnh nhân mới trên DB1 | Dữ liệu xuất hiện trên DB2 & DB3 < 1s, Lag = 0 | `[Chờ điền]` | CHỜ THỰC THI |
| **TC-02** | Standby DB2 ngắt kết nối tạm thời | Cụm 3 node đang chạy ổn định | `systemctl stop patroni` trên DB2, ghi 5 TX trên DB1 | DB1 ghi bình thường; DB2 online trở lại tự bắt kịp WAL | `[Chờ điền]` | CHỜ THỰC THI |
| **TC-03** | Primary DB1 gặp sự cố đột ngột | Ứng dụng Node.js đang gửi tải ghi 5 TX/s | `systemctl stop patroni` trên DB1 | Patroni bầu DB2/DB3 làm Primary; HAProxy đổi route; App reconnect | `[Chờ điền]` | CHỜ THỰC THI |
| **TC-04** | Khôi phục DB1 sau khi failover | DB2 đang là Primary mới | Khởi động patroni trên DB1 | DB1 tự chạy pg_rewind, tái gia nhập làm Standby | `[Chờ điền]` | CHỜ THỰC THI |
| **TC-05** | Diễn tập Restore từ pgBackRest | MON1 có ít nhất 1 bản full backup | Chạy `restore_drill.sh` vào thư mục cô lập | Bản backup giải nén toàn vẹn; schema và bảng khớp 100% | `[Chờ điền]` | CHỜ THỰC THI |
| **TC-06** | Máy MON1 offline | Cụm PostgreSQL & APP1 đang chạy | Dừng Prometheus & Grafana trên MON1 | CSDL vẫn xử lý giao dịch ghi/đọc bình thường không bị block | `[Chờ điền]` | CHỜ THỰC THI |
| **TC-07** | Phân vùng mạng 1 node vs 2 node | DB1 bị cô lập mạng bằng iptables | Chặn toàn bộ traffic giữa DB1 và {DB2, DB3} | DB1 tự giáng cấp; {DB2, DB3} giữ quorum bầu 1 Leader; Không split-brain | `[Chờ điền]` | CHỜ THỰC THI |
