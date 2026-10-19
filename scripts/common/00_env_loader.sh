#!/usr/bin/env bash
# ==============================================================================
# COMMON ENVIRONMENT LOADER & LOGGING UTILITY
# Dự án: Hệ thống CSDL Dự phòng Bệnh viện (Ubuntu Server 24.04 LTS)
# ==============================================================================

set -euo pipefail

# Màu sắc hiển thị terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Hàm ghi log có timestamp
log_info() {
    echo -e "${CYAN}[INFO]  $(date '+%Y-%m-%d %H:%M:%S') - ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}[OK]    $(date '+%Y-%m-%d %H:%M:%S') - ${1}${NC}"
}

log_warn() {
    echo -e "${YELLOW}[WARN]  $(date '+%Y-%m-%d %H:%M:%S') - ${1}${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - ${1}${NC}" >&2
}

# Kiểm tra quyền root / sudo
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Script này bắt buộc phải chạy với quyền root (hoặc sudo)."
        exit 1
    fi
}

# Yêu cầu xác nhận an toàn trước các thao tác nguy hiểm
confirm_action() {
    local prompt_msg="${1:-Bạn có chắc chắn muốn thực hiện thao tác này?}"
    if [[ "${FORCE_CONFIRM:-false}" == "true" ]]; then
        return 0
    fi
    echo -e -n "${YELLOW}${BOLD}[CẢNH BÁO] ${prompt_msg} (yes/no): ${NC}"
    read -r response
    if [[ "$response" != "yes" ]]; then
        log_info "Người dùng đã hủy thao tác."
        exit 0
    fi
}

# Tìm và nạp file .env
load_env() {
    local env_file=""
    # Các vị trí tìm kiếm file .env theo thứ tự ưu tiên
    local search_paths=(
        "$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")/.env"
        "/etc/hospital-ha/.env"
        "$(pwd)/.env"
        "$(pwd)/../.env"
    )

    for p in "${search_paths[@]}"; do
        if [[ -f "$p" ]]; then
            env_file="$p"
            break
        fi
    done

    if [[ -z "$env_file" ]]; then
        log_warn "Không tìm thấy file .env thực tế. Đang tìm .env.example để tham chiếu..."
        for p in "${search_paths[@]}"; do
            if [[ -f "${p}.example" ]]; then
                env_file="${p}.example"
                log_warn "Sử dụng cấu hình mẫu: ${env_file}. HÃY TẠO FILE .env ĐỂ ĐẢM BẢO CHÍNH XÁC!"
                break
            fi
        done
    fi

    if [[ -n "$env_file" ]]; then
        log_info "Đang nạp cấu hình từ: ${env_file}"
        # Xuất các biến môi trường từ file, bỏ qua comment
        set -a
        # shellcheck disable=SC1090
        source <(grep -v '^#' "$env_file" | grep -v '^\s*$')
        set +a
    else
        log_error "Không tìm thấy bất kỳ file cấu hình môi trường nào (.env hoặc .env.example)!"
        exit 1
    fi
}

# Tự động nạp môi trường khi script được source
load_env
