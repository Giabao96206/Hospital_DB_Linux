#!/usr/bin/env bash
# ==============================================================================
# SYSTEM INITIALIZATION & KERNEL TUNING SCRIPT
# Chạy trên tất cả 5 máy chủ Ubuntu Server 24.04 LTS
# ==============================================================================

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/00_env_loader.sh"

require_root

TARGET_HOSTNAME="${1:-}"

log_info "=== BẮT ĐẦU KHỞI TẠO HỆ THỐNG TRÊN $(hostname) ==="

# 1. ĐẶT HOSTNAME NẾU ĐƯỢC CHỈ ĐỊNH
if [[ -n "$TARGET_HOSTNAME" ]]; then
    log_info "Thiết lập hostname thành: ${TARGET_HOSTNAME}"
    hostnamectl set-hostname "${TARGET_HOSTNAME}"
fi

CURRENT_HOST="$(hostname)"
log_info "Hostname hiện tại: ${CURRENT_HOST}"

# 2. CẬP NHẬT /etc/hosts CHO CẢ 5 MÁY
log_info "Cập nhật bảng phân giải tên miền nội bộ /etc/hosts..."
sed -i '/hospital-ha-hosts/d' /etc/hosts
cat <<EOF >> /etc/hosts
# hospital-ha-hosts - Bản đồ định tuyến nội bộ 5 máy
${DB1_IP} ${DB1_HOSTNAME}
${DB2_IP} ${DB2_HOSTNAME}
${DB3_IP} ${DB3_HOSTNAME}
${APP1_IP} ${APP1_HOSTNAME}
${MON1_IP} ${MON1_HOSTNAME}
# hospital-ha-hosts
EOF
log_success "Đã cập nhật /etc/hosts thành công."

# 3. ĐỒNG BỘ THỜI GIAN QUA CHRONY (RẤT QUAN TRỌNG VỚI ETCD VÀ POSTGRESQL WAL)
log_info "Cài đặt và cấu hình đồng bộ thời gian Chrony..."
apt-get update -y -qq
apt-get install -y -qq chrony curl wget software-properties-common jq net-tools

systemctl enable --now chrony
chronyc tracking || true
log_success "Chrony đã được kích hoạt và đồng bộ thời gian."

# 4. TỐI ƯU KERNEL SYSCTL CHO POSTGRESQL VÀ ETCD
log_info "Áp dụng cấu hình kernel tối ưu cho CSDL và mạng..."
cat <<EOF > /etc/sysctl.d/99-hospital-ha.conf
# Quản lý bộ nhớ cho PostgreSQL
vm.swappiness = 10
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Giới hạn file descriptors và connection queues
fs.file-max = 2097152
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# Tránh kernel hang do thiếu ARP cache khi cluster failover
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
EOF

sysctl --system > /dev/null
log_success "Tối ưu Kernel sysctl hoàn tất."

# 5. CẤU HÌNH LIMITS CHO USER POSTGRES
cat <<EOF > /etc/security/limits.d/99-postgres.conf
postgres soft nofile 65536
postgres hard nofile 65536
postgres soft nproc 4096
postgres hard nproc 4096
EOF
log_success "Đã cấu hình ulimit cho người dùng postgres."

log_success "=== HOÀN TẤT KHỞI TẠO HỆ THỐNG TRÊN ${CURRENT_HOST} ==="
