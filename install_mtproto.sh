#!/bin/bash

# Cấu hình
WORKDIR="mtproxy"
PORT=443
SECRET="dd$(openssl rand -hex 16)"
IP=$(curl -s https://api.ipify.org)

# Tạo thư mục và file docker-compose.yml
mkdir -p $WORKDIR
cd $WORKDIR

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
docker compose up -d

# In link Telegram proxy
echo -e "\n✅ MTProxy đã chạy thành công!"
echo -e "🔒 SECRET: ${SECRET}"
echo -e "🌐 Proxy link: tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
echo -e "📱 Hoặc dùng link web: https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
