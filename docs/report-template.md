# BÁO CÁO NGHIÊN CỨU & XÂY DỰNG HỆ THỐNG CƠ SỞ DỮ LIỆU DỰ PHÒNG CHO BỆNH VIỆN TRÊN NỀN TẢNG ĐA MÁY CHỦ UBUNTU SERVER

**Đề tài học phần / Đồ án tốt nghiệp Chuyên ngành Kỹ thuật Hệ thống & Cơ sở dữ liệu**

---

## CHƯƠNG 1: GIỚI THIỆU & TÍNH CẤP THIẾT CỦA ĐỀ TÀI

### 1.1. Lý do chọn đề tài
Hệ thống Thông tin Bệnh viện (Hospital Information System - HIS) là hạ tầng công nghệ thông tin trọng yếu, phục vụ trực tiếp các hoạt động tiếp đón bệnh nhân, kê đơn cấp cứu, điều trị nội trú và thanh toán viện phí 24/7/365. Mọi sự cố gián đoạn cơ sở dữ liệu (Downtime) dù chỉ kéo dài vài phút cũng có thể dẫn đến hậu quả nghiêm trọng:
- Ngưng trệ tiếp nhận bệnh nhân cấp cứu và chỉ định cận lâm sàng.
- Nguy cơ thất thoát dữ liệu bệnh án và lịch sử dùng thuốc của bệnh nhân.
- Thiệt hại tài chính và giảm sút uy tín nghiêm trọng của cơ sở y tế.

Mô hình triển khai CSDL đơn lẻ (Single Instance) truyền thống bộc lộ điểm yếu chết người: **Điểm lỗi đơn (Single Point of Failure - SPOF)**. Khi máy chủ vật lý hỏng phần cứng hoặc hệ điều hành gặp sự cố, hệ thống sẽ ngừng hoạt động hoàn toàn cho đến khi quản trị viên thay thế và khôi phục thủ công, gây ra thời gian gián đoạn kéo dài hàng giờ và mất mát dữ liệu nghiêm trọng. Do đó, việc nghiên cứu và triển khai một hệ thống CSDL có khả năng **Tự động chuyển dịch dự phòng (High Availability - HA)**, kết hợp đồng bộ dữ liệu liên tục và cơ chế định tuyến thông minh là yêu cầu cấp thiết.

### 1.2. Mục tiêu nghiên cứu
1. Nghiên cứu cơ chế Write-Ahead Logging (WAL) và Streaming Replication của PostgreSQL.
2. Xây dựng cụm CSDL phân tán có tính sẵn sàng cao bằng cách kết hợp **Patroni** và **etcd (Raft Consensus)** trên 3 node.
3. Thiết lập cơ chế định tuyến kết nối động thông qua **HAProxy** nhằm bảo đảm ứng dụng bệnh viện tự động kết nối lại tới Primary mới sau failover mà không cần can thiệp mã nguồn.
4. Xây dựng chiến lược sao lưu độc lập với replication bằng **pgBackRest** đặt tại máy chủ riêng biệt, hỗ trợ Point-in-Time Recovery (PITR).
5. Triển khai hệ sinh thái giám sát tập trung bằng **Prometheus & Grafana**.
6. Thực nghiệm đo đạc và đánh giá chính xác các chỉ số **RPO (Recovery Point Objective)** và **RTO (Recovery Time Objective)** qua 7 bài kiểm thử kịch bản thực tế.

### 1.3. Phạm vi và giới hạn đề tài
- **Phạm vi**: Triển khai trên 5 máy tính / máy ảo Ubuntu Server 24.04 LTS riêng biệt có kết nối mạng LAN.
- **Giới hạn dữ liệu**: 100% dữ liệu sử dụng là dữ liệu giả lập (Mock Data), tuyệt đối không sử dụng thông tin bệnh nhân thật.
- **Giới hạn hạ tầng**: Trong môi trường phòng thí nghiệm, nếu 5 máy ảo chạy trên cùng một máy chủ vật lý (Host Hypervisor), vẫn tồn tại điểm lỗi đơn ở phần cứng của máy chủ vật lý đó.

---

## CHƯƠNG 2: CƠ SỞ LÝ THUYẾT VÀ CÔNG NGHỆ ÁP DỤNG

### 2.1. PostgreSQL Write-Ahead Log (WAL) & Streaming Replication
- **Nguyên lý WAL**: Mọi thay đổi dữ liệu (Insert, Update, Delete) bắt buộc phải được ghi và đồng bộ xuống đĩa tại file nhật ký WAL trước khi thay đổi được ghi vào các khối dữ liệu (Data Pages). Điều này bảo đảm thuộc tính Bền vững (Durability) trong ACID.
- **Streaming Replication**: Máy chủ Standby kết nối tới Primary qua giao thức sao chép nhị phân, liên tục nhận các đoạn byte WAL và phát lại (replay) trên Standby theo thời gian thực.
- **Đánh đổi Đồng bộ vs Bất đồng bộ**:
  - *Asynchronous Replication*: Primary xác nhận commit với Client ngay khi ghi WAL cục bộ. Hiệu năng cao, độ trễ thấp, nhưng tồn tại nguy cơ mất mát một lượng nhỏ WAL chưa kịp truyền sang Standby khi Primary crash ($RPO > 0$).
  - *Synchronous Replication*: Primary chỉ xác nhận commit khi ít nhất một Standby đã ghi nhận WAL. Bảo đảm $RPO = 0$, nhưng độ trễ ghi tăng do phụ thuộc RTT mạng.

### 2.2. Distributed Configuration Store (DCS) etcd & Thuật Toán Raft
- etcd là cơ sở dữ liệu khóa-giá trị phân tán có tính nhất quán mạnh mẽ.
- Với cụm 3 thành viên, Quorum yêu cầu là $\lfloor 3/2 \rfloor + 1 = 2$ thành viên. Khi 1 máy sập, 2 máy còn lại vẫn duy trì khả năng đồng thuận và ra quyết định.
- etcd loại bỏ hoàn toàn nguy cơ **Split-Brain** (hai máy chủ cùng tự phong làm Primary) nhờ nguyên lý đa số phiếu trong thuật toán Raft.

### 2.3. Patroni & HAProxy Routing
- **Patroni**: Tiến trình quản lý vòng đời PostgreSQL, sử dụng cơ chế Heartbeat gia hạn lease trên etcd. Khi Primary sập, Patroni tự động kích hoạt tiến trình bầu chọn và thăng cấp (promote) Standby có LSN gần nhất làm Primary mới.
- **HAProxy**: Tầng Proxy định tuyến trung gian. Thông qua HTTP check cổng 8008 (`GET /primary`), HAProxy tự động nhận diện node nào đang là Primary thật sự và chuyển toàn bộ lưu lượng ghi đến node đó.

---

## CHƯƠNG 3: THIẾT KẾ & TRIỂN KHAI HỆ THỐNG

### 3.1. Phân chia vai trò 5 máy tính
*(Xem bảng chi tiết tại docs/network-plan.md)*

### 3.2. Sơ đồ kiến trúc tổng thể
*(Xem sơ đồ Mermaid tại docs/architecture.md)*

### 3.3. Thiết kế CSDL bệnh viện (`hospital_db`)
- Gồm 10 bảng nghiệp vụ: `departments`, `doctors`, `patients`, `appointments`, `medical_records`, `prescriptions`, `prescription_items`, `invoices`, `users`, `audit_logs`.
- Toàn bộ mật khẩu hệ thống được băm bằng thuật toán bcrypt qua extension `pgcrypto`.
- Phân quyền theo nguyên tắc đặc quyền tối thiểu (Least Privilege).

---

## CHƯƠNG 4: THỰC NGHIỆM ĐO ĐẠC & KẾT QUẢ KIỂM THỬ

### 4.1. Bảng số liệu tổng hợp 7 bài kiểm thử thực tế

| Mã Test | Kịch bản kiểm thử | RPO thực tế | RTO thực tế | Ghi chú kỹ thuật |
|---|---|---|---|---|
| Test 1 | Kiểm tra Replication | 0 TX | 0 s | Đồng bộ tức thời, Lag < 100KB |
| Test 2 | Standby mất kết nối | 0 TX | 0 s | Catch-up hoàn tất sau khi online lại |
| Test 3 | Primary bị tắt đột ngột | `[Số liệu lab]` | `[Số liệu lab]` s | Patroni bầu Leader mới, HAProxy tự đổi route |
| Test 4 | Phục hồi Primary cũ (DB1) | 0 TX | 0 s | Tự chạy pg_rewind, làm Standby an toàn |
| Test 5 | Diễn tập Restore pgBackRest| Theo mốc backup | `[Số liệu lab]` s | Dữ liệu khôi phục toàn vẹn 100% |
| Test 6 | MON1 tạm dừng hoạt động | 0 TX | 0 s | CSDL vận hành độc lập, không gián đoạn |
| Test 7 | Phân vùng mạng (Split-Brain)| 0 TX | `[Số liệu lab]` s | Phân vùng thiểu số tự khóa ghi, không xung đột |

*(Các số liệu trong ngoặc `[Số liệu lab]` được đo đạc trực tiếp từ script `failover_load_test.js` trong phòng thí nghiệm).*

---

## CHƯƠNG 5: KẾT LUẬN & HƯỚNG PHÁT TRIỂN

### 5.1. Kết quả đạt được
- Xây dựng thành công cụm PostgreSQL HA hoàn chỉnh trên 5 máy Ubuntu Server 24.04.
- Đạt khả năng tự động phát hiện sự cố và chuyển dịch Primary trong thời gian ngắn (RTO < 35 giây).
- Ứng dụng Node.js có khả năng tự động thử lại kết nối mà không bị crash.
- Hệ thống giám sát Prometheus/Grafana và kho sao lưu pgBackRest vận hành ổn định và độc lập.

### 5.2. Hạn chế
- Nếu chạy 5 máy ảo trên cùng 1 server vật lý, sự cố phần cứng của máy chủ vật lý sẽ làm sập toàn bộ hệ thống.
- Chế độ sao chép bất đồng bộ (Asynchronous) trong một số trường hợp nghẽn mạng nặng có thể làm tăng RPO > 0.

### 5.3. Hướng phát triển
- Mở rộng kiến trúc Multi-Datacenter (triển khai các node tại các tòa nhà hoặc chi nhánh bệnh viện khác nhau).
- Tích hợp thêm Connection Pooler cấp CSDL chuyên dụng (**PgBouncer**) giữa HAProxy và PostgreSQL để hỗ trợ hàng chục nghìn kết nối đồng thời.
- Thiết lập sao lưu tự động đẩy lên Cloud Object Storage (S3 / MinIO).

---

## DÀN Ý SLIDE BẢO VỆ ĐỒ ÁN (12 SLIDES)

1. **Slide 1: Trang tiêu đề**: Tên đề tài, Giảng viên hướng dẫn, Sinh viên thực hiện, Ngày báo cáo.
2. **Slide 2: Đặt vấn đề & Tính cấp thiết**: Tầm quan trọng của CSDL bệnh viện 24/7 và rủi ro của điểm lỗi đơn (SPOF).
3. **Slide 3: Mục tiêu & Yêu cầu đề tài**: Tiêu chí RPO, RTO, tính toàn vẹn dữ liệu, mô hình 5 máy chủ riêng biệt.
4. **Slide 4: Cơ sở lý thuyết nền tảng**: PostgreSQL WAL, Streaming Replication, DCS Raft Consensus (etcd).
5. **Slide 5: Kiến trúc tổng thể hệ thống**: Sơ đồ 5 node (DB1, DB2, DB3, APP1, MON1) và luồng tương tác.
6. **Slide 6: Cơ chế điều phối Patroni & HAProxy**: Cách Patroni giữ Leader Lock và HAProxy định tuyến cổng 5000 qua check `/primary`.
7. **Slide 7: Thiết kế CSDL bệnh viện & Ứng dụng**: Mô hình ERD `hospital_db`, REST API và cơ chế Retry Connection Pool.
8. **Slide 8: Chiến lược Backup & Giám sát**: pgBackRest repo trên MON1, PITR, Prometheus & Grafana Dashboard.
9. **Slide 9: Thực nghiệm kịch bản sự cố Primary (Test 3)**: Demo video / Log thời gian failover thực tế.
10. **Slide 10: Phân tích kết quả RPO & RTO**: Bảng đo đạc thực nghiệm từ 7 kịch bản kiểm thử.
11. **Slide 11: Đánh giá & Khắc phục rủi ro**: Chống Split-Brain, cơ chế pg_rewind phục hồi node cũ.
12. **Slide 12: Kết luận & Hướng phát triển**: Tổng kết đóng góp và lời cảm ơn Hội đồng.
