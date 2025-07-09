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
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common python3 python3-pip sqlite3 nginx

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
sudo apt-get install -y certbot python3-certbot-nginx
certbot --version || { echo "Cài đặt Certbot thất bại"; exit 1; }

echo "=== Cài đặt thư viện Python ==="
sudo pip3 install python-dateutil

echo "=== Kiểm tra DNS cho maxproxy.maxprovpn.com ==="
if ! dig +short maxproxy.maxprovpn.com; then
  echo "DNS cho maxproxy.maxprovpn.com không giải quyết được! Vui lòng kiểm tra cấu hình DNS."
  exit 1
fi

echo "=== Kiểm tra và giải phóng cổng 80, 443, và 8444 ==="
if ss -tuln | grep -E ':80|:443|:8444'; then
  echo "Cổng 80, 443 hoặc 8444 đang được sử dụng!"
  echo "Xác định tiến trình chiếm cổng..."
  sudo lsof -i :80 -i :443 -i :8444
  echo "Dừng các dịch vụ liên quan (nếu có)..."
  sudo systemctl stop nginx apache2 || true
  sudo kill -9 $(lsof -t -i:80 -i:443 -i:8444) 2>/dev/null || true
  if ss -tuln | grep -E ':80|:443|:8444'; then
    echo "Không thể giải phóng cổng 80, 443 hoặc 8444. Vui lòng kiểm tra và thử lại."
    exit 1
  fi
fi

echo "=== Kiểm tra chứng chỉ SSL hiện có cho maxproxy.maxprovpn.com ==="
if sudo openssl x509 -in /etc/letsencrypt/live/maxproxy.maxprovpn.com/fullchain.pem -text -noout >/dev/null 2>&1; then
  echo "Chứng chỉ SSL hiện có hợp lệ, bỏ qua bước tạo mới."
else
  echo "=== Tạo chứng chỉ SSL cho maxproxy.maxprovpn.com ==="
  sudo certbot certonly --standalone -d maxproxy.maxprovpn.com --non-interactive --agree-tos --email admin@maxprovpn.com || {
    echo "Tạo chứng chỉ SSL thất bại. Vui lòng kiểm tra log /var/log/letsencrypt/letsencrypt.log."
    exit 1
  }
fi

echo "=== Tạo thư mục làm việc ==="
mkdir -p telegram-proxy/secrets
cd telegram-proxy

echo "=== Kiểm tra container mtproto-proxy ==="
if docker ps -a | grep -q mtproto-proxy; then
  echo "Container mtproto-proxy đã tồn tại. Dừng và xóa container cũ..."
  sudo docker-compose down
  sudo docker volume rm telegram-proxy_proxy-config || true
fi

echo "=== Tạo cơ sở dữ liệu SQLite để quản lý thiết bị ==="
sqlite3 devices.db <<EOF
CREATE TABLE IF NOT EXISTS devices (
  secret TEXT,
  device_ip TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (secret, device_ip)
);
EOF

echo "=== Tạo file Python để quản lý thiết bị và secret ==="
cat > manage_devices.py <<EOF
import sqlite3
import sys
import os
from datetime import datetime

def connect_db():
    return sqlite3.connect('devices.db')

def add_device(secret, device_ip):
    conn = connect_db()
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM devices WHERE secret = ? AND created_at > datetime('now', '-1 hour')", (secret,))
    count = cursor.fetchone()[0]
    if count >= 4:
        print(f"Secret {secret} đã đạt giới hạn 4 thiết bị. Vô hiệu hóa secret...")
        os.system("docker exec mtproto-proxy cat /data/secret > secrets.txt")
        with open("secrets.txt", "r") as f:
            secrets = f.readlines()
        secrets = [s.strip() for s in secrets if s.strip() != secret]
        with open("secrets.txt", "w") as f:
            f.write("\n".join(secrets) + "\n")
        os.system("docker cp secrets.txt mtproto-proxy:/data/secret")
        os.system("docker-compose restart")
        conn.close()
        return False
    cursor.execute("INSERT OR REPLACE INTO devices (secret, device_ip, created_at) VALUES (?, ?, ?)",
                   (secret, device_ip, datetime.now()))
    conn.commit()
    conn.close()
    return True

def list_devices():
    conn = connect_db()
    cursor = conn.cursor()
    cursor.execute("SELECT secret, device_ip, created_at FROM devices")
    rows = cursor.fetchall()
    for row in rows:
        print(f"Secret: {row[0]}, Device IP: {row[1]}, Connected: {row[2]}")
    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 manage_devices.py [add|list] [secret] [device_ip]")
        sys.exit(1)
    action = sys.argv[1]
    if action == "add" and len(sys.argv) == 4:
        if add_device(sys.argv[2], sys.argv[3]):
            print(f"Thiết bị {sys.argv[3]} được thêm cho secret {sys.argv[2]}")
        else:
            print(f"Không thể thêm thiết bị cho secret {sys.argv[2]}")
    elif action == "list":
        list_devices()
    else:
        print("Invalid action or arguments")
        sys.exit(1)
EOF

echo "=== Tạo file Python để phân tích access log NGINX ==="
cat > parse_nginx_log.py <<EOF
import re
import os
import sqlite3
from datetime import datetime

def connect_db():
    return sqlite3.connect('devices.db')

def parse_log():
    log_file = "/var/log/nginx/proxy_access.log"
    if not os.path.exists(log_file):
        print(f"Log file {log_file} not found!")
        return
    with open(log_file, "r") as f:
        for line in f:
            match = re.search(r'(\d+\.\d+\.\d+\.\d+)\s+-\s+-\s+\[[^\]]+\]\s+"[^"]+\?secret=(\S+)"', line)
            if match:
                ip = match.group(1)
                secret = match.group(2)
                conn = connect_db()
                cursor = conn.cursor()
                cursor.execute("INSERT OR REPLACE INTO devices (secret, device_ip, created_at) VALUES (?, ?, ?)",
                               (secret, ip, datetime.now()))
                conn.commit()
                cursor.execute("SELECT COUNT(*) FROM devices WHERE secret = ? AND created_at > datetime('now', '-1 hour')", (secret,))
                count = cursor.fetchone()[0]
                if count > 4:
                    print(f"Secret {secret} vượt quá 4 thiết bị. Vô hiệu hóa...")
                    os.system("docker exec mtproto-proxy cat /data/secret > secrets.txt")
                    with open("secrets.txt", "r") as f:
                        secrets = f.readlines()
                    secrets = [s.strip() for s in secrets if s.strip() != secret]
                    with open("secrets.txt", "w") as f:
                        f.write("\n".join(secrets) + "\n")
                    os.system("docker cp secrets.txt mtproto-proxy:/data/secret")
                    os.system("docker-compose restart")
                conn.close()
            else:
                with open("parse_log_errors.txt", "a") as f:
                    f.write(f"Dòng log không khớp định dạng: {line.strip()}\n")

if __name__ == "__main__":
    parse_log()
EOF

echo "=== Tạo file cấu hình NGINX ==="
sudo mkdir -p /etc/nginx/sites-available
sudo bash -c 'cat > /etc/nginx/sites-available/telegram-proxy.conf' <<EOF
server {
    listen 8444 ssl;
    server_name maxproxy.maxprovpn.com;

    ssl_certificate /etc/letsencrypt/live/maxproxy.maxprovpn.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/maxproxy.maxprovpn.com/privkey.pem;

    access_log /var/log/nginx/proxy_access.log main;

    location / {
        proxy_pass https://127.0.0.1:443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

echo "=== Kích hoạt cấu hình NGINX ==="
sudo ln -sf /etc/nginx/sites-available/telegram-proxy.conf /etc/nginx/sites-enabled/
sudo nginx -t || { echo "Cấu hình NGINX không hợp lệ"; exit 1; }
sudo systemctl restart nginx
sudo systemctl enable nginx

echo "=== Tạo file docker-compose.yml với 1 container ==="
cat > docker-compose.yml <<EOF
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: mtproto-proxy
    ports:
      - "127.0.0.1:443:443"
    environment:
      - SECRET_COUNT=16
      - WORKERS=4
      - TLS_DOMAIN=maxproxy.maxprovpn.com
      - VERBOSITY=2
    volumes:
      - proxy-config:/data
      - /etc/letsencrypt/live/maxproxy.maxprovpn.com/fullchain.pem:/etc/ssl/certs/fullchain.pem:ro
      - /etc/letsencrypt/live/maxproxy.maxprovpn.com/privkey.pem:/etc/ssl/private/privkey.pem:ro
    restart: always
volumes:
  proxy-config:
EOF

echo "=== Kiểm tra file docker-compose.yml ==="
docker-compose config || { echo "File YAML không hợp lệ"; exit 1; }

echo "=== Khởi chạy container MTProto Proxy ==="
sudo docker-compose up -d
sleep 15
if ! docker inspect mtproto-proxy | grep -q '"Status": "running"'; then
  echo "Container mtproto-proxy không chạy. Kiểm tra log:"
  docker logs mtproto-proxy
  exit 1
fi

echo "=== Lấy danh sách secret từ logs ==="
echo "Secrets từ mtproto-proxy:" | tee secrets/secret_list.txt
sudo docker logs mtproto-proxy | grep -i secret | tee -a secrets/secret_list.txt

echo "=== Cập nhật link proxy sang cổng 8444 và domain maxproxy.maxprovpn.com ==="
sed -i 's/proxy.maxprovpn.com/maxproxy.maxprovpn.com/' secrets/secret_list.txt
sed -i 's/port=443/port=8444/' secrets/secret_list.txt
echo "Danh sách secret đã được cập nhật với cổng 8444 và domain maxproxy.maxprovpn.com:"
cat secrets/secret_list.txt

echo "=== Kiểm tra kết nối tới proxy qua NGINX (cổng 8444) ==="
if nc -zv maxproxy.maxprovpn.com 8444 >/dev/null 2>&1; then
  echo "Kết nối tới maxproxy.maxprovpn.com:8444 thành công!"
else
  echo "Không thể kết nối tới maxproxy.maxprovpn.com:8444. Vui lòng kiểm tra firewall hoặc cấu hình DNS."
  exit 1
fi

echo "=== Tạo file log rỗng ==="
sudo touch /var/log/nginx/proxy_access.log parse_log_errors.txt
sudo chmod 666 /var/log/nginx/proxy_access.log parse_log_errors.txt

echo "=== Cấu hình tự động gia hạn chứng chỉ SSL ==="
sudo bash -c 'echo "0 0,12 * * * root certbot renew --quiet && systemctl restart nginx && cd $(pwd) && docker-compose restart" >> /etc/crontab'

echo "=== Cấu hình tự động phân tích access log NGINX (mỗi 5 phút) ==="
sudo bash -c "echo '*/5 * * * * root cd $(pwd) && python3 parse_nginx_log.py >> $(pwd)/parse_log_errors.txt 2>&1' >> /etc/crontab"

echo "=== Khởi động lại cron để áp dụng thay đổi ==="
sudo systemctl restart cron

echo "=== Hướng dẫn quản lý secret và giới hạn thiết bị ==="
echo "1. Xóa secret cụ thể:"
echo "   a. Sao chép file secret ra ngoài:"
echo "      docker exec mtproto-proxy cat /data/secret > secrets.txt"
echo "   b. Mở secrets.txt và xóa dòng chứa secret cần chặn (ví dụ: cde5c8e17af1c5ce2db2d4347b6a9cdc)."
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
echo "   b. Thêm secret mới (chuỗi hex 32 ký tự, ví dụ: dd\$(openssl rand -hex 16))."
echo "      Đảm bảo tổng số secret không vượt quá SECRET_COUNT=16."
echo "   c. Sao chép file vào container:"
echo "      docker cp secrets.txt mtproto-proxy:/data/secret"
echo "   d. Khởi động lại container:"
echo "      cd telegram-proxy"
echo "      sudo docker-compose restart"
echo "   Lưu ý: Nếu thêm secret thất bại, chuyển sang Phương pháp 3."
echo ""
echo "3. Giới hạn thiết bị (tối đa 4 thiết bị mỗi secret):"
echo "   a. Script parse_nginx_log.py chạy mỗi 5 phút để cập nhật thiết bị vào devices.db từ access log NGINX."
echo "   b. Nếu secret vượt quá 4 thiết bị, nó sẽ bị xóa khỏi /data/secret."
echo "   c. Xem danh sách thiết bị:"
echo "      python3 manage_devices.py list"
echo "   d. Thêm thiết bị thủ công (nếu cần kiểm tra):"
echo "      python3 manage_devices.py add <secret> <device_ip>"
echo "      Ví dụ: python3 manage_devices.py add cde5c8e17af1c5ce2db2d4347b6a9cdc 192.168.1.1"
echo ""
echo "4. Xóa tất cả secret và tạo mới (dự phòng):"
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

echo "=== Hướng dẫn kiểm tra lỗi log thiết bị ==="
echo "1. Kiểm tra dịch vụ cron:"
echo "   sudo systemctl status cron"
echo "2. Kiểm tra access log NGINX:"
echo "   cat /var/log/nginx/proxy_access.log"
echo "3. Chạy script phân tích thủ công:"
echo "   cd telegram-proxy"
echo "   python3 parse_nginx_log.py"
echo "4. Kiểm tra danh sách thiết bị:"
echo "   python3 manage_devices.py list"
echo "5. Kiểm tra lỗi script phân tích:"
echo "   cat telegram-proxy/parse_log_errors.txt"
echo "6. Kiểm tra container:"
echo "   docker ps -a"
echo "   docker logs mtproto-proxy"
echo "7. Kiểm tra NGINX:"
echo "   sudo systemctl status nginx"
echo "   sudo nginx -t"
