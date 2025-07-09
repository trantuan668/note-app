#!/bin/bash

set -e

# Kiểm tra quyền sudo
if ! sudo -n true 2>/dev/null; then
  echo "Lỗi: Script yêu cầu quyền sudo. Vui lòng chạy với quyền root hoặc sudo."
  exit 1
fi

# Kiểm tra hệ điều hành
if [ "$(lsb_release -si)" != "Ubuntu" ]; then
  echo "Script chỉ hỗ trợ Ubuntu!"
  exit 1
fi

# Kiểm tra tài nguyên RAM
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [ "$TOTAL_RAM" -lt 512 ]; then
  echo "Lỗi: RAM dưới 512MB. Hệ thống không đủ tài nguyên."
  exit 1
elif [ "$TOTAL_RAM" -lt 900 ]; then
  echo "Cảnh báo: RAM dưới 1GB. Hệ thống có thể không ổn định."
fi

# Kiểm tra firewall
echo "=== Kiểm tra firewall ==="
if command -v ufw >/dev/null && sudo ufw status | grep -q "80\|443.*DENY"; then
  echo "Firewall (ufw) chặn cổng 80 hoặc 443. Chạy: sudo ufw allow 80,443"
  exit 1
elif command -v iptables >/dev/null && sudo iptables -L -n | grep -E ':80|:443' | grep -q DROP; then
  echo "Firewall (iptables) chặn cổng 80 hoặc 443. Chạy: sudo iptables -D INPUT -p tcp --dport 80 -j DROP"
  exit 1
fi

# Cập nhật hệ thống và cài đặt phụ thuộc
echo "=== Cập nhật hệ thống và cài đặt phụ thuộc ==="
sudo apt-get update || { echo "Cập nhật thất bại"; exit 1; }
sudo apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl software-properties-common dnsutils docker-ce
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Cài đặt Docker
echo "=== Kích hoạt Docker ==="
sudo systemctl enable docker
sudo systemctl start docker
docker --version || { echo "Docker không hoạt động"; exit 1; }

# Cài đặt Docker Compose
echo "=== Cài đặt Docker Compose ==="
LATEST_COMPOSE=$(curl -s --connect-timeout 5 https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
if [ -z "$LATEST_COMPOSE" ]; then
  echo "Không thể lấy phiên bản Docker Compose mới nhất. Kiểm tra kết nối mạng."
  exit 1
fi
sudo curl -L --fail "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || { echo "Tải Docker Compose thất bại"; exit 1; }
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version || { echo "Cài đặt Docker Compose thất bại"; exit 1; }

# Cài đặt Certbot
echo "=== Cài đặt Certbot ==="
sudo apt-get install -y --no-install-recommends certbot
certbot --version || { echo "Cài đặt Certbot thất bại"; exit 1; }

# Kiểm tra DNS
echo "=== Kiểm tra DNS cho proxy.maxprovpn.com ==="
if ! dig +short proxy.maxprovpn.com >/dev/null; then
  echo "DNS cho proxy.maxprovpn.com không giải quyết được! Vui lòng kiểm tra cấu hình DNS."
  exit 1
fi

# Kiểm tra cổng 80 và 443
echo "=== Kiểm tra cổng 80 và 443 ==="
if ss -tuln | grep -E ':80|:443'; then
  echo "Cổng 80 hoặc 443 đang được sử dụng! Vui lòng kiểm tra và giải phóng cổng."
  exit 1
fi

# Tạo chứng chỉ SSL
echo "=== Tạo chứng chỉ SSL cho proxy.maxprovpn.com ==="
sudo certbot certonly --standalone -d proxy.maxprovpn.com --non-interactive --agree-tos --email admin@maxprovpn.com || { echo "Tạo chứng chỉ SSL thất bại"; exit 1; }

# Kiểm tra chứng chỉ SSL
echo "=== Kiểm tra chứng chỉ SSL ==="
if ! sudo openssl x509 -in /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem -text -noout >/dev/null 2>&1; then
  echo "Chứng chỉ SSL không hợp lệ!"
  exit 1
fi

# Tạo thư mục làm việc
echo "=== Tạo thư mục làm việc ==="
sudo mkdir -p telegram-proxy/secrets
sudo chmod 700 telegram-proxy/secrets
cd telegram-proxy

# Tạo file docker-compose.yml
echo "=== Tạo file docker-compose.yml ==="
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
      - MAX_CONNECTIONS_PER_SECRET=4
    volumes:
      - proxy-config:/data
      - /etc/letsencrypt/live/proxy.maxprovpn.com/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/proxy.maxprovpn.com/privkey.pem:/etc/ssl/private/privkey.pem:ro
    restart: always
volumes:
  proxy-config:
EOF

# Sao lưu file docker-compose.yml
cp docker-compose.yml docker-compose.yml.bak

# Kiểm tra file YAML
echo "=== Kiểm tra file docker-compose ==="
docker-compose config || { echo "File YAML không hợp lệ"; exit 1; }

# Kéo image Docker
echo "=== Kéo image Docker ==="
sudo docker pull telegrammessenger/proxy:latest || { echo "Không thể kéo image telegrammessenger/proxy:latest"; exit 1; }

# Khởi chạy container
echo "=== Khởi chạy container MTProto Proxy ==="
sudo docker-compose up -d
sleep 15
docker inspect mtproto-proxy | grep -q '"Status": "running"' || { echo "Container mtproto-proxy không chạy"; exit 1; }

# Lấy danh sách secret
echo "=== Lấy danh sách secret từ logs ==="
echo "Secrets từ mtproto-proxy:" | sudo tee secrets/secret_list.txt
sudo docker logs mtproto-proxy | grep -i secret | sudo tee -a secrets/secret_list.txt
if [ ! -s secrets/secret_list.txt ]; then
  echo "Lỗi: Không tìm thấy secret trong log. Kiểm tra container."
  exit 1
fi
sudo chmod 600 secrets/secret_list.txt
sudo chown root:root secrets/secret_list.txt

echo "=== Danh sách secret đã được lưu vào telegram-proxy/secrets/secret_list.txt ==="
cat secrets/secret_list.txt

# Kiểm tra kết nối proxy
echo "=== Kiểm tra kết nối tới proxy ==="
if nc -zv proxy.maxprovpn.com 443 >/dev/null 2>&1; then
  echo "Kết nối tới proxy.maxprovpn.com:443 thành công!"
else
  echo "Không thể kết nối tới proxy.maxprovpn.com:443. Vui lòng kiểm tra firewall hoặc cấu hình mạng."
  exit 1
fi

# Cấu hình cron job gia hạn SSL
echo "=== Cấu hình tự động gia hạn chứng chỉ SSL ==="
CRON_JOB="0 0,12 * * * root certbot renew --quiet && cd $(pwd) && docker-compose restart"
if ! grep -Fx "$CRON_JOB" /etc/cron.d/mtproto-proxy >/dev/null 2>&1; then
  echo "$CRON_JOB" | sudo tee /etc/cron.d/mtproto-proxy
  sudo chmod 644 /etc/cron.d/mtproto-proxy
fi

# Lưu hướng dẫn sử dụng
echo "=== Lưu hướng dẫn sử dụng ==="
cat > README.txt <<EOF
Hướng dẫn quản lý secret:
1. Xóa secret cụ thể:
   a. Sao chép file secret: docker exec mtproto-proxy cat /data/secret > secrets.txt
   b. Mở secrets.txt và xóa dòng chứa secret cần chặn: nano secrets.txt
   c. Sao chép file vào container: docker cp secrets.txt mtproto-proxy:/data/secret
   d. Khởi động lại container: cd telegram-proxy && sudo docker-compose restart
   Lưu ý: Xác minh file /data/secret tồn tại (docker exec mtproto-proxy cat /data/secret).

2. Thêm secret mới thủ công:
   a. Mở secrets.txt: nano secrets.txt
   b. Thêm secret mới (chuỗi hex 32 ký tự, ví dụ: dd\$(openssl rand -hex 16)).
   c. Sao chép file vào container: docker cp secrets.txt mtproto-proxy:/data/secret
   d. Khởi động lại container: cd telegram-proxy && sudo docker-compose restart
   Lưu ý: Tổng số secret không vượt quá SECRET_COUNT=16.

3. Xóa tất cả secret và tạo mới:
   a. Dừng container: cd telegram-proxy && sudo docker-compose down
   b. Xóa volume: sudo docker volume rm telegram-proxy_proxy-config
   c. Tái tạo container: sudo docker-compose up -d
   d. Xem secret mới: cat secrets/secret_list.txt

Hướng dẫn sử dụng proxy:
1. Mở Telegram, vào Settings > Data and Storage > Proxy Settings.
2. Thêm proxy:
   - Server: proxy.maxprovpn.com
   - Port: 443
   - Secret: Lấy từ telegram-proxy/secrets/secret_list.txt
3. Lưu ý: Mỗi secret chỉ cho phép tối đa 4 thiết bị kết nối đồng thời.
4. Nếu không kết nối được, kiểm tra log: sudo docker logs mtproto-proxy
EOF
sudo chmod 644 README.txt
echo "Hướng dẫn đã được lưu vào telegram-proxy/README.txt"
