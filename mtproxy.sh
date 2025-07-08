#!/bin/bash

set -e

# Kiểm tra hệ điều hành
if [ "$(lsb_release -si)" != "Ubuntu" ]; then
  echo "Script chỉ hỗ trợ Ubuntu!"
  exit 1
fi

echo "=== Cập nhật hệ thống ==="
sudo apt-get update || { echo "Cập nhật thất bại"; exit 1; }
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

echo "=== Thêm kho lưu trữ Docker ==="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

echo "=== Cài đặt Docker ==="
sudo apt-get update
sudo apt-get install -y docker-ce
docker --version || { echo "Cài đặt Docker thất bại"; exit 1; }
sudo systemctl enable docker
sudo systemctl start docker

echo "=== Cài đặt Docker Compose ==="
LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
sudo curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version || { echo "Cài đặt Docker Compose thất bại"; exit 1; }

echo "=== Cài đặt Certbot để lấy chứng chỉ SSL ==="
sudo apt-get install -y certbot
certbot --version || { echo "Cài đặt Certbot thất bại"; exit 1; }

echo "=== Kiểm tra cổng 80, 443, 8443, 9443 ==="
if ss -tuln | grep -E ':80|:443|:8443|:9443'; then
  echo "Một trong các cổng 80, 443, 8443, hoặc 9443 đang được sử dụng! Vui lòng kiểm tra và giải phóng cổng."
  exit 1
fi

echo "=== Tạo chứng chỉ SSL cho proxy.maxprovpn.com ==="
sudo certbot certonly --standalone -d proxy.maxprovpn.com --non-interactive --agree-tos --email admin@maxprovpn.com || { echo "Tạo chứng chỉ SSL thất bại"; exit 1; }

echo "=== Tạo thư mục làm việc ==="
mkdir -p telegram-proxy
cd telegram-proxy

echo "=== Tạo file docker-compose.yml với 3 container ==="
cat > docker-compose.yml <<EOF
version: '3'
services:
  mtproto-proxy-1:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy-1
    ports:
      - "443:443"
    environment:
      - SECRET_COUNT=16
      - WORKERS=16
      - TLS_DOMAIN=proxy.maxprovpn.com
    volumes:
      - proxy-config-1:/data
      - /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/proxy.maxprovpn.com/privkey.pem:/etc/ssl/private/privkey.pem:ro
    restart: always
  mtproto-proxy-2:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy-2
    ports:
      - "8443:443"
    environment:
      - SECRET_COUNT=16
      - WORKERS=16
      - TLS_DOMAIN=proxy.maxprovpn.com
    volumes:
      - proxy-config-2:/data
      - /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/proxy.maxprovpn.com/privkey.pem:/etc/ssl/private/privkey.pem:ro
    restart: always
  mtproto-proxy-3:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy-3
    ports:
      - "9443:443"
    environment:
      - SECRET_COUNT=16
      - WORKERS=16
      - TLS_DOMAIN=proxy.maxprovpn.com
    volumes:
      - proxy-config-3:/data
      - /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/proxy.maxprovpn.com/privkey.pem:/etc/ssl/private/privkey.pem:ro
    restart: always
volumes:
  proxy-config-1:
  proxy-config-2:
  proxy-config-3:
EOF

echo "=== Kiểm tra file docker-compose.yml ==="
docker-compose config || { echo "File YAML không hợp lệ"; exit 1; }

echo "=== Khởi chạy các container MTProto Proxy ==="
sudo docker-compose up -d
sleep 15
for container in mtproto-proxy-1 mtproto-proxy-2 mtproto-proxy-3; do
  docker inspect $container | grep -q '"Status": "running"' || { echo "Container $container không chạy"; exit 1; }
done

echo "=== Lấy danh sách secret từ logs của tất cả container ==="
mkdir -p secrets
for container in mtproto-proxy-1 mtproto-proxy-2 mtproto-proxy-3; do
  echo "Secrets từ $container:" | tee -a secrets/secret_list.txt
  sudo docker logs $container | grep -i secret | tee -a secrets/secret_list.txt
  echo "----------------------------------------" | tee -a secrets/secret_list.txt
done

echo "=== Danh sách secret đã được lưu vào telegram-proxy/secrets/secret_list.txt ==="
cat secrets/secret_list.txt

echo "=== Cấu hình tự động gia hạn chứng chỉ SSL ==="
sudo bash -c 'echo "0 0,12 * * * root certbot renew --quiet && cd $(pwd) && docker-compose restart" >> /etc/crontab'
