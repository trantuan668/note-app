#!/bin/bash

set -e

DOMAIN="proxy.maxprovpn.com"

echo "=== Cập nhật hệ thống ==="
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

echo "=== Thêm kho lưu trữ Docker ==="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

echo "=== Cài đặt Docker ==="
sudo apt-get update
sudo apt-get install -y docker-ce

echo "=== Kích hoạt và khởi động Docker ==="
sudo systemctl enable docker
sudo systemctl start docker

echo "=== Cài đặt Docker Compose ==="
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "=== Tạo thư mục làm việc ==="
mkdir -p telegram-proxy
cd telegram-proxy

echo "=== Tạo file docker-compose.yml với domain $DOMAIN ==="
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
      - TAG=$DOMAIN
    volumes:
      - proxy-config:/data
    restart: always
volumes:
  proxy-config:
EOF

echo "=== Khởi chạy MTProxy ==="
sudo docker-compose up -d

echo "=== Lấy danh sách secret từ logs ==="
sleep 5
sudo docker logs mtproto-proxy
