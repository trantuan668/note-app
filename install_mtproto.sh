#!/bin/bash
# Cài MTProto Proxy Telegram tự động

set -e

# === Cấu hình ===
PORT=8443
WORKDIR="/opt/mtproxy"
SECRET_HEX=$(openssl rand -hex 16) # Sinh SECRET ngẫu nhiên
USER="mtproxy"

echo "=== 🔧 Bắt đầu cài đặt MTProto Proxy ==="

# Tạo user nếu chưa có
id -u $USER &>/dev/null || useradd -r -s /bin/false $USER

# Cài gói cần thiết
apt update && apt install -y git build-essential curl

# Clone source
rm -rf "$WORKDIR"
git clone https://github.com/TelegramMessenger/MTProxy "$WORKDIR"
cd "$WORKDIR"

# Build
make

# Tạo file secret và config
echo -n "$SECRET_HEX" > "$WORKDIR/proxy-secret"
echo -e "dd$SECRET_HEX" > "$WORKDIR/proxy-multi.conf"

# Tạo systemd service
cat <<EOF > /etc/systemd/system/mtproxy.service
[Unit]
Description=MTProto Proxy Telegram
After=network.target

[Service]
ExecStart=$WORKDIR/objs/bin/mtproto-proxy \\
    -u $USER \\
    -p 8888 \\
    -H $PORT \\
    -S $SECRET_HEX \\
    --aes-pwd $WORKDIR/proxy-secret $WORKDIR/proxy-multi.conf \\
    -M 1 \\
    --log-file /var/log/mtproxy_access.log
User=$USER
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Phân quyền
chown -R $USER:$USER "$WORKDIR"
chmod +x "$WORKDIR/objs/bin/mtproto-proxy"

# Reload systemd và khởi động
systemctl daemon-reload
systemctl enable --now mtproxy

# Hiển thị link kết nối
IP=$(curl -s ifconfig.me)
LINK="tg://proxy?server=$IP&port=$PORT&secret=ee$SECRET_HEX"
echo ""
echo "✅ Cài đặt hoàn tất!"
echo "🔗 Link Telegram Proxy: $LINK"
