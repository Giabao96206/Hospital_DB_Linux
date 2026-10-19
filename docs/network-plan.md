# KẾ HOẠCH QUY HOẠCH MẠNG & BẢO MẬT TƯỜNG LỬA (TAILSCALE MESH NETWORK)

Tài liệu quy định chi tiết về địa chỉ IP, phân giải tên miền, ma trận cổng dịch vụ và thiết lập tường lửa cho 5 máy chủ trong hệ thống CSDL Bệnh viện HA kết nối thông qua mạng ảo Tailscale.

---

## 1. Bảng Phân Bổ Địa Chỉ Mạng Tailscale (5 Nodes Thực Tế)

| Hostname | Vai trò trong hệ thống | Địa chỉ IP Tailscale | Hệ điều hành | Card mạng kết nối |
|---|---|---|---|---|
| **db1** | Primary ban đầu (PostgreSQL 14 + Patroni + etcd) | `100.115.205.94` | Ubuntu Server 22.04 LTS | `tailscale0` |
| **db2** | Standby 1 (PostgreSQL 14 + Patroni + etcd) | `100.97.242.2` | Ubuntu Server 22.04 LTS | `tailscale0` |
| **db3** | Standby 2 (PostgreSQL 14 + Patroni + etcd) | `100.67.87.46` | Ubuntu Server 22.04 LTS | `tailscale0` |
| **app1** | Application Server (Node.js API + HAProxy) | `100.99.89.64` | Ubuntu Server 22.04 LTS | `tailscale0` |
| **mon1** | Monitoring & Backup (Prometheus, Grafana, pgBackRest) | `100.87.112.76` | Ubuntu Server 22.04 LTS | `tailscale0` |

> [!NOTE]
> Mạng Tailscale sử dụng dải IP toàn cục `100.64.0.0/10` (CGNAT range). Toàn bộ gói tin trao đổi giữa 5 máy được mã hóa tự động bằng giao thức WireGuard, giúp liên lạc an toàn và loại bỏ hoàn toàn các vấn đề về NAT, đổi IP Wi-Fi hay khác lớp mạng vật lý.

---

## 2. Bảng Phân Giải Tên Miền Nội Bộ (`/etc/hosts`)

Trên cả 5 máy chủ, file `/etc/hosts` được cấu hình đồng bộ như sau (hoặc tự động dùng MagicDNS của Tailscale):

```text
127.0.0.1 localhost
127.0.1.1 <tên_máy_tương_ứng>

# hospital-ha-hosts - Bản đồ định tuyến nội bộ qua Tailscale
100.115.205.94 db1
100.97.242.2   db2
100.67.87.46   db3
100.99.89.64   app1
100.87.112.76  mon1
```

---

## 3. Ma Trận Cổng Dịch Vụ (Port Matrix Qua Tailscale)

| Cổng (Port) | Giao thức | Dịch vụ | Nguồn cho phép (Source) | Đích (Destination) | Mục đích sử dụng |
|---|---|---|---|---|---|
| `41641` | UDP | WireGuard P2P | Mạng Internet / LAN | 5 máy | Cổng kết nối trực tiếp Peer-to-Peer của Tailscale |
| `22` | TCP | OpenSSH | Toàn bộ Tailscale Mesh | 5 máy | Quản trị từ xa và SSH key exchange cho pgBackRest |
| `5432` | TCP | PostgreSQL | `app1`, `mon1`, `db1`, `db2`, `db3` | `db1`, `db2`, `db3` | Truy vấn CSDL và Streaming Replication |
| `8008` | TCP | Patroni REST API | `app1`, `mon1`, `db1`, `db2`, `db3` | `db1`, `db2`, `db3` | HAProxy health check (`/primary`) & Prometheus scrape |
| `2379` | TCP | etcd Client API | `db1`, `db2`, `db3`, `mon1` | `db1`, `db2`, `db3` | Patroni giao tiếp với DCS và Prometheus metrics |
| `2380` | TCP | etcd Peer Traffic| **CHỈ** `db1`, `db2`, `db3` | `db1`, `db2`, `db3` | Đồng thuận Raft nội bộ giữa 3 thành viên etcd |
| `3000` | TCP | Hospital Web API | Trình duyệt quản trị / Tailnet | `app1` | Giao diện quản lý bệnh viện & REST API |
| `5000` | TCP | HAProxy Primary | `127.0.0.1` & `app1` | `app1` | Định tuyến kết nối ghi tới Primary hiện tại |
| `5001` | TCP | HAProxy Replicas| `127.0.0.1` & `app1` | `app1` | Cân bằng tải kết nối đọc tới các Standby |
| `7000` | TCP | HAProxy Stats | `100.87.112.76` (mon1) / Admin | `app1` | Trang thống kê HAProxy & Prometheus exporter |
| `9090` | TCP | Prometheus | Trình duyệt DBA / Tailnet | `mon1` | Giao diện truy vấn PromQL |
| `3001` | TCP | Grafana | Trình duyệt DBA / Tailnet | `mon1` | Dashboard trực quan hóa giám sát cụm HA |
| `9100` | TCP | Node Exporter | `100.87.112.76` (mon1) | 5 máy | Thu thập thông số CPU, RAM, Disk, Mạng |
| `9187` | TCP | Postgres Exporter| `100.87.112.76` (mon1) | `db1`, `db2`, `db3` | Thu thập metrics CSDL chuyên sâu |

---

## 4. Hướng Dẫn Kiểm Tra Kết Nối Tailscale Trước Khi Khởi Chạy

Chạy các lệnh kiểm tra sau trên máy **APP1** hoặc **DB1**:

```bash
# 1. Kiểm tra trạng thái toàn bộ các máy trong mạng Tailscale
tailscale status

# 2. Kiểm tra độ trễ (Ping) trực tiếp qua card tailscale0
tailscale ping 100.115.205.94  # Ping DB1
tailscale ping 100.97.242.2    # Ping DB2
tailscale ping 100.67.87.46    # Ping DB3
tailscale ping 100.87.112.76   # Ping MON1

# 3. Kiểm tra cổng SSH mở qua mạng Tailscale
for ip in 100.115.205.94 100.97.242.2 100.67.87.46 100.99.89.64 100.87.112.76; do
    nc -zv -w 2 $ip 22 2>&1 | grep -q "succeeded" && echo "✅ $ip:22 OPEN" || echo "❌ $ip:22 CLOSED"
done
```
