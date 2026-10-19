#!/usr/bin/env bash
# ==============================================================================
# FIREWALL SETUP SCRIPT (UFW)
# Thiết lập tường lửa theo nguyên tắc phân quyền tối thiểu (Least Privilege)
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00_env_loader.sh"

require_root

ROLE="${1:-}"

if [[ -z "$ROLE" ]]; then
    # Tự động suy đoán role dựa trên hostname
    CURRENT_HOST="$(hostname)"
    case "$CURRENT_HOST" in
        db1|db2|db3) ROLE="db" ;;
        app1)        ROLE="app" ;;
        mon1)        ROLE="mon" ;;
        *)
            log_error "Không thể tự nhận diện vai trò máy chủ. Hãy truyền tham số: db, app, hoặc mon."
            echo "Ví dụ: sudo $0 db"
            exit 1
            ;;
    esac
fi

log_info "=== CẤU HÌNH TƯỜNG LỬA UFW CHO VAI TRÒ: ${ROLE^^} ==="

apt-get install -y -qq ufw

# Đặt chính sách mặc định: chặn toàn bộ incoming, cho phép outgoing
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# 1. Cho phép SSH (Cổng 22) từ toàn bộ dải mạng lab
ufw allow 22/tcp comment "SSH Management"

# HỖ TRỢ ĐẶC BIỆT KHI DÙNG MẠNG ẢO TAILSCALE
if ip link show tailscale0 >/dev/null 2>&1; then
    log_info "Phát hiện card mạng ảo Tailscale (tailscale0). Cấu hình mở thông suốt Tailscale VPN..."
    # Mở toàn bộ luồng traffic giữa các node thông qua giao diện tailscale0 được mã hóa WireGuard
    ufw allow in on tailscale0 comment "Allow all incoming on Tailscale VPN interface"
    # Mở cổng 41641 UDP cho Tailscale thiết lập kết nối trực tiếp P2P (tránh đi qua DERP relay chậm)
    ufw allow 41641/udp comment "Tailscale WireGuard Direct Peer Connection"
    log_success "Đã mở quyền kết nối thông suốt cho giao diện tailscale0 và cổng 41641/udp."
fi

case "$ROLE" in
    db)
        log_info "Mở các cổng dịch vụ cho Node CSDL (PostgreSQL, Patroni, etcd, Exporters)..."
        # PostgreSQL 5432: Cho phép từ các DB nodes khác, APP1 và MON1
        ufw allow from "${CLUSTER_SUBNET}" to any port 5432 proto tcp comment "PostgreSQL Cluster & Clients"
        
        # Patroni REST API 8008: Cho phép từ APP1 (HAProxy check), DB nodes và MON1 (Prometheus)
        ufw allow from "${CLUSTER_SUBNET}" to any port 8008 proto tcp comment "Patroni REST API Health Check"
        
        # etcd client (2379): Cho phép từ 3 DB nodes và MON1
        ufw allow from "${CLUSTER_SUBNET}" to any port 2379 proto tcp comment "etcd Client API"
        
        # etcd peer (2380): CHỈ CHO PHÉP GIỮA 3 DB NODES
        ufw allow from "${DB1_IP}" to any port 2380 proto tcp comment "etcd Peer DB1"
        ufw allow from "${DB2_IP}" to any port 2380 proto tcp comment "etcd Peer DB2"
        ufw allow from "${DB3_IP}" to any port 2380 proto tcp comment "etcd Peer DB3"
        
        # Exporters: Chỉ cho phép MON1 thu thập
        ufw allow from "${MON1_IP}" to any port 9100 proto tcp comment "node_exporter"
        ufw allow from "${MON1_IP}" to any port 9187 proto tcp comment "postgres_exporter"
        ;;

    app)
        log_info "Mở các cổng dịch vụ cho Máy Ứng Dụng (Node.js API, HAProxy)..."
        # REST API Bệnh viện
        ufw allow 3000/tcp comment "Hospital REST API Web"
        
        # HAProxy Database Ports
        ufw allow from 127.0.0.1 to any port 5000 proto tcp comment "HAProxy Primary Local"
        ufw allow from "${CLUSTER_SUBNET}" to any port 5000 proto tcp comment "HAProxy Primary Cluster"
        ufw allow from 127.0.0.1 to any port 5001 proto tcp comment "HAProxy Standby Local"
        
        # HAProxy Stats Dashboard (Port 7000)
        ufw allow from "${CLUSTER_SUBNET}" to any port 7000 proto tcp comment "HAProxy Stats & Metrics"
        
        # node_exporter
        ufw allow from "${MON1_IP}" to any port 9100 proto tcp comment "node_exporter"
        ;;

    mon)
        log_info "Mở các cổng dịch vụ cho Máy Giám Sát & Backup (Prometheus, Grafana)..."
        # Grafana Web Dashboard
        ufw allow 3001/tcp comment "Grafana Web UI"
        
        # Prometheus Web & API
        ufw allow from "${CLUSTER_SUBNET}" to any port 9090 proto tcp comment "Prometheus Server"
        
        # node_exporter
        ufw allow from 127.0.0.1 to any port 9100 proto tcp comment "node_exporter Local"
        ;;
esac

# Bật tường lửa
ufw --force enable
ufw status verbose
log_success "Thiết lập tường lửa UFW cho vai trò ${ROLE^^} hoàn tất."
