#!/bin/bash

# Script tự động cài đặt N8N + NocoDB trên Ubuntu
# Tác giả: Auto Install Script
# Phiên bản: 1.0

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Hàm hiển thị thông báo
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

# Hàm kiểm tra lỗi
check_error() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    fi
}

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then 
    print_error "Vui lòng chạy script với quyền root hoặc sudo"
    exit 1
fi

# Banner
clear
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║     SCRIPT CÀI ĐẶT TỰ ĐỘNG N8N + NOCODB + NGINX + SSL    ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Thu thập thông tin từ người dùng
print_message "Vui lòng nhập các thông tin cần thiết:"
echo ""

read -p "Nhập domain cho N8N (VD: n8n.modaviet.pro.vn): " N8N_DOMAIN
read -p "Nhập domain cho NocoDB (VD: noco.modaviet.pro.vn): " NOCODB_DOMAIN
read -p "Nhập email để đăng ký SSL (VD: admin@modaviet.pro.vn): " SSL_EMAIL
echo ""

read -p "Nhập mật khẩu cho PostgreSQL Database: " -s POSTGRES_PASSWORD
echo ""
read -p "Nhập JWT Secret cho NocoDB (hoặc để trống để tự động tạo): " JWT_SECRET
echo ""

# Tạo JWT secret nếu để trống
if [ -z "$JWT_SECRET" ]; then
    JWT_SECRET=$(openssl rand -base64 32)
    print_message "JWT Secret đã được tạo tự động"
fi

# Xác nhận thông tin
echo ""
print_warning "Xác nhận thông tin:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "N8N Domain       : $N8N_DOMAIN"
echo "NocoDB Domain    : $NOCODB_DOMAIN"
echo "SSL Email        : $SSL_EMAIL"
echo "Postgres Password: ********"
echo "JWT Secret       : ********"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Thông tin có chính xác không? (y/n): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    print_error "Đã hủy cài đặt"
    exit 1
fi

echo ""
print_success "Bắt đầu quá trình cài đặt..."
sleep 2

# Bước 1: Cập nhật hệ thống
print_message "Bước 1/9: Cập nhật hệ thống..."
apt update && apt upgrade -y
check_error "Cập nhật hệ thống thất bại"

# Bước 2: Cài đặt các gói cần thiết
print_message "Bước 2/9: Cài đặt các gói cần thiết..."
apt install -y apt-transport-https ca-certificates curl software-properties-common ufw
check_error "Cài đặt các gói cần thiết thất bại"

# Bước 3: Cài đặt Docker
print_message "Bước 3/9: Cài đặt Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    check_error "Cài đặt Docker thất bại"
    systemctl start docker
    systemctl enable docker
    print_success "Docker đã được cài đặt thành công"
else
    print_warning "Docker đã được cài đặt, bỏ qua bước này"
fi

# Bước 4: Cài đặt Docker Compose
print_message "Bước 4/9: Cài đặt Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    check_error "Cài đặt Docker Compose thất bại"
    print_success "Docker Compose đã được cài đặt thành công"
else
    print_warning "Docker Compose đã được cài đặt, bỏ qua bước này"
fi

# Bước 5: Cài đặt Nginx
print_message "Bước 5/9: Cài đặt Nginx..."
if ! command -v nginx &> /dev/null; then
    apt install -y nginx
    check_error "Cài đặt Nginx thất bại"
    systemctl start nginx
    systemctl enable nginx
    print_success "Nginx đã được cài đặt thành công"
else
    print_warning "Nginx đã được cài đặt, bỏ qua bước này"
fi

# Bước 6: Cài đặt Certbot
print_message "Bước 6/9: Cài đặt Certbot..."
apt install -y certbot python3-certbot-nginx
check_error "Cài đặt Certbot thất bại"

# Bước 7: Tạo cấu trúc thư mục và file docker-compose
print_message "Bước 7/9: Tạo cấu trúc thư mục và cấu hình..."
INSTALL_DIR="/root/apps"
mkdir -p $INSTALL_DIR/n8n
mkdir -p $INSTALL_DIR/nocodb
mkdir -p $INSTALL_DIR/nocodb_db

# Tạo file docker-compose.yml
cat > $INSTALL_DIR/docker-compose.yml << EOF
version: '3.8'

services:
  # N8N Service
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=$N8N_DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$N8N_DOMAIN/
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - ./n8n:/home/node/.n8n
    networks:
      - app-network

  # NocoDB Service
  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      - NC_DB=pg://nocodb_db:5432?u=nocodb&p=$POSTGRES_PASSWORD&d=nocodb
      - NC_AUTH_JWT_SECRET=$JWT_SECRET
      - NC_PUBLIC_URL=https://$NOCODB_DOMAIN
      - NC_DISABLE_TELE=true
    volumes:
      - ./nocodb:/usr/app/data
    depends_on:
      - nocodb_db
    networks:
      - app-network

  # PostgreSQL for NocoDB
  nocodb_db:
    image: postgres:14-alpine
    container_name: nocodb_db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=nocodb
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
      - POSTGRES_DB=nocodb
    volumes:
      - ./nocodb_db:/var/lib/postgresql/data
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
EOF

print_success "File docker-compose.yml đã được tạo"

# Khởi động Docker containers
print_message "Khởi động Docker containers..."
cd $INSTALL_DIR
docker-compose up -d
check_error "Khởi động Docker containers thất bại"
sleep 10

# Bước 8: Cấu hình Nginx
print_message "Bước 8/9: Cấu hình Nginx..."

# Cấu hình cho N8N
cat > /etc/nginx/sites-available/$N8N_DOMAIN << EOF
server {
    listen 80;
    server_name $N8N_DOMAIN;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_read_timeout 86400;
    }
}
EOF

# Cấu hình cho NocoDB
cat > /etc/nginx/sites-available/$NOCODB_DOMAIN << EOF
server {
    listen 80;
    server_name $NOCODB_DOMAIN;

    client_max_body_size 100M;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeout settings
        proxy_read_timeout 600s;
        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

# Kích hoạt sites
ln -sf /etc/nginx/sites-available/$N8N_DOMAIN /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/$NOCODB_DOMAIN /etc/nginx/sites-enabled/

# Kiểm tra cấu hình Nginx
nginx -t
check_error "Cấu hình Nginx không hợp lệ"

# Khởi động lại Nginx
systemctl restart nginx
check_error "Khởi động lại Nginx thất bại"
print_success "Nginx đã được cấu hình thành công"

# Bước 9: Cài đặt SSL Certificate
print_message "Bước 9/9: Cài đặt SSL Certificate..."
sleep 2

print_message "Đang cài đặt SSL cho $N8N_DOMAIN..."
certbot --nginx -d $N8N_DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL --redirect
if [ $? -eq 0 ]; then
    print_success "SSL cho N8N đã được cài đặt thành công"
else
    print_error "Cài đặt SSL cho N8N thất bại. Vui lòng kiểm tra DNS và thử lại."
fi

sleep 2

print_message "Đang cài đặt SSL cho $NOCODB_DOMAIN..."
certbot --nginx -d $NOCODB_DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL --redirect
if [ $? -eq 0 ]; then
    print_success "SSL cho NocoDB đã được cài đặt thành công"
else
    print_error "Cài đặt SSL cho NocoDB thất bại. Vui lòng kiểm tra DNS và thử lại."
fi

# Cấu hình tự động gia hạn SSL
print_message "Cấu hình tự động gia hạn SSL..."
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
print_success "Tự động gia hạn SSL đã được cấu hình"

# Cấu hình Firewall
print_message "Cấu hình Firewall..."
ufw --force enable
ufw allow 'Nginx Full'
ufw allow OpenSSH
ufw allow 22/tcp
print_success "Firewall đã được cấu hình"

# Tạo file thông tin
cat > $INSTALL_DIR/installation-info.txt << EOF
╔════════════════════════════════════════════════════════════╗
║           THÔNG TIN CÀI ĐẶT N8N + NOCODB                  ║
╚════════════════════════════════════════════════════════════╝

Ngày cài đặt: $(date)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
URL TRUY CẬP:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
N8N        : https://$N8N_DOMAIN
NocoDB     : https://$NOCODB_DOMAIN

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
THÔNG TIN DATABASE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Database User     : nocodb
Database Password : $POSTGRES_PASSWORD
Database Name     : nocodb
JWT Secret        : $JWT_SECRET

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
THƯ MỤC CÀI ĐẶT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Thư mục chính     : $INSTALL_DIR
Docker Compose    : $INSTALL_DIR/docker-compose.yml
Dữ liệu N8N       : $INSTALL_DIR/n8n
Dữ liệu NocoDB    : $INSTALL_DIR/nocodb
Database          : $INSTALL_DIR/nocodb_db

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LỆNH QUẢN LÝ HỮU ÍCH:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Di chuyển vào thư mục:
  cd $INSTALL_DIR

Xem logs:
  docker-compose logs -f n8n
  docker-compose logs -f nocodb

Khởi động lại:
  docker-compose restart n8n
  docker-compose restart nocodb

Dừng tất cả:
  docker-compose down

Khởi động tất cả:
  docker-compose up -d

Cập nhật containers:
  docker-compose pull
  docker-compose up -d

Backup dữ liệu:
  tar -czf backup-\$(date +%Y%m%d).tar.gz $INSTALL_DIR

Kiểm tra SSL:
  certbot certificates

Gia hạn SSL thủ công:
  certbot renew

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LƯU Ý BẢO MẬT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- File này chứa thông tin nhạy cảm, vui lòng bảo mật
- Thay đổi mật khẩu mặc định sau khi đăng nhập
- Thiết lập backup định kỳ cho dữ liệu
- SSL sẽ tự động gia hạn mỗi ngày lúc 3:00 AM

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# Hoàn thành
clear
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║            CÀI ĐẶT HOÀN TẤT THÀNH CÔNG! 🎉                ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}URL TRUY CẬP:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "N8N        : ${YELLOW}https://$N8N_DOMAIN${NC}"
echo -e "NocoDB     : ${YELLOW}https://$NOCODB_DOMAIN${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}THÔNG TIN QUAN TRỌNG:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "✓ Tất cả thông tin đã được lưu tại: ${YELLOW}$INSTALL_DIR/installation-info.txt${NC}"
echo -e "✓ SSL Certificate đã được cài đặt và tự động gia hạn"
echo -e "✓ Docker containers đang chạy"
echo -e "✓ Firewall đã được cấu hình"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}BƯỚC TIẾP THEO:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "1. Truy cập vào các URL ở trên để thiết lập tài khoản"
echo -e "2. Đọc file thông tin chi tiết: ${YELLOW}cat $INSTALL_DIR/installation-info.txt${NC}"
echo -e "3. Thiết lập backup định kỳ cho dữ liệu"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}KIỂM TRA TRẠNG THÁI:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "cd $INSTALL_DIR && docker-compose ps"
echo ""
echo -e "${GREEN}Cảm ơn bạn đã sử dụng script! 🚀${NC}"
echo ""
