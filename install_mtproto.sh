#!/bin/bash

set -e

echo "[+] Cập nhật hệ thống..."
sudo apt update && sudo apt upgrade -y

echo "[+] Cài đặt Docker và Docker Compose..."
sudo apt install -y docker.io docker-compose

echo "[+] Khởi động Docker..."
sudo systemctl start docker
sudo systemctl enable docker

echo "[+] Tạo thư mục và tệp docker-compose..."
mkdir -p telegram-proxy && cd telegram-proxy

cat > docker-compose.yml <<EOF
version: '3'
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    ports:
      - "443:443"
    environment:
      - SECRET_COUNT=10
      - WORKERS=16
    volumes:
      - mtproxy:/data
    restart: always
volumes:
  mtproxy:
EOF

echo "[+] Khởi động MTProto Proxy..."
sudo docker-compose up -d

echo "[+] Đang lấy log từ container..."
sudo docker logs mtproto-proxy
