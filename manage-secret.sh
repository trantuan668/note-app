#!/bin/bash

# ==== Cấu hình ====
SECRET_FILE="./proxy-secret"
EXPIRE_DB="./secret-expiry.db"
CONTAINER_NAME="mtproto-proxy"
DOMAIN_OR_IP="yourdomain.com"  # ← Thay bằng domain hoặc IP thật

# ==== Màu ====
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

# ==== Kiểm tra file ====
touch "$SECRET_FILE"
touch "$EXPIRE_DB"

# ==== Kiểm tra định dạng ====
function validate_secret() {
  [[ "$1" =~ ^[a-fA-F0-9]{32}$ ]] || {
    echo -e "${RED}SECRET không hợp lệ. Phải là chuỗi hex 32 ký tự.${NC}"
    return 1
  }
  return 0
}

# ==== Khởi động lại container ====
function restart_container() {
  echo -e "${YELLOW}Khởi động lại container...${NC}"
  docker restart "$CONTAINER_NAME" >/dev/null
  echo -e "${GREEN}Đã khởi động lại.${NC}"
}

# ==== Thêm SECRET ====
function add_secret() {
  secret="$1"
  ttl_min="$2"
  validate_secret "$secret" || return
  grep -qxF "$secret" "$SECRET_FILE" && {
    echo -e "${YELLOW}SECRET đã tồn tại.${NC}"
    return
  }
  echo "$secret" >> "$SECRET_FILE"
  if [[ -n "$ttl_min" ]]; then
    expire_time=$(( $(date +%s) + ttl_min * 60 ))
    echo "$secret $expire_time" >> "$EXPIRE_DB"
    echo -e "${GREEN}Đã thêm SECRET (hết hạn sau $ttl_min phút).${NC}"
  else
    echo -e "${GREEN}Đã thêm SECRET không thời hạn.${NC}"
  fi
  restart_container
}

# ==== Tạo SECRET ngẫu nhiên ====
function generate_secret() {
  openssl rand -hex 16
}

# ==== Dọn SECRET hết hạn ====
function clean_expired() {
  echo -e "${YELLOW}Đang dọn các SECRET hết hạn...${NC}"
  now=$(date +%s)
  cleaned=0
  while read -r secret expire; do
    if (( expire <= now )); then
      grep -vxF "$secret" "$SECRET_FILE" > "$SECRET_FILE.tmp" && mv "$SECRET_FILE.tmp" "$SECRET_FILE"
      grep -v "^$secret " "$EXPIRE_DB" > "$EXPIRE_DB.tmp" && mv "$EXPIRE_DB.tmp" "$EXPIRE_DB"
      echo -e "→ Xoá $secret (đã hết hạn)"
      cleaned=1
    fi
  done < "$EXPIRE_DB"
  (( cleaned == 0 )) && echo -e "${GREEN}Không có SECRET nào hết hạn.${NC}" || restart_container
}

# ==== Tạo URL Proxy ====
function generate_url() {
  read -p "Nhập SECRET cần tạo URL: " input_secret
  validate_secret "$input_secret" || return
  echo -e "${GREEN}URL Telegram Proxy:${NC}"
  echo "tg://proxy?server=$DOMAIN_OR_IP&port=443&secret=$input_secret"
}

# ==== Menu chính ====
function main_menu() {
  clear
  echo -e "${YELLOW}====== QUẢN LÝ MTProxy - SECRET ======${NC}"
  echo "1. Tạo SECRET ngẫu nhiên (vô thời hạn)"
  echo "2. Tạo SECRET ngẫu nhiên (có thời hạn)"
  echo "3. Dọn các SECRET đã hết hạn"
  echo "4. Tạo URL Telegram Proxy"
  echo "5. Thoát"
  echo -n "Chọn thao tác (1-5): "
  read choice

  case "$choice" in
    1)
      secret=$(generate_secret)
      add_secret "$secret"
      echo -e "→ SECRET: ${GREEN}$secret${NC}"
      ;;
    2)
      secret=$(generate_secret)
      echo -n "Nhập thời hạn (phút): "
      read ttl_min
      [[ "$ttl_min" =~ ^[0-9]+$ ]] || {
        echo -e "${RED}Thời hạn không hợp lệ.${NC}"
        return
      }
      add_secret "$secret" "$ttl_min"
      echo -e "→ SECRET: ${GREEN}$secret${NC}"
      ;;
    3)
      clean_expired
      ;;
    4)
      generate_url
      ;;
    5)
      echo "Thoát."
      exit 0
      ;;
    *)
      echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
      ;;
  esac

  echo
  read -p "Nhấn Enter để quay lại menu..."
  main_menu
}

# ==== Khởi động menu ====
main_menu
