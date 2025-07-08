#!/bin/bash

set -e

DOMAIN="proxy.maxprovpn.com"
EMAIL="admin@maxprovpn.com" # Thay bằng email thật để nhận cảnh báo SSL
MTPORT="8443"         # MTProxy sẽ chạy nội bộ cổng này (ẩn sau NGINX)

echo "=== Cập nhật hệ thống và cài đặt phụ thuộc ==="
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2 ufw nginx certbot python3-certbot-nginx

echo "=== Cài Docker và Docker Compose ==="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo systemctl enable docker
sudo systemctl start docker

echo "=== Mở firewall cho HTTP/HTTPS ==="
sudo ufw allow 'Nginx Full'

echo "=== Tạo thư mục và file docker-compose cho MTProxy ==="
mkdir -p ~/telegram-proxy
cd ~/telegram-proxy

cat > docker-compose.yml <<EOF
version: '3'
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    ports:
      - "${MTPORT}:${MTPORT}"
    environment:
      - PORT=${MTPORT}
      - SECRET_COUNT=10
      - WORKERS=16
      - TAG=${DOMAIN}
    volumes:
      - proxy-config:/data
    restart: always
volumes:
  proxy-config:
EOF

echo "=== Khởi động MTProxy ở cổng $MTPORT ==="
sudo docker-compose up -d

echo "=== Cấu hình NGINX reverse proxy cho $DOMAIN ==="
sudo tee /etc/nginx/sites-available/mtproxy <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$MTPORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/mtproxy /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "=== Cấp SSL với Let's Encrypt cho $DOMAIN ==="
sudo certbot --nginx --non-interactive --agree-tos --redirect -d $DOMAIN -m $EMAIL

echo "=== Cấu hình hoàn tất ==="
echo "🔒 MTProxy đang chạy tại: https://$DOMAIN"
echo "⏳ Đợi 5 giây để hiển thị danh sách secret..."
sleep 5
sudo docker logs mtproto-proxy
