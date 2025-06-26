#!/bin/bash

# ==== Cấu hình ====
SECRET_FILE="./proxy-secret"
CONTAINER_NAME="mtproto-proxy"
EXPIRE_DB="./secret-expiry.db"
DOMAIN_OR_IP="yourdomain.com"  # ← Thay bằng domain hoặc IP server bạn

# ==== Màu sắc ====
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

# ==== Kiểm tra file ====
touch "$SECRET_FILE"
touch "$EXPIRE_DB"

# ==== Kiểm tra định dạng hợp lệ (hex 32 ký tự) ====
function validate_secret() {
  [[ "$1" =~ ^[a-fA-F0-9]{32}$ ]] || {
    echo -e "${RED}SECRET không hợp lệ (phải là 32 ký tự hex).${NC}"
    exit 1
  }
}

# ==== Hướng dẫn ====
function usage() {
  echo "Sử dụng: $0 [add|remove|list|generate|clean|url] [SECRET] [--ttl <giây>]"
  echo
  echo "  add <SECRET>         Thêm SECRET thủ công"
  echo "  remove <SECRET>      Xoá SECRET thủ công"
  echo "  list                 Hiển thị danh sách SECRET đang hoạt động"
  echo "  generate [--ttl]     Tạo SECRET ngẫu nhiên, tùy chọn thời hạn (giây)"
  echo "  clean                Xoá các SECRET đã hết hạn"
  echo "  url <SECRET>         In ra liên kết Telegram Proxy tương ứng"
  echo
  echo "Ví dụ:"
  echo "  $0 generate --ttl 3600        # Tạo SECRET hết hạn sau 1 giờ"
  echo "  $0 url abcd1234abcd1234abcd1234abcd1234"
  exit 1
}

# ==== Thêm SECRET (và lưu hạn nếu có) ====
function add_secret() {
  validate_secret "$1"
  grep -qxF "$1" "$SECRET_FILE" && {
    echo -e "${YELLOW}SECRET đã tồn tại.${NC}"
    return
  }
  echo "$1" >> "$SECRET_FILE"
  if [ -n "$TTL" ]; then
    expire_time=$(( $(date +%s) + TTL ))
    echo "$1 $expire_time" >> "$EXPIRE_DB"
    echo -e "${YELLOW}Đã thêm SECRET với hạn: $TTL giây.${NC}"
  else
    echo -e "${GREEN}Đã thêm SECRET không thời hạn.${NC}"
  fi
  restart_container
}

# ==== Xoá SECRET ====
function remove_secret() {
  validate_secret "$1"
  grep -qxF "$1" "$SECRET_FILE" || {
    echo -e "${RED}SECRET không tồn tại.${NC}"
    return
  }
  grep -vxF "$1" "$SECRET_FILE" > "$SECRET_FILE.tmp" && mv "$SECRET_FILE.tmp" "$SECRET_FILE"
  grep -v "^$1 " "$EXPIRE_DB" > "$EXPIRE_DB.tmp" && mv "$EXPIRE_DB.tmp" "$EXPIRE_DB"
  echo -e "${GREEN}Đã xoá SECRET.${NC}"
  restart_container
}

# ==== Tạo SECRET ngẫu nhiên ====
function generate_secret() {
  local new_secret
  new_secret=$(openssl rand -hex 16)
  echo -e "${YELLOW}Tạo SECRET: ${GREEN}$new_secret${NC}"
  add_secret "$new_secret"
  echo -e "${GREEN}URL: tg://proxy?server=$DOMAIN_OR_IP&port=443&secret=$new_secret${NC}"
}

# ==== Liệt kê SECRET đang hoạt động ====
function list_secret() {
  echo -e "${YELLOW}Danh sách SECRET hiện tại:${NC}"
  while read -r line; do
    secret=$line
    expire=$(grep "^$secret " "$EXPIRE_DB" | awk '{print $2}')
    if [ -n "$expire" ]; then
      now=$(date +%s)
      remain=$(( expire - now ))
      if (( remain > 0 )); then
        echo -e "$secret - còn ${remain}s"
      else
        echo -e "$secret - ${RED}HẾT HẠN${NC}"
      fi
    else
      echo -e "$secret - không thời hạn"
    fi
  done < "$SECRET_FILE"
}

# ==== Xoá các SECRET đã hết hạn ====
function clean_expired() {
  echo -e "${YELLOW}Đang xoá các SECRET hết hạn...${NC}"
  now=$(date +%s)
  while read -r secret expire; do
    if (( expire <= now )); then
      remove_secret "$secret"
    fi
  done < "$EXPIRE_DB"
}

# ==== Tạo URL proxy ====
function proxy_url() {
  validate_secret "$1"
  echo -e "tg://proxy?server=$DOMAIN_OR_IP&port=443&secret=$1"
}

# ==== Khởi động lại container ====
function restart_container() {
  echo -e "${YELLOW}Khởi động lại container: $CONTAINER_NAME...${NC}"
  docker restart "$CONTAINER_NAME" >/dev/null
  echo -e "${GREEN}Đã khởi động lại.${NC}"
}

# ==== Parse TTL flag ====
TTL=""
while [[ "$2" == "--ttl" ]]; do
  TTL="$3"
  shift 2
done

# ==== Dispatch ====
case "$1" in
  add)
    [ -z "$2" ] && usage
    add_secret "$2"
    ;;
  remove)
    [ -z "$2" ] && usage
    remove_secret "$2"
    ;;
  list)
    list_secret
    ;;
  generate)
    generate_secret
    ;;
  clean)
    clean_expired
    ;;
  url)
    [ -z "$2" ] && usage
    proxy_url "$2"
    ;;
  *)
    usage
    ;;
esac
