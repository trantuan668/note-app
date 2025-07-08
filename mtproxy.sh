#!/bin/bash
# Cập nhật hệ thống
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Thêm kho lưu trữ Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Cài đặt Docker
sudo apt-get update
sudo apt-get install -y docker-ce

# Kích hoạt và khởi động Docker
sudo systemctl enable docker
sudo systemctl start docker

# Cài đặt Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
