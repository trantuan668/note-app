#!/bin/bash

set -e

# ======= MÀU & LOG =========
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
RESET="\033[0m"

log() {
  echo -e "${GREEN}[+]${RESET} $1"
}

warn() {
  echo -e "${YELLOW}[!]${RESET} $1"
}

error() {
  echo -e "${RED}[-]${RESET} $1"
}

# ======= HỎI PORT ==========
read -p "Nhập port bạn muốn dùng cho MTProxy (mặc định: 443): " PORT
PORT=${PORT:-443}

# ======= KIỂM TRA DOCKER ==========
if ! command -v docker &> /dev/null; then
  warn "Docker chưa được cài. Đang tiến hành cài đặt..."
  curl -fsSL https://get.docker.com | bash
else
  log "Docker đã được cài."
fi

# ======= KIỂM TRA DOCKER COMPOSE ==========
if ! docker compose version &> /dev/null; then
  warn "Docker Compose plugin chưa được cài. Đang cài đặt..."
  sudo apt update
  sudo apt install docker-compose-plugin -y
else
  log "Docker Compose plugin đã được cài."
fi

# ======= THIẾT LẬP ==========
WORKDIR="mtproxy"
SECRET="dd$(openssl rand -hex 16)"
IP=$(curl -s https://api.ipify.org)

log "Tạo thư mục và file cấu hình..."
mkdir -p $WORKDIR
cd $WORKDIR

# Ghi docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3'
services:
  mtproxy:
    image: telegrammessenger/proxy
    container_name: mtproxy
    ports:
      - "${PORT}:443"
    environment:
      - SECRET=${SECRET}
    restart: always
EOF

# Khởi động container
log "Khởi động MTProxy trên port ${PORT}..."
docker compose up -d

# ======= HIỂN THỊ KẾT QUẢ ==========
echo -e "\n${GREEN}✅ MTProxy đã chạy thành công!${RESET}"
echo -e "🔒 SECRET: ${SECRET}"
echo -e "🌐 Proxy link: tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
echo -e "📱 Mở nhanh Telegram: https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
