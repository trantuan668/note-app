#!/bin/bash

# === CONFIG ===
IP=$(curl -s https://api.ipify.org)
PORT=443
SERVICE_NAME="mtprotoproxy"

echo "==🧪 Đang kiểm tra trạng thái MTProto Proxy trên $IP:$PORT =="

# 1. Kiểm tra service
echo -e "\n🔍 [1] Kiểm tra trạng thái systemd:"
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "✅ Service '$SERVICE_NAME' đang chạy."
else
    echo "❌ Service '$SERVICE_NAME' không chạy."
    systemctl status $SERVICE_NAME --no-pager
fi

# 2. Kiểm tra cổng
echo -e "\n🔍 [2] Kiểm tra port $PORT:"
if ss -tulnp | grep -q ":$PORT"; then
    echo "✅ Port $PORT đang được lắng nghe."
else
    echo "❌ Port $PORT chưa được mở hoặc chưa có tiến trình nào lắng nghe."
fi

# 3. Kiểm tra firewall UFW
echo -e "\n🔍 [3] Kiểm tra firewall (ufw):"
ufw status verbose | grep -q "$PORT"
if [ $? -eq 0 ]; then
    echo "✅ Port $PORT đã được mở trên firewall."
else
    echo "⚠️ Port $PORT CHƯA được mở trên firewall. Mở bằng:"
    echo "    sudo ufw allow $PORT/tcp"
fi

# 4. Kiểm tra phản hồi TLS
echo -e "\n🔍 [4] Kiểm tra TLS phản hồi từ $IP:$PORT (FakeTLS check):"
timeout 5 bash -c "</dev/tcp/$IP/$PORT" &> /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Cổng $PORT có thể kết nối từ nội bộ."
else
    echo "❌ Không thể kết nối tới $IP:$PORT (có thể bị chặn hoặc service không chạy)."
fi

# 5. Đo độ trễ
echo -e "\n🔍 [5] Đo ping:"
ping -c 3 $IP

# 6. Kiểm tra từ bên ngoài (bằng curl HTTPS nếu là FakeTLS)
echo -e "\n🔍 [6] Kiểm tra phản hồi HTTPS (FakeTLS check):"
curl -vk --connect-timeout 5 https://$IP:$PORT 2>&1 | grep "Connected" && echo "✅ FakeTLS có phản hồi HTTPS." || echo "⚠️ Không phản hồi FakeTLS HTTPS."

# 7. Gợi ý thêm
echo -e "\n📌 Nếu vẫn không vào Telegram được:"
echo "   - Kiểm tra proxy có chạy đúng secret, đúng định dạng (ee + hex + domain)."
echo "   - Dùng VPS khác (Hetzner, Contabo), không nên dùng Google Cloud hoặc Azure."
