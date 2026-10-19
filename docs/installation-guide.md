# HƯỚNG DẪN TRIỂN KHAI TỪNG BƯỚC TRÊN 5 MÁY CHỦ UBUNTU SERVER 24.04 LTS

Tài liệu hướng dẫn chi tiết quy trình triển khai hệ thống Cơ sở dữ liệu Dự phòng Bệnh viện (Patroni HA + etcd + HAProxy + pgBackRest + Prometheus/Grafana + Node.js API).

---

## 1. Chuẩn Bị Môi Trường Lab

Yêu cầu phần cứng tối thiểu cho mỗi máy (máy ảo KVM / VMware / VirtualBox hoặc máy vật lý):
- **DB1, DB2, DB3**: 2 vCPU, 2 GB RAM, 20 GB Disk, Ubuntu Server 24.04 LTS.
- **APP1**: 1-2 vCPU, 2 GB RAM, 20 GB Disk, Ubuntu Server 24.04 LTS.
- **MON1**: 2 vCPU, 2-4 GB RAM, 30 GB Disk (lưu backup và metrics), Ubuntu Server 24.04 LTS.

---

## 2. Quy Trình Cài Đặt Theo Thứ Tự

### BƯỚC 1: Sao chép dự án và cấu hình biến môi trường
Thực hiện trên máy trạm quản trị hoặc trên từng máy:
```bash
# Clone dự án vào thư mục /opt
sudo git clone <REPO_URL> /opt/hospital-db-ha
cd /opt/hospital-db-ha

# Tạo file .env từ file mẫu và điều chỉnh các địa chỉ IP thực tế
sudo cp .env.example .env
sudo nano .env
```

---

### BƯỚC 2: Khởi tạo hệ thống và Tường lửa trên cả 5 máy
Chạy lần lượt trên từng máy với quyền sudo:

```bash
# Trên máy DB1:
sudo bash /opt/hospital-db-ha/scripts/common/01_system_init.sh db1
sudo bash /opt/hospital-db-ha/scripts/common/02_firewall_setup.sh db

# Trên máy DB2:
sudo bash /opt/hospital-db-ha/scripts/common/01_system_init.sh db2
sudo bash /opt/hospital-db-ha/scripts/common/02_firewall_setup.sh db

# Trên máy DB3:
sudo bash /opt/hospital-db-ha/scripts/common/01_system_init.sh db3
sudo bash /opt/hospital-db-ha/scripts/common/02_firewall_setup.sh db

# Trên máy APP1:
sudo bash /opt/hospital-db-ha/scripts/common/01_system_init.sh app1
sudo bash /opt/hospital-db-ha/scripts/common/02_firewall_setup.sh app

# Trên máy MON1:
sudo bash /opt/hospital-db-ha/scripts/common/01_system_init.sh mon1
sudo bash /opt/hospital-db-ha/scripts/common/02_firewall_setup.sh mon
```

---

### BƯỚC 3: Thiết lập cụm etcd 3 thành viên (DB1, DB2, DB3)
Chạy trên 3 máy CSDL để tạo Quorum:

```bash
# Trên DB1:
sudo bash /opt/hospital-db-ha/scripts/db/11_setup_etcd_node.sh db1

# Trên DB2:
sudo bash /opt/hospital-db-ha/scripts/db/11_setup_etcd_node.sh db2

# Trên DB3:
sudo bash /opt/hospital-db-ha/scripts/db/11_setup_etcd_node.sh db3
```

**Kiểm tra Quorum etcd (trên bất kỳ máy nào trong 3 máy):**
```bash
ETCDCTL_API=3 etcdctl --endpoints=http://127.0.0.1:2379 endpoint health
# Kết quả mong đợi: Cả 3 endpoint đều báo: healthy: took = ...
```

---

### BƯỚC 4: Cài đặt PostgreSQL 16 và Patroni (DB1, DB2, DB3)
Chạy trên cả 3 máy CSDL:

```bash
# Trên DB1, DB2, DB3:
sudo bash /opt/hospital-db-ha/scripts/db/10_install_postgres_patroni.sh
```

---

### BƯỚC 5: Khởi chạy Patroni Service theo thứ tự Primary trước, Standby sau

> [!IMPORTANT]
> **Thứ tự rất quan trọng**: Khởi chạy trên **DB1 trước** để Patroni thực hiện bootstrap khởi tạo cụm PostgreSQL đầu tiên. Sau khi DB1 trở thành Leader, mới khởi chạy DB2 và DB3 để chúng clone dữ liệu làm Standby!

```bash
# 1. Khởi chạy trên DB1 (Khởi tạo cụm):
sudo bash /opt/hospital-db-ha/scripts/db/12_setup_patroni_service.sh db1

# Chờ 10-15s kiểm tra xem DB1 đã nhận vai trò Leader chưa:
sudo patronictl -c /etc/patroni/patroni.yml list

# 2. Sau khi DB1 báo Leader, khởi chạy tiếp trên DB2 và DB3:
# Trên DB2:
sudo bash /opt/hospital-db-ha/scripts/db/12_setup_patroni_service.sh db2

# Trên DB3:
sudo bash /opt/hospital-db-ha/scripts/db/12_setup_patroni_service.sh db3
```

**Kiểm tra trạng thái cụm hoàn chỉnh:**
```bash
sudo patronictl -c /etc/patroni/patroni.yml list
# Kết quả mong đợi:
# + Cluster: hospital-ha-cluster (72...) -----+---------+
# | Member | Host          | Role    | State   | TL | Lag |
# +--------+---------------+---------+---------+----+-----+
# | db1    | 100.115.205.94| Leader  | running |  1 |     |
# | db2    | 100.97.242.2  | Sync/Rep| running |  1 |   0 |
# | db3    | 100.67.87.46  | Replica | running |  1 |   0 |
# +--------+---------------+---------+---------+----+-----+
```

---

### BƯỚC 6: Khởi tạo CSDL Bệnh Viện (`hospital_db`)
Chạy trên máy **DB1** (Primary):

```bash
# Khởi tạo tự động CSDL, tài khoản ứng dụng, schema 10 bảng và dữ liệu mẫu:
sudo bash /opt/hospital-db-ha/scripts/db/13_init_database.sh

# Kiểm tra dữ liệu tức thì trên Standby (DB2) qua IP Tailscale:
sudo -u postgres psql -h 100.97.242.2 -d hospital_db -c "SELECT count(*) FROM patients;"
```

---

### BƯỚC 7: Cài đặt HAProxy và Ứng Dụng Node.js (APP1)
Thực hiện trên máy **APP1 (100.99.89.64)**:

```bash
# 1. Cài đặt và cấu hình HAProxy tự động (đọc IP từ .env)
sudo bash /opt/hospital-db-ha/scripts/app/setup_haproxy.sh

# Kiểm tra kết nối ghi qua HAProxy cổng 5000:
sudo apt-get install -y postgresql-client
PGPASSWORD='Hospital@2026!AppPass' psql -h 127.0.0.1 -p 5000 -U hospital_app_user -d hospital_db -c "SELECT inet_server_addr();"

# 2. Cài đặt Node.js và khởi chạy ứng dụng API
sudo apt-get install -y nodejs npm
cd /opt/hospital-db-ha/app
npm install
npm start &
```

---

### BƯỚC 8: Cài đặt pgBackRest Backup Server & Clients
1. **Trên máy MON1 (Kho sao lưu)**:
```bash
sudo bash /opt/hospital-db-ha/scripts/backup/20_setup_pgbackrest_server.sh
# Sao chép public key hiển thị trên màn hình
```

2. **Trên các máy DB1, DB2, DB3**:
```bash
sudo bash /opt/hospital-db-ha/scripts/backup/21_setup_pgbackrest_client.sh
# Dán public key của MON1 vào /var/lib/postgresql/.ssh/authorized_keys
```

3. **Tạo Stanza và chạy bản sao lưu đầu tiên từ MON1**:
```bash
sudo bash /opt/hospital-db-ha/scripts/backup/backup_full.sh
```

---

### BƯỚC 9: Cài đặt Prometheus & Grafana Giám Sát (MON1)
1. **Cài đặt Exporters trên cả 5 máy**:
```bash
# Chạy trên từng máy tương ứng:
sudo bash /opt/hospital-db-ha/scripts/monitoring/30_install_exporters.sh
```

2. **Cài đặt Prometheus & Grafana trên MON1**:
```bash
sudo bash /opt/hospital-db-ha/scripts/monitoring/31_setup_prometheus_grafana.sh
```

Truy cập Grafana tại `http://100.87.112.76:3001` (admin / admin).
Mở Dashboard **"Hospital PostgreSQL HA Cluster Dashboard"** để theo dõi cụm trực quan!
