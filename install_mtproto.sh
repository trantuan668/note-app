#!/bin/bash

set -e

# Kiểm tra hệ điều hành
if [ "$(lsb_release -si)" != "Ubuntu" ]; then
  echo "Script chỉ hỗ trợ Ubuntu!"
  exit 1
fi

# Kiểm tra tài nguyên RAM
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 900 ]; then
  echo "Cảnh báo: RAM dưới 1GB. Hệ thống có thể không ổn định khi chạy proxy."
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

echo "=== Kiểm tra DNS cho proxy.maxprovpn.com ==="
if ! dig +short proxy.maxprovpn.com; then
  echo "DNS cho proxy.maxprovpn.com không giải quyết được! Vui lòng kiểm tra cấu hình DNS."
  exit 1
fi

echo "=== Kiểm tra cổng 80 và 443 ==="
if ss -tuln | grep -E ':80|:443'; then
  echo "Cổng 80 hoặc 443 đang được sử dụng! Vui lòng kiểm tra và giải phóng cổng."
  exit 1
fi

echo "=== Tạo chứng chỉ SSL cho proxy.maxprovpn.com ==="
sudo certbot certonly --standalone -d proxy.maxprovpn.com --non-interactive --agree-tos --email admin@maxprovpn.com || { echo "Tạo chứng chỉ SSL thất bại"; exit 1; }

echo "=== Kiểm tra chứng chỉ SSL ==="
if ! sudo openssl x509 -in /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem -text -noout >/dev/null 2>&1; then
  echo "Chứng chỉ SSL không hợp lệ!"
  exit 1
fi

echo "=== Tạo thư mục làm việc ==="
mkdir -p telegram-proxy/secrets
cd telegram-proxy

echo "=== Tạo file docker-compose.yml với 1 container ==="
cat > docker-compose.yml <<EOF
version: '3'
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    ports:
      - "443:443"
    environment:
      - SECRET_COUNT=16
      - WORKERS=4
      - TLS_DOMAIN=proxy.maxprovpn.com
    volumes:
      - proxy-config:/data
      - /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/proxy.maxprovpn.com/privkey.pem:/etc/ssl/private/privkey.pem:ro
    restart: always
volumes:
  proxy-config:
EOF

echo "=== Kiểm tra file docker-compose.yml ==="
docker-compose config || { echo "File YAML không hợp lệ"; exit 1; }

echo "=== Khởi chạy container MTProto Proxy ==="
sudo docker-compose up -d
sleep 15
docker inspect mtproto-proxy | grep -q '"Status": "running"' || { echo "Container mtproto-proxy không chạy"; exit 1; }

echo "=== Lấy danh sách secret từ logs ==="
echo "Secrets từ mtproto-proxy:" | tee secrets/secret_list.txt
sudo docker logs mtproto-proxy | grep -i secret | tee -a secrets/secret_list.txt

echo "=== Danh sách secret đã được lưu vào telegram-proxy/secrets/secret_list.txt ==="
cat secrets/secret_list.txt

echo "=== Kiểm tra kết nối tới proxy ==="
if nc -zv proxy.maxprovpn.com 443 >/dev/null 2>&1; then
  echo "Kết nối tới proxy.maxprovpn.com:443 thành công!"
else
  echo "Không thể kết nối tới proxy.maxprovpn.com:443. Vui lòng kiểm tra firewall hoặc cấu hình mạng."
  exit 1
fi

echo "=== Cấu hình tự động gia hạn chứng chỉ SSL ==="
sudo bash -c 'echo "0 0,12 * * * root certbot renew --quiet && cd $(pwd) && docker-compose restart" >> /etc/crontab'

echo "=== Hướng dẫn quản lý secret ==="
echo "1. Xóa secret cụ thể:"
echo "   a. Sao chép file secret ra ngoài:"
echo "      docker exec mtproto-proxy cat /data/secret > secrets.txt"
echo "   b. Mở secrets.txt và xóa dòng chứa secret cần chặn (ví dụ: dd123...)."
echo "      nano secrets.txt"
echo "   c. Sao chép file đã chỉnh sửa vào container:"
echo "      docker cp secrets.txt mtproto-proxy:/data/secret"
echo "   d. Khởi động lại container:"
echo "      cd telegram-proxy"
echo "      sudo docker-compose restart"
echo "   Lưu ý: Xác minh file /data/secret tồn tại (docker exec mtproto-proxy cat /data/secret)."
echo ""
echo "2. Thêm secret mới thủ công:"
echo "   a. Mở secrets.txt (hoặc tạo mới nếu chưa có):"
echo "      nano secrets.txt"
echo "   b. Thêm secret mới (chuỗi hex 32 ký tự, ví dụ: dd$(openssl rand -hex 16))."
echo "      Đảm bảo tổng số secret không vượt quá SECRET_COUNT=16."
echo "   c. Sao chép file vào container:"
echo "      docker cp secrets.txt mtproto-proxy:/data/secret"
echo "   d. Khởi động lại container:"
echo "      cd telegram-proxy"
echo "      sudo docker-compose restart"
echo "   Lưu ý: Nếu thêm secret thất bại, chuyển sang Phương pháp 3."
echo ""
echo "3. Xóa tất cả secret và tạo mới (dự phòng):"
echo "   a. Dừng và xóa container:"
echo "      cd telegram-proxy"
echo "      sudo docker-compose down"
echo "   b. Xóa volume:"
echo "      sudo docker volume rm telegram-proxy_proxy-config"
echo "   c. Tái tạo container:"
echo "      sudo docker-compose up -d"
echo "   d. Xem secret mới:"
echo "      cat secrets/secret_list.txt"
echo "   Lưu ý: Các secret cũ sẽ không còn hợp lệ."

echo "=== Hướng dẫn sử dụng proxy ==="
echo "1. Mở Telegram, vào Settings > Data and Storage > Proxy Settings."
echo "2. Thêm proxy với các thông số:"
echo "   - Server: proxy.maxprovpn.com"
echo "   - Port: 443"
echo "   - Secret: Lấy từ telegram-proxy/secrets/secret_list.txt"
echo "3. Nếu không kết nối được, thử mạng khác hoặc kiểm tra log container (sudo docker logs mtproto-proxy)."
