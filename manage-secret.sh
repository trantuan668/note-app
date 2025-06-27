# Dockerfile
FROM alpine:latest

RUN apk add --no-cache git build-base libevent-dev openssl-dev && \
    git clone https://github.com/TelegramMessenger/MTProxy && \
    cd MTProxy && make

WORKDIR /MTProxy
EXPOSE 443

ENTRYPOINT ["./objs/bin/mtproto-proxy"]

---
# docker-compose.yml
version: '3.8'
services:
  mtproxy:
    build: .
    container_name: mtproxy
    ports:
      - "443:443"
    volumes:
      - ./config:/config
    command: >
      ./objs/bin/mtproto-proxy
      -u nobody
      -p 8888
      -H 443
      -S $(cat /config/proxy-secret | tr '\n' ',')
      -M 1
      --aes-pwd /config/proxy-secret /config/proxy-multi.conf

---
# config/proxy-secret
# Example secrets (1 line per user)
1234567890abcdef1234567890abcdef
abcdef1234567890abcdef1234567890

---
# config/proxy-multi.conf
# Format: <secret> tag=<user_tag>
1234567890abcdef1234567890abcdef tag=user1
abcdef1234567890abcdef1234567890 tag=user2

---
# scripts/manage_secret.sh
#!/bin/bash

CONFIG_DIR=./config
SECRET_FILE="$CONFIG_DIR/proxy-secret"
MULTI_CONF="$CONFIG_DIR/proxy-multi.conf"

add_secret() {
    SECRET=$1
    TAG=$2
    if grep -q "$SECRET" $SECRET_FILE; then
        echo "Secret already exists."
        exit 1
    fi
    echo "$SECRET" >> $SECRET_FILE
    echo "$SECRET tag=$TAG" >> $MULTI_CONF
    docker restart mtproxy
}

remove_secret() {
    SECRET=$1
    sed -i "/$SECRET/d" $SECRET_FILE
    sed -i "/$SECRET/d" $MULTI_CONF
    docker restart mtproxy
}

case "$1" in
  add_secret)
    add_secret $2 $3
    ;;
  remove_secret)
    remove_secret $2
    ;;
  *)
    echo "Usage: $0 {add_secret <secret> <tag>|remove_secret <secret>}"
    exit 1
esac

---
# README.md
# MTProxy Docker + Secret Manager

Triển khai MTProxy trong Docker với nhiều người dùng.

## Cài đặt
```bash
git clone <repo_url>
cd mtproxy-docker-manager
docker-compose build
docker-compose up -d
```

## Thêm hoặc Xóa người dùng
```bash
# Thêm
./scripts/manage_secret.sh add_secret 1234567890abcdef1234567890abcdef user1

# Xóa
./scripts/manage_secret.sh remove_secret 1234567890abcdef1234567890abcdef
```

## Tạo link kết nối
```
tg://proxy?server=<IP>&port=443&secret=ee<secret>
```

## Gợi ý
- Tích hợp cron để xóa secret hết hạn
- Tạo web panel để thêm/xóa dễ hơn
