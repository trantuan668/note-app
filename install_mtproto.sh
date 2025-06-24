#!/bin/bash

set -e  # Dừng nếu có lỗi

# Cài gói cần thiết
apt update && apt install -y git curl build-essential libssl-dev zlib1g-dev python3 python3-pip

# Cài Flask để chạy dashboard
pip3 install flask --break-system-packages

# Tạo user riêng cho MTProxy
useradd -r -s /bin/false mtproxy || true

# Biến cấu hình
INSTALL_DIR="/opt/mtproxy"
PROXY_PORT=8888
HTTP_PORT=443
SECRET_HEX=$(head -c 16 /dev/urandom | xxd -ps)
TAG="ee$SECRET_HEX"

# Clone và build
cd /opt
git clone https://github.com/TelegramMessenger/MTProxy mtproxy
cd mtproxy
make

# Tải cấu hình Telegram
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf

# Lưu secret
echo $SECRET_HEX > "$INSTALL_DIR/secret.key"

# File log IP
mkdir -p /opt/mtproxy/logs
touch /opt/mtproxy/logs/connections.json
chmod 666 /opt/mtproxy/logs/connections.json

# Tạo systemd service
cat <<EOF >/etc/systemd/system/mtproxy.service
[Unit]
Description=MTProto Proxy Telegram
After=network.target

[Service]
User=mtproxy
Type=simple
ExecStart=$INSTALL_DIR/objs/bin/mtproto-proxy \\
  -u mtproxy \\
  -p $PROXY_PORT \\
  -H $HTTP_PORT \\
  -S $SECRET_HEX \\
  --aes-pwd $INSTALL_DIR/proxy-secret $INSTALL_DIR/proxy-multi.conf \\
  -M 1 \\
  >> /var/log/mtproxy.log 2>&1
Restart=on-failure
LimitNOFILE=51200
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Tạo script theo dõi IP bằng ss
cat <<'EOF' > /opt/mtproxy/log_ip.sh
#!/bin/bash
OUTPUT="/opt/mtproxy/logs/connections.json"
ss -tn state established '( sport = :8888 or sport = :443 )' | \
awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq | \
jq -R -s -c 'split("\n")[:-1] | map({ip: ., time: now | todate})' > "$OUTPUT"
EOF

chmod +x /opt/mtproxy/log_ip.sh

# Tạo cron job chạy mỗi phút
echo "* * * * * root /opt/mtproxy/log_ip.sh" > /etc/cron.d/mtproxy-log

# Reload và start dịch vụ
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mtproxy
systemctl start mtproxy

# Mở port nếu có ufw
if command -v ufw >/dev/null; then
    ufw allow $PROXY_PORT/tcp
    ufw allow $HTTP_PORT/tcp
fi

# In link kết nối
IP=$(curl -s ifconfig.me)
echo ""
echo "✅ MTProto Proxy đã được cài đặt và khởi chạy!"
echo "📶 Sẵn sàng hỗ trợ gọi thoại Telegram."
echo "📎 Link kết nối Telegram:"
echo "tg://proxy?server=$IP&port=$HTTP_PORT&secret=$TAG"
echo ""
echo "🌐 Hoặc chia sẻ dạng web:"
echo "https://t.me/proxy?server=$IP&port=$HTTP_PORT&secret=$TAG"
echo "📊 Dashboard: http://$IP:5000"
echo ""
