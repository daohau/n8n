#!/bin/bash

# Script quản lý N8N + NocoDB trên Ubuntu (V3.0 - Menu Version)
# Tác giả: Auto Management Script
# Phiên bản: 3.0

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Thư mục cài đặt
INSTALL_DIR="/root/apps"
BACKUP_DIR="/root/backups"

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
        read -p "Nhấn Enter để quay lại menu..."
        return 1
    fi
    return 0
}

# Kiểm tra quyền root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "Vui lòng chạy script với quyền root hoặc sudo"
        exit 1
    fi
}

# Kiểm tra Docker đã cài chưa
check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi
    return 0
}

# Kiểm tra N8N đã cài chưa
check_n8n_installed() {
    if [ -f "$INSTALL_DIR/docker-compose.yml" ] && docker ps -a | grep -q "n8n"; then
        return 0
    fi
    return 1
}

# Kiểm tra NocoDB đã cài chưa
check_nocodb_installed() {
    if [ -f "$INSTALL_DIR/docker-compose.yml" ] && docker ps -a | grep -q "nocodb"; then
        return 0
    fi
    return 1
}

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║       QUẢN LÝ N8N + NOCODB - PHIÊN BẢN 3.0               ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Menu chính
show_main_menu() {
    show_banner
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    MENU CHÍNH                              ${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Cài đặt N8N"
    echo -e "  ${CYAN}2)${NC} Cài đặt NocoDB"
    echo -e "  ${CYAN}3)${NC} Cập nhật N8N lên phiên bản mới nhất"
    echo -e "  ${CYAN}4)${NC} Cập nhật NocoDB lên phiên bản mới nhất"
    echo -e "  ${CYAN}5)${NC} Tự động sao lưu dữ liệu N8N"
    echo -e "  ${CYAN}6)${NC} Tự động sao lưu dữ liệu NocoDB"
    echo -e "  ${CYAN}7)${NC} Khôi phục dữ liệu N8N"
    echo -e "  ${CYAN}8)${NC} Khôi phục dữ liệu NocoDB"
    echo -e "  ${CYAN}9)${NC} Xem trạng thái hệ thống"
    echo -e "  ${CYAN}10)${NC} Xem logs"
    echo -e "  ${RED}0)${NC} Thoát"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Cài đặt Docker và Docker Compose
install_docker() {
    print_message "Cài đặt Docker và Docker Compose..."
    
    if command -v docker &> /dev/null; then
        print_warning "Docker đã được cài đặt"
        return 0
    fi
    
    # Cài Docker
    apt update
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    
    if ! check_error "Cài đặt Docker thất bại"; then
        return 1
    fi
    
    systemctl start docker
    systemctl enable docker
    
    # Cài Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    print_success "Docker và Docker Compose đã được cài đặt thành công"
    return 0
}

# Cài đặt Nginx và Certbot
install_nginx_certbot() {
    print_message "Cài đặt Nginx và Certbot..."
    
    if ! command -v nginx &> /dev/null; then
        apt install -y nginx
        systemctl start nginx
        systemctl enable nginx
    else
        print_warning "Nginx đã được cài đặt"
    fi
    
    if ! command -v certbot &> /dev/null; then
        apt install -y certbot python3-certbot-nginx
    else
        print_warning "Certbot đã được cài đặt"
    fi
    
    print_success "Nginx và Certbot đã sẵn sàng"
}

# Cấu hình Firewall
configure_firewall() {
    print_message "Cấu hình Firewall..."
    ufw --force enable
    ufw allow 'Nginx Full'
    ufw allow OpenSSH
    ufw allow 22/tcp
    print_success "Firewall đã được cấu hình"
}

# 1. Cài đặt N8N
install_n8n() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              CÀI ĐẶT N8N                                 ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Kiểm tra đã cài chưa
    if check_n8n_installed; then
        print_warning "N8N đã được cài đặt!"
        read -p "Bạn có muốn cài đặt lại không? (y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            return
        fi
    fi
    
    # Cài Docker nếu chưa có
    if ! check_docker_installed; then
        install_docker
        if [ $? -ne 0 ]; then
            return
        fi
    fi
    
    # Cài Nginx và Certbot
    install_nginx_certbot
    
    # Thu thập thông tin
    read -p "Nhập domain cho N8N (VD: n8n.modaviet.pro.vn): " N8N_DOMAIN
    read -p "Nhập email để đăng ký SSL: " SSL_EMAIL
    
    # Tạo encryption key
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    
    # Tạo thư mục
    mkdir -p $INSTALL_DIR/n8n
    chown -R 1000:1000 $INSTALL_DIR/n8n
    chmod -R 755 $INSTALL_DIR/n8n
    
    # Tạo hoặc cập nhật docker-compose.yml
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        # Backup file cũ
        cp $INSTALL_DIR/docker-compose.yml $INSTALL_DIR/docker-compose.yml.backup
        
        # Kiểm tra xem đã có service n8n chưa
        if grep -q "n8n:" $INSTALL_DIR/docker-compose.yml; then
            print_message "Cập nhật cấu hình N8N trong docker-compose.yml..."
            # Xóa service n8n cũ và thêm mới
            sed -i '/^  n8n:/,/^  [a-z]/d' $INSTALL_DIR/docker-compose.yml
        fi
        
        # Thêm service n8n vào file
        cat >> $INSTALL_DIR/docker-compose.yml << EOF

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
      - WEBHOOK_URL=https://$N8N_DOMAIN/
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
    volumes:
      - ./n8n:/home/node/.n8n
    networks:
      - app-network
    user: "1000:1000"
EOF
    else
        # Tạo file mới
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
      - WEBHOOK_URL=https://$N8N_DOMAIN/
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
    volumes:
      - ./n8n:/home/node/.n8n
    networks:
      - app-network
    user: "1000:1000"

networks:
  app-network:
    driver: bridge
EOF
    fi
    
    # Cấu hình Nginx
    cat > /etc/nginx/sites-available/$N8N_DOMAIN << 'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }
}
NGINX_EOF
    
    sed -i "s/DOMAIN_PLACEHOLDER/$N8N_DOMAIN/g" /etc/nginx/sites-available/$N8N_DOMAIN
    ln -sf /etc/nginx/sites-available/$N8N_DOMAIN /etc/nginx/sites-enabled/
    
    nginx -t && systemctl reload nginx
    
    # Khởi động N8N
    cd $INSTALL_DIR
    docker-compose up -d n8n
    
    print_message "Đợi 30 giây để N8N khởi động..."
    sleep 30
    
    # Cài SSL
    print_message "Cài đặt SSL Certificate..."
    certbot --nginx -d $N8N_DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL --redirect
    
    # Lưu thông tin
    echo "N8N_DOMAIN=$N8N_DOMAIN" >> $INSTALL_DIR/n8n.env
    echo "N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY" >> $INSTALL_DIR/n8n.env
    chmod 600 $INSTALL_DIR/n8n.env
    
    configure_firewall
    
    print_success "Cài đặt N8N hoàn tất!"
    echo ""
    echo -e "${GREEN}URL truy cập:${NC} https://$N8N_DOMAIN"
    echo -e "${YELLOW}Encryption Key đã được lưu tại: $INSTALL_DIR/n8n.env${NC}"
    echo ""
    
    read -p "Nhấn Enter để quay lại menu..."
}

# 2. Cài đặt NocoDB
install_nocodb() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              CÀI ĐẶT NOCODB                              ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Kiểm tra đã cài chưa
    if check_nocodb_installed; then
        print_warning "NocoDB đã được cài đặt!"
        read -p "Bạn có muốn cài đặt lại không? (y/n): " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            return
        fi
    fi
    
    # Cài Docker nếu chưa có
    if ! check_docker_installed; then
        install_docker
        if [ $? -ne 0 ]; then
            return
        fi
    fi
    
    # Cài Nginx và Certbot
    install_nginx_certbot
    
    # Thu thập thông tin
    read -p "Nhập domain cho NocoDB (VD: noco.modaviet.pro.vn): " NOCODB_DOMAIN
    read -p "Nhập email để đăng ký SSL: " SSL_EMAIL
    read -p "Nhập mật khẩu cho PostgreSQL: " -s POSTGRES_PASSWORD
    echo ""
    
    # Tạo JWT secret
    JWT_SECRET=$(openssl rand -base64 32)
    
    # Tạo thư mục
    mkdir -p $INSTALL_DIR/nocodb
    mkdir -p $INSTALL_DIR/nocodb_db
    
    # Tạo hoặc cập nhật docker-compose.yml
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        cp $INSTALL_DIR/docker-compose.yml $INSTALL_DIR/docker-compose.yml.backup
        
        if grep -q "nocodb:" $INSTALL_DIR/docker-compose.yml; then
            print_message "Cập nhật cấu hình NocoDB trong docker-compose.yml..."
            sed -i '/^  nocodb:/,/^  [a-z]/d' $INSTALL_DIR/docker-compose.yml
            sed -i '/^  nocodb_db:/,/^  [a-z]/d' $INSTALL_DIR/docker-compose.yml
        fi
        
        cat >> $INSTALL_DIR/docker-compose.yml << EOF

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
EOF
    else
        cat > $INSTALL_DIR/docker-compose.yml << EOF
version: '3.8'

services:
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
    fi
    
    # Cấu hình Nginx
    cat > /etc/nginx/sites-available/$NOCODB_DOMAIN << 'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;
    client_max_body_size 100M;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 600s;
        proxy_connect_timeout 600s;
        proxy_send_timeout 600s;
    }
}
NGINX_EOF
    
    sed -i "s/DOMAIN_PLACEHOLDER/$NOCODB_DOMAIN/g" /etc/nginx/sites-available/$NOCODB_DOMAIN
    ln -sf /etc/nginx/sites-available/$NOCODB_DOMAIN /etc/nginx/sites-enabled/
    
    nginx -t && systemctl reload nginx
    
    # Khởi động NocoDB
    cd $INSTALL_DIR
    docker-compose up -d nocodb_db nocodb
    
    print_message "Đợi 30 giây để NocoDB khởi động..."
    sleep 30
    
    # Cài SSL
    print_message "Cài đặt SSL Certificate..."
    certbot --nginx -d $NOCODB_DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL --redirect
    
    # Lưu thông tin
    echo "NOCODB_DOMAIN=$NOCODB_DOMAIN" >> $INSTALL_DIR/nocodb.env
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> $INSTALL_DIR/nocodb.env
    echo "JWT_SECRET=$JWT_SECRET" >> $INSTALL_DIR/nocodb.env
    chmod 600 $INSTALL_DIR/nocodb.env
    
    configure_firewall
    
    print_success "Cài đặt NocoDB hoàn tất!"
    echo ""
    echo -e "${GREEN}URL truy cập:${NC} https://$NOCODB_DOMAIN"
    echo -e "${YELLOW}Thông tin đã được lưu tại: $INSTALL_DIR/nocodb.env${NC}"
    echo ""
    
    read -p "Nhấn Enter để quay lại menu..."
}

# 3. Cập nhật N8N
update_n8n() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              CẬP NHẬT N8N                                ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! check_n8n_installed; then
        print_error "N8N chưa được cài đặt!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    print_warning "Hệ thống sẽ backup dữ liệu trước khi cập nhật..."
    backup_n8n_silent
    
    cd $INSTALL_DIR
    
    print_message "Dừng container N8N..."
    docker-compose stop n8n
    
    print_message "Pull phiên bản mới nhất..."
    docker-compose pull n8n
    
    print_message "Khởi động lại N8N..."
    docker-compose up -d n8n
    
    print_message "Đợi 30 giây để N8N khởi động..."
    sleep 30
    
    # Kiểm tra trạng thái
    if docker ps | grep -q "n8n"; then
        print_success "Cập nhật N8N thành công!"
        docker-compose logs --tail=20 n8n
    else
        print_error "N8N không khởi động được. Đang rollback..."
        docker-compose down n8n
        docker-compose up -d n8n
    fi
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# 4. Cập nhật NocoDB
update_nocodb() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              CẬP NHẬT NOCODB                             ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! check_nocodb_installed; then
        print_error "NocoDB chưa được cài đặt!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    print_warning "Hệ thống sẽ backup dữ liệu trước khi cập nhật..."
    backup_nocodb_silent
    
    cd $INSTALL_DIR
    
    print_message "Dừng container NocoDB..."
    docker-compose stop nocodb
    
    print_message "Pull phiên bản mới nhất..."
    docker-compose pull nocodb
    
    print_message "Khởi động lại NocoDB..."
    docker-compose up -d nocodb
    
    print_message "Đợi 30 giây để NocoDB khởi động..."
    sleep 30
    
    # Kiểm tra trạng thái
    if docker ps | grep -q "nocodb"; then
        print_success "Cập nhật NocoDB thành công!"
        docker-compose logs --tail=20 nocodb
    else
        print_error "NocoDB không khởi động được. Đang rollback..."
        docker-compose down nocodb
        docker-compose up -d nocodb
    fi
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# 5. Backup N8N (silent version cho auto)
backup_n8n_silent() {
    mkdir -p $BACKUP_DIR
    BACKUP_FILE="$BACKUP_DIR/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if [ -d "$INSTALL_DIR/n8n" ]; then
        tar -czf $BACKUP_FILE -C $INSTALL_DIR n8n n8n.env 2>/dev/null || true
        return 0
    fi
    return 1
}

# 5. Backup N8N
backup_n8n() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              SAO LƯU DỮ LIỆU N8N                        ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! check_n8n_installed; then
        print_error "N8N chưa được cài đặt!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    mkdir -p $BACKUP_DIR
    BACKUP_FILE="$BACKUP_DIR/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    print_message "Đang sao lưu dữ liệu N8N..."
    
    cd $INSTALL_DIR
    tar -czf $BACKUP_FILE n8n n8n.env 2>/dev/null || tar -czf $BACKUP_FILE n8n
    
    if [ -f "$BACKUP_FILE" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        print_success "Sao lưu thành công!"
        echo ""
        echo -e "${GREEN}File backup:${NC} $BACKUP_FILE"
        echo -e "${GREEN}Database SQL:${NC} $DB_BACKUP"
        echo -e "${GREEN}Kích thước:${NC} $BACKUP_SIZE"
        
        # Tự động xóa backup cũ hơn 30 ngày
        find $BACKUP_DIR -name "nocodb-backup-*.tar.gz" -mtime +30 -delete 2>/dev/null
        find $BACKUP_DIR -name "nocodb-db-*.sql" -mtime +30 -delete 2>/dev/null
        
        echo ""
        echo -e "${YELLOW}Backup cũ hơn 30 ngày đã được tự động xóa${NC}"
    else
        print_error "Sao lưu thất bại!"
    fi
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# 7. Khôi phục N8N
restore_n8n() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              KHÔI PHỤC DỮ LIỆU N8N                      ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "Thư mục backup không tồn tại!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    # Liệt kê các file backup
    echo -e "${YELLOW}Danh sách các file backup N8N:${NC}"
    echo ""
    
    BACKUPS=($(ls -t $BACKUP_DIR/n8n-backup-*.tar.gz 2>/dev/null))
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        print_error "Không tìm thấy file backup nào!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    for i in "${!BACKUPS[@]}"; do
        BACKUP_FILE="${BACKUPS[$i]}"
        BACKUP_DATE=$(basename "$BACKUP_FILE" | sed 's/n8n-backup-\(.*\)\.tar\.gz/\1/')
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo -e "  ${CYAN}$((i+1)))${NC} $(basename $BACKUP_FILE) - ${GREEN}$BACKUP_SIZE${NC} - ${YELLOW}$BACKUP_DATE${NC}"
    done
    
    echo ""
    read -p "Chọn file backup để khôi phục (hoặc 0 để hủy): " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#BACKUPS[@]} ] 2>/dev/null; then
        print_error "Lựa chọn không hợp lệ!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    SELECTED_BACKUP="${BACKUPS[$((choice-1))]}"
    
    print_warning "CẢNH BÁO: Dữ liệu hiện tại sẽ bị ghi đè!"
    read -p "Bạn có chắc chắn muốn khôi phục? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_message "Đã hủy khôi phục"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    # Backup dữ liệu hiện tại trước khi khôi phục
    print_message "Đang backup dữ liệu hiện tại trước khi khôi phục..."
    backup_n8n_silent
    
    # Dừng N8N
    print_message "Đang dừng N8N..."
    cd $INSTALL_DIR
    docker-compose stop n8n 2>/dev/null || true
    
    # Xóa dữ liệu cũ
    print_message "Đang xóa dữ liệu cũ..."
    rm -rf $INSTALL_DIR/n8n.old 2>/dev/null || true
    mv $INSTALL_DIR/n8n $INSTALL_DIR/n8n.old 2>/dev/null || true
    
    # Giải nén backup
    print_message "Đang khôi phục dữ liệu từ backup..."
    tar -xzf "$SELECTED_BACKUP" -C $INSTALL_DIR
    
    # Phân quyền lại
    chown -R 1000:1000 $INSTALL_DIR/n8n
    chmod -R 755 $INSTALL_DIR/n8n
    
    # Khởi động lại N8N
    print_message "Đang khởi động lại N8N..."
    docker-compose up -d n8n
    
    print_message "Đợi 30 giây để N8N khởi động..."
    sleep 30
    
    if docker ps | grep -q "n8n"; then
        print_success "Khôi phục N8N thành công!"
        echo ""
        echo -e "${YELLOW}Dữ liệu cũ đã được lưu tại: $INSTALL_DIR/n8n.old${NC}"
    else
        print_error "Khởi động N8N thất bại!"
        echo ""
        echo -e "${YELLOW}Đang rollback về dữ liệu cũ...${NC}"
        rm -rf $INSTALL_DIR/n8n
        mv $INSTALL_DIR/n8n.old $INSTALL_DIR/n8n
        docker-compose up -d n8n
    fi
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# 8. Khôi phục NocoDB
restore_nocodb() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              KHÔI PHỤC DỮ LIỆU NOCODB                   ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "Thư mục backup không tồn tại!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    # Liệt kê các file backup
    echo -e "${YELLOW}Danh sách các file backup NocoDB:${NC}"
    echo ""
    
    BACKUPS=($(ls -t $BACKUP_DIR/nocodb-backup-*.tar.gz 2>/dev/null))
    
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        print_error "Không tìm thấy file backup nào!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    for i in "${!BACKUPS[@]}"; do
        BACKUP_FILE="${BACKUPS[$i]}"
        BACKUP_DATE=$(basename "$BACKUP_FILE" | sed 's/nocodb-backup-\(.*\)\.tar\.gz/\1/')
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo -e "  ${CYAN}$((i+1)))${NC} $(basename $BACKUP_FILE) - ${GREEN}$BACKUP_SIZE${NC} - ${YELLOW}$BACKUP_DATE${NC}"
    done
    
    echo ""
    read -p "Chọn file backup để khôi phục (hoặc 0 để hủy): " choice
    
    if [ "$choice" -eq 0 ] 2>/dev/null; then
        return
    fi
    
    if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#BACKUPS[@]} ] 2>/dev/null; then
        print_error "Lựa chọn không hợp lệ!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    SELECTED_BACKUP="${BACKUPS[$((choice-1))]}"
    
    print_warning "CẢNH BÁO: Dữ liệu hiện tại sẽ bị ghi đè!"
    read -p "Bạn có chắc chắn muốn khôi phục? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_message "Đã hủy khôi phục"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    # Backup dữ liệu hiện tại trước khi khôi phục
    print_message "Đang backup dữ liệu hiện tại trước khi khôi phục..."
    backup_nocodb_silent
    
    # Dừng NocoDB
    print_message "Đang dừng NocoDB..."
    cd $INSTALL_DIR
    docker-compose stop nocodb nocodb_db 2>/dev/null || true
    
    # Xóa dữ liệu cũ
    print_message "Đang xóa dữ liệu cũ..."
    rm -rf $INSTALL_DIR/nocodb.old $INSTALL_DIR/nocodb_db.old 2>/dev/null || true
    mv $INSTALL_DIR/nocodb $INSTALL_DIR/nocodb.old 2>/dev/null || true
    mv $INSTALL_DIR/nocodb_db $INSTALL_DIR/nocodb_db.old 2>/dev/null || true
    
    # Giải nén backup
    print_message "Đang khôi phục dữ liệu từ backup..."
    tar -xzf "$SELECTED_BACKUP" -C $INSTALL_DIR
    
    # Khởi động lại NocoDB
    print_message "Đang khởi động lại NocoDB..."
    docker-compose up -d nocodb_db
    sleep 10
    docker-compose up -d nocodb
    
    print_message "Đợi 30 giây để NocoDB khởi động..."
    sleep 30
    
    if docker ps | grep -q "nocodb"; then
        print_success "Khôi phục NocoDB thành công!"
        echo ""
        echo -e "${YELLOW}Dữ liệu cũ đã được lưu tại:${NC}"
        echo -e "  - $INSTALL_DIR/nocodb.old"
        echo -e "  - $INSTALL_DIR/nocodb_db.old"
    else
        print_error "Khởi động NocoDB thất bại!"
        echo ""
        echo -e "${YELLOW}Đang rollback về dữ liệu cũ...${NC}"
        docker-compose stop nocodb nocodb_db
        rm -rf $INSTALL_DIR/nocodb $INSTALL_DIR/nocodb_db
        mv $INSTALL_DIR/nocodb.old $INSTALL_DIR/nocodb
        mv $INSTALL_DIR/nocodb_db.old $INSTALL_DIR/nocodb_db
        docker-compose up -d nocodb_db nocodb
    fi
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# 9. Xem trạng thái hệ thống
show_status() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              TRẠNG THÁI HỆ THỐNG                        ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Kiểm tra Docker
    if check_docker_installed; then
        echo -e "${GREEN}✓${NC} Docker: ${GREEN}Đã cài đặt${NC}"
        docker --version
    else
        echo -e "${RED}✗${NC} Docker: ${RED}Chưa cài đặt${NC}"
    fi
    
    echo ""
    
    # Kiểm tra Nginx
    if command -v nginx &> /dev/null; then
        echo -e "${GREEN}✓${NC} Nginx: ${GREEN}Đã cài đặt${NC}"
        nginx -v 2>&1
    else
        echo -e "${RED}✗${NC} Nginx: ${RED}Chưa cài đặt${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Kiểm tra containers
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        echo ""
        echo -e "${CYAN}Trạng thái Containers:${NC}"
        echo ""
        cd $INSTALL_DIR
        docker-compose ps
        
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # Thông tin kết nối
        if [ -f "$INSTALL_DIR/n8n.env" ]; then
            echo ""
            echo -e "${CYAN}N8N:${NC}"
            source $INSTALL_DIR/n8n.env
            echo -e "  URL: ${GREEN}https://$N8N_DOMAIN${NC}"
        fi
        
        if [ -f "$INSTALL_DIR/nocodb.env" ]; then
            echo ""
            echo -e "${CYAN}NocoDB:${NC}"
            source $INSTALL_DIR/nocodb.env
            echo -e "  URL: ${GREEN}https://$NOCODB_DOMAIN${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}Chưa có service nào được cài đặt${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Disk usage
    echo ""
    echo -e "${CYAN}Dung lượng ổ cứng:${NC}"
    df -h / | tail -1
    
    if [ -d "$INSTALL_DIR" ]; then
        echo ""
        echo -e "${CYAN}Dung lượng thư mục apps:${NC}"
        du -sh $INSTALL_DIR 2>/dev/null || echo "N/A"
    fi
    
    if [ -d "$BACKUP_DIR" ]; then
        echo ""
        echo -e "${CYAN}Dung lượng backup:${NC}"
        du -sh $BACKUP_DIR 2>/dev/null || echo "N/A"
        
        N8N_BACKUPS=$(ls -1 $BACKUP_DIR/n8n-backup-*.tar.gz 2>/dev/null | wc -l)
        NOCODB_BACKUPS=$(ls -1 $BACKUP_DIR/nocodb-backup-*.tar.gz 2>/dev/null | wc -l)
        
        echo -e "  - N8N backups: ${GREEN}$N8N_BACKUPS${NC} files"
        echo -e "  - NocoDB backups: ${GREEN}$NOCODB_BACKUPS${NC} files"
    fi
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "Nhấn Enter để quay lại menu..."
}

# 10. Xem logs
show_logs() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              XEM LOGS                                    ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -f "$INSTALL_DIR/docker-compose.yml" ]; then
        print_error "Chưa có service nào được cài đặt!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    echo -e "  ${CYAN}1)${NC} Xem logs N8N (50 dòng cuối)"
    echo -e "  ${CYAN}2)${NC} Xem logs NocoDB (50 dòng cuối)"
    echo -e "  ${CYAN}3)${NC} Xem logs N8N (realtime)"
    echo -e "  ${CYAN}4)${NC} Xem logs NocoDB (realtime)"
    echo -e "  ${CYAN}5)${NC} Xem logs PostgreSQL"
    echo -e "  ${RED}0)${NC} Quay lại"
    echo ""
    
    read -p "Chọn chức năng: " choice
    
    cd $INSTALL_DIR
    
    case $choice in
        1)
            echo ""
            echo -e "${YELLOW}Logs N8N (50 dòng cuối):${NC}"
            echo ""
            docker-compose logs --tail=50 n8n
            ;;
        2)
            echo ""
            echo -e "${YELLOW}Logs NocoDB (50 dòng cuối):${NC}"
            echo ""
            docker-compose logs --tail=50 nocodb
            ;;
        3)
            echo ""
            echo -e "${YELLOW}Logs N8N (realtime - Nhấn Ctrl+C để thoát):${NC}"
            echo ""
            docker-compose logs -f n8n
            ;;
        4)
            echo ""
            echo -e "${YELLOW}Logs NocoDB (realtime - Nhấn Ctrl+C để thoát):${NC}"
            echo ""
            docker-compose logs -f nocodb
            ;;
        5)
            echo ""
            echo -e "${YELLOW}Logs PostgreSQL (50 dòng cuối):${NC}"
            echo ""
            docker-compose logs --tail=50 nocodb_db
            ;;
        0)
            return
            ;;
        *)
            print_error "Lựa chọn không hợp lệ!"
            ;;
    esac
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# Main function
main() {
    check_root
    
    while true; do
        show_main_menu
        read -p "Chọn chức năng (0-10): " choice
        
        case $choice in
            1)
                install_n8n
                ;;
            2)
                install_nocodb
                ;;
            3)
                update_n8n
                ;;
            4)
                update_nocodb
                ;;
            5)
                backup_n8n
                ;;
            6)
                backup_nocodb
                ;;
            7)
                restore_n8n
                ;;
            8)
                restore_nocodb
                ;;
            9)
                show_status
                ;;
            10)
                show_logs
                ;;
            0)
                echo ""
                print_success "Cảm ơn bạn đã sử dụng script! Tạm biệt! 👋"
                echo ""
                exit 0
                ;;
            *)
                print_error "Lựa chọn không hợp lệ!"
                sleep 2
                ;;
        esac
    done
}

# Chạy script
main" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        print_success "Sao lưu thành công!"
        echo ""
        echo -e "${GREEN}File backup:${NC} $BACKUP_FILE"
        echo -e "${GREEN}Kích thước:${NC} $BACKUP_SIZE"
        
        # Tự động xóa backup cũ hơn 30 ngày
        find $BACKUP_DIR -name "n8n-backup-*.tar.gz" -mtime +30 -delete 2>/dev/null
        
        echo ""
        echo -e "${YELLOW}Backup cũ hơn 30 ngày đã được tự động xóa${NC}"
    else
        print_error "Sao lưu thất bại!"
    fi
    
    echo ""
    read -p "Nhấn Enter để quay lại menu..."
}

# 6. Backup NocoDB (silent version)
backup_nocodb_silent() {
    mkdir -p $BACKUP_DIR
    BACKUP_FILE="$BACKUP_DIR/nocodb-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    
    if [ -d "$INSTALL_DIR/nocodb" ]; then
        cd $INSTALL_DIR
        docker-compose exec -T nocodb_db pg_dump -U nocodb nocodb > $BACKUP_DIR/nocodb-db-$(date +%Y%m%d-%H%M%S).sql 2>/dev/null || true
        tar -czf $BACKUP_FILE -C $INSTALL_DIR nocodb nocodb_db nocodb.env 2>/dev/null || true
        return 0
    fi
    return 1
}

# 6. Backup NocoDB
backup_nocodb() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              SAO LƯU DỮ LIỆU NOCODB                     ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! check_nocodb_installed; then
        print_error "NocoDB chưa được cài đặt!"
        read -p "Nhấn Enter để quay lại menu..."
        return
    fi
    
    mkdir -p $BACKUP_DIR
    BACKUP_FILE="$BACKUP_DIR/nocodb-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    DB_BACKUP="$BACKUP_DIR/nocodb-db-$(date +%Y%m%d-%H%M%S).sql"
    
    print_message "Đang sao lưu database NocoDB..."
    cd $INSTALL_DIR
    docker-compose exec -T nocodb_db pg_dump -U nocodb nocodb > $DB_BACKUP 2>/dev/null || print_warning "Không thể dump database"
    
    print_message "Đang sao lưu dữ liệu NocoDB..."
    tar -czf $BACKUP_FILE nocodb nocodb_db nocodb.env 2>/dev/null || tar -czf $BACKUP_FILE nocodb nocodb_db
    
    if [ -f "$BACKUP_FILE
