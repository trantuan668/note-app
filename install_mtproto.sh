#!/bin/bash

# --- Thông số ---
PORT=8443
WORK_DIR="/opt/mtproxy"
USER=mtproxy
SECRET_HEX=$(head -c 16 /dev/urandom | xxd -ps)
TAG="ee${SECRET_HEX}"

# --- Cài đặt gói cần thiết ---
apt update && apt install -y git curl build-essential libssl-dev zlib1g-dev

# --- Tạo user riêng nếu chưa có ---
id -u $USER &>/dev/null || useradd -r -s /usr/sbin/nologin $USER

# --- Tải mã nguồn MTProxy ---
rm -rf $WORK_DIR
git clone https://github.com/TelegramMessenger/MTProxy $WORK_DIR
cd $WORK_DIR && make

# --- Tải file cấu hình Telegram ---
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf

# --- Lưu secret để tái sử dụng ---
echo "$SECRET_HEX" > $WORK_DIR/secret.key

# --- Phân quyền ---
chown -R $USER:$USER $WORK_DIR

# --- Tạo systemd service ---
cat <<EOF >/etc/systemd/system/mtproxy.service
[Unit]
Description=MTProto Proxy Telegram
After=network.target

[Service]
User=$USER
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/objs/bin/mtproto-proxy \\
  -u $USER \\
  -p 8888 \\
  -H $PORT \\
  -S $SECRET_HEX \\
  --aes-pwd $WORK_DIR/proxy-secret $WORK_DIR/proxy-multi.conf \\
  -M 1
Restart=on-failure
LimitNOFILE=51200
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# --- Mở cổng tường lửa ---
ufw allow $PORT/tcp
ufw allow $PORT/udp

# --- Kích hoạt và chạy dịch vụ ---
systemctl daemon-reload
systemctl enable mtproxy
systemctl restart mtproxy

# --- Lấy IP ---
IP=$(curl -s ifconfig.me)

# --- Hiển thị thông tin proxy ---
echo ""
echo "✅ MTProto Proxy đã được cài đặt và chạy trên port $PORT"
echo "🔐 Secret Key: $SECRET_HEX"
echo "📎 Link Telegram:"
echo "tg://proxy?server=$IP&port=$PORT&secret=$TAG"
echo ""
echo "🌐 Link chia sẻ web:"
echo "https://t.me/proxy?server=$IP&port=$PORT&secret=$TAG"
