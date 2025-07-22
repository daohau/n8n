#!/bin/bash

# Script để triển khai n8n trên VPS với PostgreSQL, Nginx, SSL và gia hạn tự động
# Yêu cầu: Chạy trên Ubuntu 20.04/22.04 với quyền root/sudo
# Đã trỏ bản ghi A của tên miền đến IP của VPS

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script với quyền root hoặc sudo."
  exit 1
fi

# Nhập tên miền của n8n
read -p "Nhập tên miền cho n8n (ví dụ: n8n.modaviet.vn): " N8N_DOMAIN
if [ -z "$N8N_DOMAIN" ]; then
  echo "Tên miền không được để trống!"
  exit 1
fi

# Tạo khóa mã hóa và mật khẩu PostgreSQL ngẫu nhiên
ENCRYPTION_KEY=$(openssl rand -base64 32)
POSTGRES_PASSWORD=$(openssl rand -base64 16)

# Cập nhật hệ thống
echo "Cập nhật hệ thống..."
apt update && apt upgrade -y

# Cài đặt các công cụ cần thiết
echo "Cài đặt Docker, Docker Compose, Nginx và Certbot..."
apt install -y docker.io nginx certbot python3-certbot-nginx
systemctl start docker
systemctl enable docker

# Cài đặt Docker Compose
curl -L "https://github.com/docker/compose/releases/download/2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Kiểm tra cài đặt
docker --version
docker-compose --version

# Tạo thư mục cho n8n
echo "Tạo thư mục và cấu hình n8n với PostgreSQL..."
mkdir -p /root/n8n/n8n_data
mkdir -p /root/n8n/postgres_data
cd /root/n8n

# Tạo file docker-compose.yml với PostgreSQL
cat > docker-compose.yml <<EOL
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:latest
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - N8N_EDITOR_BASE_URL=https://${N8N_DOMAIN}/
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ./n8n_data:/home/node/.n8n
    depends_on:
      - postgres
    restart: always
  postgres:
    image: postgres:13
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - ./postgres_data:/var/lib/postgresql/data
    restart: always
volumes:
  n8n_data:
  postgres_data:
EOL

# Phân quyền thư mục dữ liệu
chown -R 1000:1000 n8n_data
chown -R 999:999 postgres_data

# Khởi động n8n và PostgreSQL
echo "Khởi động n8n và PostgreSQL..."
docker-compose up -d

# Kiểm tra container
echo "Kiểm tra trạng thái container..."
docker ps

# Cấu hình Nginx
echo "Cấu hình Nginx..."
cat > /etc/nginx/sites-available/${N8N_DOMAIN} <<EOL
server {
    listen 80;
    server_name ${N8N_DOMAIN};

    # Chuyển hướng HTTP sang HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${N8N_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${N8N_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${N8N_DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOL

# Kích hoạt cấu hình Nginx
ln -s /etc/nginx/sites-available/${N8N_DOMAIN} /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx

# Cài đặt chứng chỉ SSL
echo "Cài đặt chứng chỉ SSL với Let's Encrypt..."
certbot --nginx -d ${N8N_DOMAIN} --non-interactive --agree-tos --email admin@${N8N_DOMAIN}

# Kiểm tra và khởi động lại Nginx
nginx -t
systemctl restart nginx

# Thiết lập gia hạn tự động SSL
echo "Thiết lập gia hạn tự động SSL..."
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet") | crontab -

# Kiểm tra firewall (nếu sử dụng UFW)
if command -v ufw >/dev/null; then
  echo "Cấu hình firewall..."
  ufw allow 80
  ufw allow 443
  ufw allow 5678
fi

# Thông báo hoàn tất
echo "---------------------------------------------"
echo "Hoàn tất! n8n đã được triển khai tại https://${N8N_DOMAIN}"
echo "Truy cập URL trên để thiết lập tài khoản quản trị."
echo "Khóa mã hóa n8n: ${ENCRYPTION_KEY}"
echo "Mật khẩu PostgreSQL: ${POSTGRES_PASSWORD}"
echo "Lưu trữ các khóa trên ở nơi an toàn!"
echo "---------------------------------------------"
