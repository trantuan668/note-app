#!/bin/bash

# Cài gói cần thiết
apt update && apt install -y git curl build-essential libssl-dev zlib1g-dev

# Tạo thư mục cài đặt
cd /opt
git clone https://github.com/TelegramMessenger/MTProxy mtproxy
cd mtproxy
make

# Tải file cấu hình Telegram
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf

# Sinh secret key
SECRET_HEX=$(head -c 16 /dev/urandom | xxd -ps)
PORT=443
TAG="ee$SECRET_HEX"

# Lưu key để tái sử dụng
echo $SECRET_HEX > /opt/mtproxy/secret.key

# Tạo service systemd
cat <<EOF >/etc/systemd/system/mtproxy.service
[Unit]
Description=MTProto Proxy Telegram
After=network.target

[Service]
Type=simple
ExecStart=/opt/mtproxy/objs/bin/mtproto-proxy -u nobody -p 8888 -H $PORT -S $SECRET_HEX --aes-pwd /opt/mtproxy/proxy-secret /opt/mtproxy/proxy-multi.conf -M 1
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Khởi động dịch vụ
systemctl daemon-reexec
systemctl enable mtproxy
systemctl start mtproxy

# In link proxy
IP=$(curl -s ifconfig.me)
echo ""
echo "✅ MTProto Proxy đã được cài đặt và khởi chạy!"
echo "📶 Sẵn sàng hỗ trợ gọi thoại Telegram."
echo "📎 Link kết nối:"
echo "tg://proxy?server=$IP&port=$PORT&secret=$TAG"
echo ""
echo "🌐 Hoặc chia sẻ dạng web:"
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$TAG"
