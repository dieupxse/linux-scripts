#!/usr/bin/env bash

set -e

echo "====================================="
echo " Update Ubuntu"
echo "====================================="
apt update
apt upgrade -y

echo "====================================="
echo " Install prerequisites"
echo "====================================="
apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https

echo "====================================="
echo " Install Docker"
echo "====================================="

install -m 0755 -d /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
fi

cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF

apt update

apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "====================================="
echo " Install MySQL"
echo "====================================="
apt install -y mysql-server mysql-client

systemctl enable mysql
systemctl start mysql

echo "====================================="
echo " Install Nginx"
echo "====================================="
apt install -y nginx

systemctl enable nginx
systemctl start nginx

echo "====================================="
echo " Install Certbot"
echo "====================================="
apt install -y \
    certbot \
    python3-certbot-nginx

echo "====================================="
echo " Install net-tools"
echo "====================================="
apt install -y net-tools

echo "====================================="
echo " Verify versions"
echo "====================================="

echo ""
echo "Docker:"
docker --version || true

echo ""
echo "Docker Compose:"
docker compose version || true

echo ""
echo "MySQL:"
mysql --version || true

echo ""
echo "Nginx:"
nginx -v || true

echo ""
echo "Certbot:"
certbot --version || true

echo ""
echo "====================================="
echo " Installation completed"
echo "====================================="

echo ""
echo "Next steps:"
echo "1. mysql_secure_installation"
echo "2. ufw allow OpenSSH"
echo "3. ufw allow 'Nginx Full'"
echo "4. certbot --nginx -d example.com"