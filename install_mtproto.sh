#!/bin/bash

set -e

# 1. Cài Docker nếu chưa có
if ! command -v docker >/dev/null 2>&1; then
  echo "[+] Cài Docker..."
  curl -fsSL https://get.docker.com | bash
fi

# 2. Cài Docker Compose nếu chưa có
if ! command -v docker-compose >/dev/null 2>&1; then
  echo "[+] Cài Docker Compose..."
  apt install -y docker-compose
fi

# 3. Clone hoặc copy source (nếu cần)
echo "[+] Đảm bảo thư mục project sẵn sàng..."

# 4. Sinh secrets (mặc định 5 người dùng)
echo "[+] Tạo secret người dùng..."
chmod +x generate-secret.sh
./generate-secret.sh 5

# 5. Build & chạy container
echo "[+] Build và khởi chạy container MTProxy..."
docker-compose up -d --build

echo "[✓] Triển khai thành công!"
echo "===> Danh sách liên kết proxy:"
cat config/secrets.env | while read line; do
  key=$(echo $line | cut -d '=' -f2)
  echo "tg://proxy?server=$(curl -s ifconfig.me)&port=443&secret=ee${key}"
done
