#!/bin/bash

# N8N Auto Installation Script for Ubuntu with Docker
# Compatible with existing NocoDB installation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="n8n.modaviet.vn"
N8N_DIR="/opt/n8n"
ADMIN_USER="admin"
EMAIL="your-email@domain.com"  # Change this to your email

# Generate random passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-12)
ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is available
    if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Determine compose command
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    
    print_success "Prerequisites check passed"
}

# Check port conflicts
check_ports() {
    print_status "Checking for port conflicts..."
    
    PORTS_TO_CHECK=(5678 5433)
    
    for port in "${PORTS_TO_CHECK[@]}"; do
        if sudo netstat -tlnp | grep ":$port " > /dev/null; then
            print_error "Port $port is already in use. Please free this port before continuing."
            sudo netstat -tlnp | grep ":$port "
            exit 1
        fi
    done
    
    print_success "No port conflicts detected"
}

# Install Nginx if not present
install_nginx() {
    if ! command -v nginx &> /dev/null; then
        print_status "Installing Nginx..."
        sudo apt update
        sudo apt install -y nginx
        sudo systemctl enable nginx
        sudo systemctl start nginx
        print_success "Nginx installed successfully"
    else
        print_status "Nginx is already installed"
    fi
}

# Install Certbot if not present
install_certbot() {
    if ! command -v certbot &> /dev/null; then
        print_status "Installing Certbot..."
        sudo apt update
        sudo apt install -y certbot python3-certbot-nginx
        print_success "Certbot installed successfully"
    else
        print_status "Certbot is already installed"
    fi
}

# Create N8N directory structure
create_directories() {
    print_status "Creating directory structure..."
    
    sudo mkdir -p $N8N_DIR/{data,postgres-data}
    sudo chown -R $USER:$USER $N8N_DIR
    cd $N8N_DIR
    
    print_success "Directory structure created"
}

# Generate .env file
create_env_file() {
    print_status "Creating environment file..."
    
    cat > $N8N_DIR/.env << EOF
# PostgreSQL Configuration
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_DB_PASSWORD=$POSTGRES_PASSWORD

# N8N Admin Configuration
N8N_BASIC_AUTH_USER=$ADMIN_USER
N8N_BASIC_AUTH_PASSWORD=$ADMIN_PASSWORD

# N8N Encryption Key (32 characters)
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY

# Domain
DOMAIN=$DOMAIN
EOF
    
    chmod 600 $N8N_DIR/.env
    print_success "Environment file created"
}

# Create docker-compose.yml
create_docker_compose() {
    print_status "Creating Docker Compose configuration..."
    
    cat > $N8N_DIR/docker-compose.yml << 'EOF'
version: '3.8'

services:
  n8n-postgres:
    image: postgres:15
    restart: unless-stopped
    container_name: n8n-postgres
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    networks:
      - n8n-network
    ports:
      - "5433:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    container_name: n8n
    environment:
      # Database
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: n8n-postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: n8n
      DB_POSTGRESDB_USER: n8n
      DB_POSTGRESDB_PASSWORD: ${N8N_DB_PASSWORD}
      
      # N8N Configuration
      N8N_HOST: ${DOMAIN}
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: https://${DOMAIN}/
      
      # Security
      N8N_BASIC_AUTH_ACTIVE: true
      N8N_BASIC_AUTH_USER: ${N8N_BASIC_AUTH_USER}
      N8N_BASIC_AUTH_PASSWORD: ${N8N_BASIC_AUTH_PASSWORD}
      
      # Timezone
      GENERIC_TIMEZONE: Asia/Ho_Chi_Minh
      TZ: Asia/Ho_Chi_Minh
      
      # Encryption key
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      
      # Additional settings
      N8N_METRICS: false
      N8N_LOG_LEVEL: info
      
    ports:
      - "5678:5678"
    volumes:
      - ./data:/home/node/.n8n
    depends_on:
      n8n-postgres:
        condition: service_healthy
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  n8n-network:
    driver: bridge
EOF
    
    print_success "Docker Compose configuration created"
}

# Create Nginx configuration
create_nginx_config() {
    print_status "Creating Nginx configuration..."
    
    sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    # SSL Configuration (will be updated by Certbot)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA;
    ssl_prefer_server_ciphers on;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Maximum file upload size
    client_max_body_size 100M;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }
    
    # Health check endpoint
    location /healthz {
        proxy_pass http://localhost:5678/healthz;
        proxy_set_header Host \$host;
        access_log off;
    }
}
EOF
    
    # Enable the site
    sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    if sudo nginx -t; then
        print_success "Nginx configuration created successfully"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
}

# Start N8N services
start_n8n() {
    print_status "Starting N8N services..."
    
    cd $N8N_DIR
    
    # Set proper ownership
    sudo chown -R 1000:1000 data postgres-data
    
    # Pull images
    $COMPOSE_CMD pull
    
    # Start services
    $COMPOSE_CMD up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to start..."
    sleep 30
    
    # Check if services are running
    if $COMPOSE_CMD ps | grep -q "Up"; then
        print_success "N8N services started successfully"
    else
        print_error "Failed to start N8N services"
        $COMPOSE_CMD logs
        exit 1
    fi
}

# Configure SSL with Let's Encrypt
configure_ssl() {
    print_status "Configuring SSL with Let's Encrypt..."
    
    # Reload Nginx
    sudo systemctl reload nginx
    
    # Get SSL certificate
    print_warning "Please make sure your domain $DOMAIN points to this server's IP address"
    read -p "Press Enter when ready to continue with SSL configuration..."
    
    if sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL --redirect; then
        print_success "SSL certificate configured successfully"
    else
        print_warning "SSL configuration failed, but N8N is still accessible via HTTP"
        print_warning "You can manually configure SSL later with: sudo certbot --nginx -d $DOMAIN"
    fi
}

# Create maintenance script
create_maintenance_script() {
    print_status "Creating maintenance script..."
    
    cat > $N8N_DIR/n8n-maintenance.sh << 'EOF'
#!/bin/bash

# N8N Maintenance Script
BACKUP_DIR="/opt/backups/n8n"
N8N_DIR="/opt/n8n"
DATE=$(date +%Y%m%d_%H%M%S)

# Determine compose command
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

# Create backup directory
mkdir -p $BACKUP_DIR

backup_n8n() {
    echo "=== Backup N8N ==="
    cd $N8N_DIR
    
    # Backup database
    $COMPOSE_CMD exec -T n8n-postgres pg_dump -U n8n n8n > "$BACKUP_DIR/n8n_db_$DATE.sql"
    
    # Backup data directory
    tar -czf "$BACKUP_DIR/n8n_data_$DATE.tar.gz" data/
    
    # Backup configuration files
    cp docker-compose.yml "$BACKUP_DIR/docker-compose_$DATE.yml"
    cp .env "$BACKUP_DIR/env_$DATE"
    
    echo "Backup completed: $BACKUP_DIR"
}

update_n8n() {
    echo "=== Update N8N ==="
    cd $N8N_DIR
    
    # Create backup before update
    backup_n8n
    
    # Pull latest images
    $COMPOSE_CMD pull
    
    # Restart services
    $COMPOSE_CMD down
    $COMPOSE_CMD up -d
    
    echo "N8N updated successfully"
}

restart_n8n() {
    echo "=== Restart N8N ==="
    cd $N8N_DIR
    $COMPOSE_CMD restart
    echo "N8N restarted successfully"
}

check_health() {
    echo "=== Health Check ==="
    cd $N8N_DIR
    
    # Check containers
    echo "Container status:"
    $COMPOSE_CMD ps
    
    echo -e "\nN8N HTTP Status:"
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5678/healthz
    
    echo -e "\nDisk usage:"
    df -h $N8N_DIR
    
    echo -e "\nRecent logs:"
    $COMPOSE_CMD logs --tail=10 n8n
}

show_logs() {
    cd $N8N_DIR
    $COMPOSE_CMD logs -f "${2:-n8n}"
}

cleanup_backups() {
    echo "=== Cleanup Old Backups ==="
    find $BACKUP_DIR -name "n8n_*" -type f -mtime +7 -delete
    echo "Old backups cleaned up (kept last 7 days)"
}

case "$1" in
    backup)
        backup_n8n
        ;;
    update)
        update_n8n
        ;;
    restart)
        restart_n8n
        ;;
    health)
        check_health
        ;;
    logs)
        show_logs $@
        ;;
    cleanup)
        cleanup_backups
        ;;
    *)
        echo "Usage: $0 {backup|update|restart|health|logs|cleanup}"
        echo ""
        echo "  backup  - Create backup of N8N data and database"
        echo "  update  - Update N8N to latest version"
        echo "  restart - Restart N8N services"
        echo "  health  - Check N8N health status"
        echo "  logs    - Show N8N logs (add service name for specific service)"
        echo "  cleanup - Remove old backups"
        exit 1
        ;;
esac
EOF
    
    chmod +x $N8N_DIR/n8n-maintenance.sh
    print_success "Maintenance script created at $N8N_DIR/n8n-maintenance.sh"
}

# Display final information
show_final_info() {
    print_success "N8N installation completed successfully!"
    echo ""
    echo "=== Access Information ==="
    echo "URL: https://$DOMAIN"
    echo "Username: $ADMIN_USER"
    echo "Password: $ADMIN_PASSWORD"
    echo ""
    echo "=== File Locations ==="
    echo "Installation directory: $N8N_DIR"
    echo "Data directory: $N8N_DIR/data"
    echo "Database data: $N8N_DIR/postgres-data"
    echo "Configuration: $N8N_DIR/.env"
    echo "Maintenance script: $N8N_DIR/n8n-maintenance.sh"
    echo ""
    echo "=== Useful Commands ==="
    echo "Check status: cd $N8N_DIR && $COMPOSE_CMD ps"
    echo "View logs: cd $N8N_DIR && $COMPOSE_CMD logs -f"
    echo "Restart: cd $N8N_DIR && $COMPOSE_CMD restart"
    echo "Maintenance: $N8N_DIR/n8n-maintenance.sh health"
    echo ""
    echo "=== Important Notes ==="
    echo "1. Please save the login credentials shown above"
    echo "2. Database passwords are in $N8N_DIR/.env"
    echo "3. Regular backups can be created with: $N8N_DIR/n8n-maintenance.sh backup"
    echo "4. SSL certificate will auto-renew via certbot"
    echo ""
    print_warning "Please ensure your domain $DOMAIN points to this server's IP address"
}

# Main execution
main() {
    echo "================================================================"
    echo "           N8N Auto Installation Script"
    echo "         Compatible with existing NocoDB"
    echo "================================================================"
    echo ""
    
    # Prompt for email
    read -p "Enter your email for SSL certificate (default: $EMAIL): " input_email
    if [[ ! -z "$input_email" ]]; then
        EMAIL="$input_email"
    fi
    
    # Prompt for domain confirmation
    read -p "Confirm domain name (default: $DOMAIN): " input_domain
    if [[ ! -z "$input_domain" ]]; then
        DOMAIN="$input_domain"
    fi
    
    print_status "Starting N8N installation for domain: $DOMAIN"
    
    check_root
    check_prerequisites
    check_ports
    install_nginx
    install_certbot
    create_directories
    create_env_file
    create_docker_compose
    create_nginx_config
    start_n8n
    configure_ssl
    create_maintenance_script
    show_final_info
    
    print_success "Installation completed! N8N should now be accessible at https://$DOMAIN"
}

# Run main function
main "$@"
