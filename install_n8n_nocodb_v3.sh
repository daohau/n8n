#!/bin/bash

# Script tự động cài đặt & quản lý N8N + NocoDB trên Ubuntu
# Phiên bản: 3.1 (Sửa lỗi khởi động lại sau khi dừng)
# Tác giả: Dựa trên script gốc và được nâng cấp bởi Gemini

set -e

# --- CẤU HÌNH ---
INSTALL_DIR="/root/apps" # Thư mục cài đặt chính

# --- MÀU SẮC & HÀM HỖ TRỢ ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }

check_error() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        exit 1
    fi
}

# --- CÁC HÀM QUẢN LÝ ---

# Hàm kiểm tra DNS
check_dns() {
    local DOMAIN=$1
    print_message "Đang kiểm tra DNS cho domain: $DOMAIN..."
    local SERVER_IP
    SERVER_IP=$(curl -s ifconfig.me)
    local DOMAIN_IP
    DOMAIN_IP=$(dig +short "$DOMAIN")

    if [ -z "$DOMAIN_IP" ]; then
        print_error "Không thể phân giải IP cho domain $DOMAIN. Vui lòng kiểm tra lại cấu hình DNS."
        return 1
    fi

    if [ "$SERVER_IP" == "$DOMAIN_IP" ]; then
        print_success "DNS cho $DOMAIN đã trỏ về đúng IP server ($SERVER_IP)."
        return 0
    else
        print_error "DNS cho $DOMAIN chưa trỏ về đúng IP server."
        echo "IP Server hiện tại : $SERVER_IP"
        echo "IP của domain     : $DOMAIN_IP"
        return 1
    fi
}

# Hàm backup dữ liệu
backup_data() {
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "Thư mục cài đặt $INSTALL_DIR không tồn tại. Không thể backup."
        exit 1
    fi
    cd "$INSTALL_DIR"

    print_message "Bắt đầu quá trình backup..."
    BACKUP_FILE="backup-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
    
    print_message "Tạm dừng các services để đảm bảo toàn vẹn dữ liệu..."
    docker-compose down
    
    print_message "Nén dữ liệu vào file: $BACKUP_FILE..."
    tar -czf "$BACKUP_FILE" n8n nocodb nocodb_db .env docker-compose.yml
    
    print_message "Khởi động lại các services..."
    docker-compose up -d
    
    print_success "Backup hoàn tất! File đã được lưu tại: $INSTALL_DIR/$BACKUP_FILE"
}

# Hàm restore dữ liệu
restore_data() {
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
    fi
    cd "$INSTALL_DIR"

    read -p "Nhập đường dẫn đầy đủ đến file backup (VD: $INSTALL_DIR/backup-YYYY-MM-DD.tar.gz): " BACKUP_FILE
    if [ ! -f "$BACKUP_FILE" ]; then
        print_error "File backup không tồn tại!"
        exit 1
    fi

    print_warning "CẢNH BÁO: Thao tác này sẽ ghi đè toàn bộ dữ liệu hiện tại trong $INSTALL_DIR."
    read -p "Bạn có chắc chắn muốn tiếp tục? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "Đã hủy thao tác restore."
        exit 1
    fi

    print_message "Dừng các services nếu đang chạy..."
    docker-compose down --volumes > /dev/null 2>&1 || true # Ignore error if not running
    
    print_message "Xóa dữ liệu cũ (nếu có)..."
    rm -rf n8n nocodb nocodb_db .env docker-compose.yml
    
    print_message "Giải nén file backup..."
    tar -xzf "$BACKUP_FILE"
    check_error "Giải nén file backup thất bại."
    
    print_message "Phân quyền lại cho N8N..."
    chown -R 1000:1000 ./n8n
    
    print_message "Khởi động lại các services từ backup..."
    docker-compose up -d
    
    print_success "Restore hoàn tất!"
    docker-compose ps
}

# Hàm gỡ cài đặt
uninstall() {
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "Thư mục cài đặt $INSTALL_DIR không tồn tại. Không có gì để gỡ bỏ."
        exit 1
    fi

    print_warning "CẢNH BÁO: Thao tác này sẽ XÓA TOÀN BỘ containers, volumes (dữ liệu), cấu hình Nginx và SSL."
    read -p "Bạn có chắc chắn muốn gỡ cài đặt? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "Đã hủy gỡ cài đặt."
        exit 1
    fi

    cd "$INSTALL_DIR"
    
    # Lấy domain từ file .env
    # shellcheck source=.env
    source .env
    
    print_message "Dừng và xóa các containers, volumes, networks..."
    docker-compose down --volumes
    
    print_message "Xóa cấu hình Nginx..."
    rm -f /etc/nginx/sites-available/"$N8N_DOMAIN"
    rm -f /etc/nginx/sites-enabled/"$N8N_DOMAIN"
    rm -f /etc/nginx/sites-available/"$NOCODB_DOMAIN"
    rm -f /etc/nginx/sites-enabled/"$NOCODB_DOMAIN"
    
    print_message "Reload Nginx..."
    systemctl reload nginx
    
    print_message "Thu hồi SSL certificates..."
    certbot delete --cert-name "$N8N_DOMAIN" --non-interactive || print_warning "Không thể xóa SSL cho $N8N_DOMAIN (có thể đã bị xóa trước đó)."
    certbot delete --cert-name "$NOCODB_DOMAIN" --non-interactive || print_warning "Không thể xóa SSL cho $NOCODB_DOMAIN (có thể đã bị xóa trước đó)."

    print_message "Xóa thư mục cài đặt: $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
    
    print_success "Gỡ cài đặt hoàn tất!"
}


# Hàm hiển thị menu quản lý
show_management_menu() {
    if [ ! -d "$INSTALL_DIR" ]; then
        print_error "Thư mục cài đặt $INSTALL_DIR không tồn tại. Vui lòng cài đặt trước."
        exit 1
    fi
    cd "$INSTALL_DIR"

    while true; do
        echo ""
        print_success "MENU QUẢN LÝ N8N & NOCODB"
        echo "──────────────────────────────────────────"
        echo " 1. Xem trạng thái các services"
        echo " 2. Xem logs N8N (realtime)"
        echo " 3. Xem logs NocoDB (realtime)"
        echo " 4. Khởi động / Khởi động lại tất cả services"
        echo " 5. Dừng và XÓA tất cả services"
        echo " 6. Cập nhật (pull images mới và khởi động lại)"
        echo " 7. Backup dữ liệu"
        echo " 8. Restore từ backup"
        echo " 9. Gỡ cài đặt toàn bộ"
        echo " 0. Thoát"
        echo "──────────────────────────────────────────"
        read -p "Lựa chọn của bạn [0-9]: " choice

        case $choice in
            1) print_message "Trạng thái các services:"; docker-compose ps ;;
            2) docker-compose logs -f n8n ;;
            3) docker-compose logs -f nocodb ;;
            4) print_message "Khởi động lại tất cả..."; docker-compose up -d; print_success "Hoàn tất!";; # <<< ĐÂY LÀ THAY ĐỔI
            5) print_message "Dừng và xóa tất cả..."; docker-compose down; print_success "Hoàn tất!";;
            6) 
                print_message "Đang cập nhật các container..."
                docker-compose pull
                docker-compose up -d
                print_success "Cập nhật hoàn tất!"
                ;;
            7) backup_data ;;
            8) restore_data ;;
            9) uninstall; exit 0 ;;
            0) exit 0 ;;
            *) print_error "Lựa chọn không hợp lệ." ;;
        esac
    done
}

# --- HÀM CÀI ĐẶT CHÍNH ---
run_install() {
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
    echo "║  SCRIPT CÀI ĐẶT & QUẢN LÝ N8N + NOCODB (V3.1 TOÀN DIỆN)    ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    # Thu thập thông tin từ người dùng
    print_message "Vui lòng nhập các thông tin cần thiết:"
    read -p "Nhập domain cho N8N (VD: n8n.modaviet.pro.vn): " N8N_DOMAIN
    read -p "Nhập domain cho NocoDB (VD: noco.modaviet.pro.vn): " NOCODB_DOMAIN
    read -p "Nhập email để đăng ký SSL (VD: admin@modaviet.pro.vn): " SSL_EMAIL
    echo ""
    read -p "Nhập mật khẩu cho PostgreSQL Database: " -s POSTGRES_PASSWORD
    echo ""
    read -p "Nhập JWT Secret cho NocoDB (hoặc để trống để tự động tạo): " JWT_SECRET
    echo ""

    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(openssl rand -base64 32)
        print_message "JWT Secret đã được tạo tự động"
    fi
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    print_message "N8N Encryption Key đã được tạo tự động"

    # Xác nhận thông tin
    echo ""
    print_warning "Xác nhận thông tin:"
    echo "N8N Domain       : $N8N_DOMAIN"
    echo "NocoDB Domain    : $NOCODB_DOMAIN"
    echo "SSL Email        : $SSL_EMAIL"
    echo "Postgres Password: [ĐÃ GIẤU]"
    read -p "Thông tin có chính xác không? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_error "Đã hủy cài đặt"; exit 1
    fi

    print_success "Bắt đầu quá trình cài đặt..."
    sleep 2

    # Bước 1: Cập nhật & Cài đặt gói cần thiết
    print_message "Bước 1/9: Cập nhật hệ thống và cài đặt gói cần thiết..."
    apt update && apt upgrade -y
    apt install -y apt-transport-https ca-certificates curl software-properties-common ufw nginx certbot python3-certbot-nginx dnsutils
    check_error "Cài đặt các gói cần thiết thất bại"

    # Bước 2: Cài đặt Docker
    print_message "Bước 2/9: Cài đặt Docker..."
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
        apt install -y docker-ce docker-ce-cli containerd.io
        systemctl start docker && systemctl enable docker
        check_error "Cài đặt Docker thất bại"
    else
        print_warning "Docker đã được cài đặt, bỏ qua."
    fi

    # Bước 3: Cài đặt Docker Compose
    print_message "Bước 3/9: Cài đặt Docker Compose..."
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        check_error "Cài đặt Docker Compose thất bại"
    else
        print_warning "Docker Compose đã được cài đặt, bỏ qua."
    fi

    # Bước 4: Tạo cấu trúc thư mục
    print_message "Bước 4/9: Tạo cấu trúc thư mục và phân quyền..."
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "Phát hiện thư mục cũ, đang backup..."
        mv "$INSTALL_DIR" "$INSTALL_DIR.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    mkdir -p "$INSTALL_DIR"/{n8n,nocodb,nocodb_db}
    chown -R 1000:1000 "$INSTALL_DIR/n8n"
    chmod -R 755 "$INSTALL_DIR/n8n"

    # Bước 5: Tạo file cấu hình
    print_message "Bước 5/9: Tạo file .env và docker-compose.yml..."
    # Tạo file .env
    cat > "$INSTALL_DIR/.env" << EOF
# Configuration for N8N and NocoDB - Generated on $(date)
GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
N8N_DOMAIN=$N8N_DOMAIN
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
NOCODB_DOMAIN=$NOCODB_DOMAIN
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
POSTGRES_USER=nocodb
POSTGRES_DB=nocodb
EOF

    # Tạo file docker-compose.yml
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - N8N_HOST=\${N8N_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://\${N8N_DOMAIN}/
      - GENERIC_TIMEZONE=\${GENERIC_TIMEZONE}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
    volumes:
      - ./n8n:/home/node/.n8n
    networks:
      - app-network
    user: "1000:1000"

  nocodb:
    image: nocodb/nocodb:latest
    container_name: nocodb
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    environment:
      - NC_DB=pg://nocodb_db:5432?u=\${POSTGRES_USER}&p=\${POSTGRES_PASSWORD}&d=\${POSTGRES_DB}
      - NC_AUTH_JWT_SECRET=\${JWT_SECRET}
      - NC_PUBLIC_URL=https://\${NOCODB_DOMAIN}
      - NC_DISABLE_TELE=true
    volumes:
      - ./nocodb:/usr/app/data
    depends_on:
      - nocodb_db
    networks:
      - app-network

  nocodb_db:
    image: postgres:14-alpine
    container_name: nocodb_db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - ./nocodb_db:/var/lib/postgresql/data
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
EOF

    # Bước 6: Khởi động Docker containers
    print_message "Bước 6/9: Khởi động Docker containers..."
    cd "$INSTALL_DIR"
    docker-compose up -d
    check_error "Khởi động Docker containers thất bại"
    print_message "Đợi 45 giây để containers khởi động hoàn toàn..."
    sleep 45

    # Bước 7: Cấu hình Nginx
    print_message "Bước 7/9: Cấu hình Nginx..."
    # N8N
    cat > /etc/nginx/sites-available/"$N8N_DOMAIN" << EOF
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
    }
}
EOF
    # NocoDB
    cat > /etc/nginx/sites-available/"$NOCODB_DOMAIN" << EOF
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
    }
}
EOF
    ln -sf /etc/nginx/sites-available/"$N8N_DOMAIN" /etc/nginx/sites-enabled/
    ln -sf /etc/nginx/sites-available/"$NOCODB_DOMAIN" /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl restart nginx
    check_error "Cấu hình hoặc khởi động lại Nginx thất bại"

    # Bước 8: Cài đặt SSL
    print_message "Bước 8/9: Kiểm tra DNS và cài đặt SSL..."
    if check_dns "$N8N_DOMAIN"; then
        certbot --nginx -d "$N8N_DOMAIN" --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect
        [ $? -eq 0 ] && print_success "SSL cho N8N đã được cài đặt" || print_warning "Cài SSL cho N8N thất bại."
    else
        print_warning "Bỏ qua cài đặt SSL cho $N8N_DOMAIN do lỗi DNS."
    fi

    if check_dns "$NOCODB_DOMAIN"; then
        certbot --nginx -d "$NOCODB_DOMAIN" --non-interactive --agree-tos --email "$SSL_EMAIL" --redirect
        [ $? -eq 0 ] && print_success "SSL cho NocoDB đã được cài đặt" || print_warning "Cài SSL cho NocoDB thất bại."
    else
        print_warning "Bỏ qua cài đặt SSL cho $NOCODB_DOMAIN do lỗi DNS."
    fi

    # Bước 9: Firewall & Hoàn tất
    print_message "Bước 9/9: Cấu hình Firewall và hoàn tất..."
    ufw --force enable
    ufw allow 'Nginx Full'
    ufw allow OpenSSH

    # Tạo file thông tin
    cat > "$INSTALL_DIR/installation-info.txt" << EOF
THÔNG TIN CÀI ĐẶT N8N + NOCODB (Generated on $(date))
────────────────────────────────────────────────────────────
URL TRUY CẬP:
- N8N: https://$N8N_DOMAIN
- NocoDB: https://$NOCODB_DOMAIN

THÔNG TIN QUAN TRỌNG:
- Tất cả cấu hình được lưu tại: $INSTALL_DIR/.env
- Hãy backup file .env và các thư mục dữ liệu cẩn thận!

LỆNH QUẢN LÝ:
- Chạy script với lệnh 'manage' để vào menu quản lý:
  bash $0 manage
────────────────────────────────────────────────────────────
EOF
    
    # Final success message
    clear
    print_success "CÀI ĐẶT HOÀN TẤT!"
    echo "────────────────────────────────────────────────────────────"
    echo -e "N8N        : ${YELLOW}https://$N8N_DOMAIN${NC}"
    echo -e "NocoDB     : ${YELLOW}https://$NOCODB_DOMAIN${NC}"
    echo ""
    echo -e "Thông tin chi tiết đã được lưu tại: ${YELLOW}$INSTALL_DIR/installation-info.txt${NC}"
    echo -e "Để quản lý (backup, xem logs, cập nhật...), hãy chạy lại script này với lệnh:"
    echo -e "${YELLOW}bash $0 manage${NC}"
    echo "────────────────────────────────────────────────────────────"
    cd "$INSTALL_DIR" && docker-compose ps
}


# --- LOGIC CHÍNH CỦA SCRIPT ---

case "$1" in
    install)
        run_install
        ;;
    manage)
        show_management_menu
        ;;
    backup)
        backup_data
        ;;
    restore)
        restore_data
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Sử dụng:"
        echo "  $0 install    - Để bắt đầu cài đặt mới."
        echo "  $0 manage     - Để mở menu quản lý tương tác."
        echo "  $0 backup     - Để tạo bản backup nhanh."
        echo "  $0 restore    - Để phục hồi từ một bản backup."
        echo "  $0 uninstall  - Để gỡ cài đặt toàn bộ."
        echo ""
        # Mặc định chạy cài đặt nếu không có tham số
        if [ -z "$1" ]; then
            run_install
        fi
        ;;
esac

exit 0
