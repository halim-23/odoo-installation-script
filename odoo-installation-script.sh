#!/bin/bash

# ========================================================================================
# Odoo 18 Enterprise Provisioning Script for Ubuntu 24.04 LTS (V3 - WebSocket Enabled)
# Author: Your DevOps Expert
# Version: 3.0
#
# This script automates a full production-grade Odoo 18 Enterprise installation,
# including Nginx with WebSocket support, performance tuning, and security best practices.
# ========================================================================================

set -euo pipefail

# --- SCRIPT CONFIGURATION ---
ODOO_VERSION="18.0"
ODOO_USER="odoo18e"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_CONFIG_FILE="/etc/${ODOO_USER}.conf"

# --- Dynamic Performance Calculation ---
CPU_CORES=$(nproc)
ODOO_WORKERS=$((2 * CPU_CORES + 1))

# --- Passwords (Auto-generated) ---
PG_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWD=$(openssl rand -base64 16)

# --- Repositories ---
ODOO_COMMUNITY_REPO="https://github.com/odoo/odoo.git"

# --- User Input Variables ---
DOMAIN=""
ADMIN_EMAIL=""
ODOO_ENTERPRISE_REPO=""
CUSTOM_ADDONS_REPO=""

# --- Helper Functions ---
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
warn() { echo -e "\e[33m[WARNING]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# ========================================================================================
# --- SCRIPT LOGIC (Only the Nginx function is significantly changed) ---
# ========================================================================================

# ... (pre_run_checks, update_and_install_dependencies, etc. are identical to V2) ...
# ... (for brevity, I'm omitting the functions that have not changed) ...

pre_run_checks() {
    info "Starting pre-run checks..."
    if [ "$(id -u)" -ne 0 ]; then error "This script must be run as root."; fi
    if [ -z "$DOMAIN" ]; then read -p "Enter the domain name for Odoo: " DOMAIN; if [ -z "$DOMAIN" ]; then error "Domain name is required."; fi; fi
    if [ -z "$ADMIN_EMAIL" ]; then read -p "Enter your email for SSL cert: " ADMIN_EMAIL; if [ -z "$ADMIN_EMAIL" ]; then error "Email is required."; fi; fi
    if [ -z "$ODOO_ENTERPRISE_REPO" ]; then read -p "Enter Odoo Enterprise Git URL: " ODOO_ENTERPRISE_REPO; if [ -z "$ODOO_ENTERPRISE_REPO" ]; then error "Enterprise URL is required."; fi; fi
    if [ -z "$CUSTOM_ADDONS_REPO" ]; then read -p "Enter Custom Addons Git URL (or press Enter to skip): " CUSTOM_ADDONS_REPO; fi
    success "Pre-run checks passed."
}

update_and_install_dependencies() {
    info "Updating system and installing dependencies..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get upgrade -y
    apt-get install -y git python3 python3-pip python3-venv build-essential wget \
    libxslt-dev libzip-dev libldap2-dev libsasl2-dev libpq-dev \
    python3-dev python3-wheel node-less libjpeg-dev gdebi-core \
    postgresql nginx certbot python3-certbot-nginx
    success "System dependencies installed."
}

install_wkhtmltopdf() {
    info "Installing wkhtmltopdf..."
    if dpkg -l | grep -q wkhtmltox; then warn "wkhtmltopdf already installed."; return; fi
    wget -qO /tmp/wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
    gdebi --n /tmp/wkhtmltox.deb && rm /tmp/wkhtmltox.deb
    success "wkhtmltopdf installed."
}

setup_postgres() {
    info "Setting up PostgreSQL..."
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_USER'" | grep -q 1; then
        warn "PostgreSQL user '$ODOO_USER' already exists."
    else
        sudo -u postgres createuser -sdrP "$ODOO_USER"
        sudo -u postgres psql -c "ALTER USER $ODOO_USER WITH PASSWORD '$PG_PASSWORD';"
        success "PostgreSQL user '$ODOO_USER' created."
    fi
}

setup_odoo_user() {
    info "Creating system user '$ODOO_USER'..."
    if id -u "$ODOO_USER" &>/dev/null; then warn "System user '$ODOO_USER' already exists."; else
        useradd -m -d "$ODOO_HOME" -U -r -s /bin/bash "$ODOO_USER"
        success "System user '$ODOO_USER' created."
    fi
}

install_odoo() {
    info "Cloning Odoo repositories and setting up Python environment..."
    if [ -d "$ODOO_HOME/odoo" ]; then warn "Odoo directory exists, skipping clone."; return; fi
    sudo -u "$ODOO_USER" bash <<EOF
set -e
cd "$ODOO_HOME"
git clone --depth 1 --branch "$ODOO_VERSION" "$ODOO_COMMUNITY_REPO" odoo
git clone --depth 1 --branch "$ODOO_VERSION" "$ODOO_ENTERPRISE_REPO" enterprise
if [ -n "$CUSTOM_ADDONS_REPO" ]; then git clone --depth 1 "$CUSTOM_ADDONS_REPO" custom_addons; else mkdir custom_addons; fi
python3 -m venv venv && source venv/bin/activate && pip3 install wheel && pip3 install -r odoo/requirements.txt && deactivate
EOF
    success "Odoo source code and Python environment are ready."
}

create_odoo_config() {
    info "Creating Odoo configuration file with performance tuning..."
    local ADDONS_PATH="$ODOO_HOME/enterprise,$ODOO_HOME/custom_addons,$ODOO_HOME/odoo/addons"
    cat > "$ODOO_CONFIG_FILE" <<EOF
[options]
admin_passwd = ${ADMIN_PASSWD}
db_host = False
db_port = False
db_user = ${ODOO_USER}
db_password = ${PG_PASSWORD}
addons_path = ${ADDONS_PATH}
xmlrpc_port = 8069
longpolling_port = 8072
proxy_mode = True
workers = ${ODOO_WORKERS}
limit_time_cpu = 600
limit_time_real = 1200
logfile = /var/log/${ODOO_USER}/odoo.log
log_level = info
EOF
    mkdir -p "/var/log/${ODOO_USER}"
    chown -R "$ODOO_USER":"$ODOO_USER" "/var/log/${ODOO_USER}"
    chown "$ODOO_USER":"$ODOO_USER" "$ODOO_CONFIG_FILE"
    chmod 640 "$ODOO_CONFIG_FILE"
    success "Odoo configuration file created with ${ODOO_WORKERS} workers."
}

create_systemd_service() {
    info "Creating systemd service for Odoo..."
    cat > "/etc/systemd/system/${ODOO_USER}.service" <<EOF
[Unit]
Description=Odoo 18 Enterprise (Tuned, WebSocket)
Requires=postgresql.service
After=network.target postgresql.service
[Service]
Type=simple
SyslogIdentifier=${ODOO_USER}
User=${ODOO_USER}
Group=${ODOO_USER}
ExecStart=${ODOO_HOME}/venv/bin/python3 ${ODOO_HOME}/odoo/odoo-bin -c ${ODOO_CONFIG_FILE}
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now "${ODOO_USER}.service"
    success "Odoo service created and started."
}

# --- THIS FUNCTION IS FULLY UPDATED FOR WEBSOCKETS ---
setup_nginx_and_ssl() {
    info "Configuring Nginx with WebSocket support and obtaining SSL..."

    # Create the main Nginx site configuration
    cat > "/etc/nginx/sites-available/${DOMAIN}" <<EOF
# Odoo upstream for main requests
upstream odoo {
    server 127.0.0.1:8069;
}

# Odoo upstream for real-time (WebSocket/Longpolling)
upstream odoochat {
    server 127.0.0.1:8072;
}

# Map for WebSocket upgrade
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

# HTTP server to redirect to HTTPS
server {
    listen 80;
    server_name ${DOMAIN};

    # Let Certbot handle the redirection
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    # SSL settings will be added by Certbot
    # ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    # Standard security headers and proxy settings
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    client_max_body_size 512m;

    access_log /var/log/nginx/odoo.access.log;
    error_log /var/log/nginx/odoo.error.log;

    # WebSocket location (preferred method)
    location /websocket {
        proxy_pass http://odoochat;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Longpolling location (fallback method)
    location /longpolling {
        proxy_pass http://odoochat;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Main Odoo requests
    location / {
        proxy_pass http://odoo;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Cache static assets
    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odoo;
    }
}
EOF

    ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t # Test configuration

    # Obtain SSL certificate
    certbot --nginx --agree-tos --redirect --hsts --staple-ocsp --email "$ADMIN_EMAIL" -d "$DOMAIN"
    
    systemctl restart nginx
    success "Nginx with WebSocket support configured and SSL certificate installed."
}

setup_firewall() {
    info "Configuring firewall..."
    ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable
    success "Firewall enabled."
}

final_summary() {
    # This function is the same, just updated text
    echo
    success "Odoo 18 Enterprise (WebSocket Enabled) provisioning is complete!"
    echo -e "\n\e[1m==================== Odoo Instance Details ====================\e[0m"
    echo -e "URL:                 \e[32mhttps://${DOMAIN}\e[0m"
    echo -e "Real-time Protocol:  \e[32mWebSocket (with Longpolling fallback)\e[0m"
    echo -e "CPU Cores Detected:    \e[36m${CPU_CORES}\e[0m"
    echo -e "Odoo Workers Set:      \e[36m${ODOO_WORKERS}\e[0m"
    echo -e "Odoo Master Admin PW:  \e[33m${ADMIN_PASSWD}\e[0m"
    echo -e "PostgreSQL Password:   \e[33m${PG_PASSWORD}\e[0m"
    echo -e "\nTo restart Odoo: \e[3m'sudo systemctl restart ${ODOO_USER}'\e[0m"
    echo -e "\e[1m=============================================================\e[0m\n"
    warn "IMPORTANT: Save the generated passwords securely!"
}

# --- Main Execution ---
main() {
    pre_run_checks
    update_and_install_dependencies
    install_wkhtmltopdf
    setup_postgres
    setup_odoo_user
    install_odoo
    create_odoo_config
    create_systemd_service
    setup_nginx_and_ssl
    setup_firewall
    final_summary
}

main "$@"
