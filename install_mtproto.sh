#!/bin/bash

# ====================== THÔNG SỐ ======================
PORT=8443
WORK_DIR="/opt/mtproxy"
USER=mtproxy
SECRET_HEX=$(head -c 16 /dev/urandom | xxd -ps)
TAG="ee${SECRET_HEX}"
DASHBOARD_PORT=5000

# ====================== CÀI THÊM GÓI ======================
apt update && apt install -y git curl build-essential libssl-dev zlib1g-dev python3 python3-pip geoip-bin
pip3 install flask geoip2 flask_cors

# ====================== TẠO USER & THƯ MỤC ======================
id -u $USER &>/dev/null || useradd -r -s /usr/sbin/nologin $USER
rm -rf $WORK_DIR
mkdir -p $WORK_DIR && cd $WORK_DIR

# ====================== CÀI MTProxy ======================
git clone https://github.com/TelegramMessenger/MTProxy $WORK_DIR/src
cd $WORK_DIR/src && make
cd $WORK_DIR
cp src/proxy-secret src/proxy-multi.conf .
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
echo "$SECRET_HEX" > secret.key
chown -R $USER:$USER $WORK_DIR

# ====================== SERVICE MTProxy ======================
cat <<EOF >/etc/systemd/system/mtproxy.service
[Unit]
Description=MTProto Proxy Telegram
After=network.target

[Service]
User=$USER
WorkingDirectory=$WORK_DIR
ExecStart=$WORK_DIR/src/objs/bin/mtproto-proxy \\
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

# ====================== DASHBOARD FLASK ======================
cat <<EOF >$WORK_DIR/dashboard.py
# -*- coding: utf-8 -*-
from flask import Flask, jsonify, render_template, request
from flask_cors import CORS
from datetime import datetime, timedelta
import os, geoip2.database, json

app = Flask(__name__)
CORS(app)

LOG_FILE = "/var/log/mtproxy_access.log"
GEOIP_DB = "/usr/share/GeoIP/GeoLite2-City.mmdb"

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/stats")
def stats():
    timeframe = request.args.get("time", "24h")
    since = datetime.utcnow() - (timedelta(hours=1) if timeframe == "1h" else timedelta(hours=24))
    stats = {}
    if os.path.exists(LOG_FILE):
        with open(LOG_FILE) as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) < 2:
                    continue
                ts, ip = parts[0], parts[1]
                try:
                    dt = datetime.utcfromtimestamp(float(ts))
                    if dt >= since:
                        stats[ip] = stats.get(ip, 0) + 1
                except:
                    continue
    sorted_stats = sorted(stats.items(), key=lambda x: x[1], reverse=True)
    return jsonify(sorted_stats[:5])

@app.route("/api/geoip/<ip>")
def geoip(ip):
    try:
        reader = geoip2.database.Reader(GEOIP_DB)
        response = reader.city(ip)
        return jsonify({
            "ip": ip,
            "city": response.city.name,
            "country": response.country.name
        })
    except:
        return jsonify({"ip": ip, "city": "Unknown", "country": "Unknown"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=$DASHBOARD_PORT)
EOF

# ====================== DASHBOARD TEMPLATE ======================
mkdir -p $WORK_DIR/templates
cat <<EOF >$WORK_DIR/templates/index.html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>MTProxy IP Stats</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <h2>Top 5 IP (Kết nối gần đây)</h2>
  <select onchange="load(this.value)">
    <option value="1h">Trong 1 giờ</option>
    <option value="24h" selected>Trong 24 giờ</option>
  </select>
  <canvas id="chart" width="400" height="200"></canvas>
  <ul id="ip-info"></ul>
  <script>
    async function load(time) {
      const res = await fetch('/api/stats?time=' + time);
      const data = await res.json();
      const ctx = document.getElementById('chart').getContext('2d');
      const labels = data.map(d => d[0]);
      const counts = data.map(d => d[1]);
      if (window.myChart) window.myChart.destroy();
      window.myChart = new Chart(ctx, {
        type: 'pie',
        data: {
          labels: labels,
          datasets: [{ data: counts, backgroundColor: ['red','green','blue','orange','purple'] }]
        }
      });
      const ul = document.getElementById("ip-info");
      ul.innerHTML = "";
      for (let [ip] of data) {
        const geo = await fetch('/api/geoip/' + ip).then(r => r.json());
        ul.innerHTML += '<li>' + ip + ' - ' + geo.city + ', ' + geo.country + '</li>';
      }
    }
    load("24h");
  </script>
</body>
</html>
EOF

# ====================== SERVICE DASHBOARD ======================
cat <<EOF >/etc/systemd/system/dashboard.service
[Unit]
Description=MTProxy Dashboard IP Stats
After=network.target

[Service]
WorkingDirectory=$WORK_DIR
ExecStart=/usr/bin/python3 dashboard.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ====================== CẤP PHÉP & CHẠY ======================
touch /var/log/mtproxy_access.log
chown $USER:$USER /var/log/mtproxy_access.log
ufw allow $PORT/tcp
ufw allow $DASHBOARD_PORT/tcp

systemctl daemon-reload
systemctl enable mtproxy dashboard
systemctl restart mtproxy dashboard

# ====================== THÔNG TIN CUỐI ======================
IP=$(curl -s ifconfig.me)
echo ""
echo "✅ MTProxy đang chạy trên port $PORT"
echo "🔐 Secret: $SECRET_HEX"
echo "📎 Link Telegram: tg://proxy?server=$IP&port=$PORT&secret=$TAG"
echo ""
echo "📊 Dashboard: http://$IP:$DASHBOARD_PORT"
