#!/bin/bash

# Danh sách domain phổ biến hoạt động tốt với Telegram VoIP
domains=(
    "www.cloudflare.com"
    "cdn.cloudflare.com"
    "www.google.com"
    "www.bing.com"
    "www.microsoft.com"
    "www.amazon.com"
    "cdn.telegram.org"
    "graph.facebook.com"
    "www.youtube.com"
    "clients3.google.com"
)

echo "🔐 Danh sách 10 FakeTLS Secret ngẫu nhiên (dùng cho MTProto Proxy):"
echo "---------------------------------------------------------------"

for i in {1..10}; do
    domain=${domains[$RANDOM % ${#domains[@]}]}
    secret_hex=$(head -c 16 /dev/urandom | xxd -p)
    domain_hex=$(echo -n "$domain" | xxd -p)
    faketls_secret="ee${secret_hex}${domain_hex}"

    echo "[$i]"
    echo "🌐 Domain      : $domain"
    echo "🔑 Secret      : $faketls_secret"
    echo "🧪 Telegram URL: tg://proxy?server=YOUR_IP&port=443&secret=$faketls_secret"
    echo "---------------------------------------------------------------"
done
