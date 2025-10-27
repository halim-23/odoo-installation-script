#!/bin/bash

# ========================================================================================
# Odoo Complete Uninstallation Script
# Version: 1.0
#
# This script completely removes Odoo installation including:
# - Odoo service and files
# - Odoo system user and home directory
# - PostgreSQL odoo user and databases
# - Nginx configuration
# - SSL certificates (optional)
# - Dependencies (optional)
# - Firewall rules
# ========================================================================================

set -euo pipefail

# --- SCRIPT CONFIGURATION ---
ODOO_USER="odoo"
ODOO_HOME="/opt/$ODOO_USER"
ODOO_CONFIG_FILE="/etc/${ODOO_USER}.conf"
ODOO_SERVICE="/etc/systemd/system/${ODOO_USER}.service"
ODOO_LOG_DIR="/var/log/${ODOO_USER}"

# --- Color Helper Functions ---
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
success() { echo -e "\e[32m[SUCCESS]\e[0m $1"; }
warn() { echo -e "\e[33m[WARNING]\e[0m $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; }

# --- Confirmation Prompt ---
confirm_uninstall() {
    echo
    warn "╔════════════════════════════════════════════════════════════════╗"
    warn "║           ODOO COMPLETE UNINSTALLATION SCRIPT                  ║"
    warn "╚════════════════════════════════════════════════════════════════╝"
    echo
    warn "This script will PERMANENTLY REMOVE:"
    echo "  ✗ Odoo service and systemd configuration"
    echo "  ✗ Odoo user and home directory ($ODOO_HOME)"
    echo "  ✗ All Odoo files, addons, and configurations"
    echo "  ✗ PostgreSQL 'odoo' user and ALL Odoo databases"
    echo "  ✗ Nginx Odoo configuration files"
    echo "  ✗ Odoo log files"
    echo "  ✗ SSL certificates (optional)"
    echo "  ✗ System dependencies (optional)"
    echo
    warn "THIS ACTION CANNOT BE UNDONE!"
    echo
    read -p "Are you absolutely sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Uninstallation cancelled."
        exit 0
    fi
    
    read -p "Type 'DELETE' in capital letters to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        info "Uninstallation cancelled."
        exit 0
    fi
    
    success "Confirmation received. Starting uninstallation..."
    echo
}

# --- Pre-run Checks ---
pre_run_checks() {
    info "Running pre-run checks..."
    if [ "$(id -u)" -ne 0 ]; then 
        error "This script must be run as root or with sudo."
        exit 1
    fi
    success "Pre-run checks passed."
}

# --- Stop Odoo Service ---
stop_odoo_service() {
    info "Stopping Odoo service..."
    if systemctl is-active --quiet "${ODOO_USER}.service" 2>/dev/null; then
        systemctl stop "${ODOO_USER}.service"
        success "Odoo service stopped."
    else
        warn "Odoo service is not running or does not exist."
    fi
}

# --- Disable and Remove Systemd Service ---
remove_systemd_service() {
    info "Removing systemd service..."
    if [ -f "$ODOO_SERVICE" ]; then
        systemctl disable "${ODOO_USER}.service" 2>/dev/null || true
        rm -f "$ODOO_SERVICE"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        success "Systemd service removed."
    else
        warn "Systemd service file not found."
    fi
}

# --- Remove PostgreSQL User and Databases ---
remove_postgres_data() {
    info "Removing PostgreSQL odoo user and databases..."
    
    if ! command -v psql &> /dev/null; then
        warn "PostgreSQL is not installed. Skipping database cleanup."
        return
    fi
    
    if ! systemctl is-active --quiet postgresql 2>/dev/null; then
        warn "PostgreSQL service is not running. Skipping database cleanup."
        return
    fi
    
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_USER'" | grep -q 1; then
        info "Dropping all databases owned by '$ODOO_USER'..."
        DATABASES=$(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datdba=(SELECT oid FROM pg_roles WHERE rolname='$ODOO_USER')")
        
        if [ -n "$DATABASES" ]; then
            while IFS= read -r db; do
                if [ -n "$db" ]; then
                    info "Dropping database: $db"
                    sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$db\";" 2>/dev/null || warn "Failed to drop database: $db"
                fi
            done <<< "$DATABASES"
        fi
        
        info "Searching for additional Odoo databases..."
        ALL_DBS=$(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1')")
        
        if [ -n "$ALL_DBS" ]; then
            echo "Found the following databases:"
            echo "$ALL_DBS"
            read -p "Do you want to remove ALL these databases? (yes/no): " -r
            if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                while IFS= read -r db; do
                    if [ -n "$db" ]; then
                        info "Dropping database: $db"
                        sudo -u postgres psql -c "DROP DATABASE IF EXISTS \"$db\";" 2>/dev/null || warn "Failed to drop database: $db"
                    fi
                done <<< "$ALL_DBS"
            fi
        fi
        
        info "Dropping PostgreSQL user '$ODOO_USER'..."
        sudo -u postgres psql -c "DROP USER IF EXISTS $ODOO_USER;" 2>/dev/null || warn "Failed to drop user: $ODOO_USER"
        success "PostgreSQL user '$ODOO_USER' and associated databases removed."
    else
        warn "PostgreSQL user '$ODOO_USER' does not exist."
    fi
}

# --- Remove Odoo System User ---
remove_odoo_user() {
    info "Removing Odoo system user and home directory..."
    if id -u "$ODOO_USER" &>/dev/null; then
        pkill -u "$ODOO_USER" 2>/dev/null || true
        sleep 2
        
        userdel -r "$ODOO_USER" 2>/dev/null || {
            warn "Failed to remove user with home directory. Trying alternative method..."
            userdel "$ODOO_USER" 2>/dev/null || true
        }
        
        if [ -d "$ODOO_HOME" ]; then
            rm -rf "$ODOO_HOME"
        fi
        
        groupdel "$ODOO_USER" 2>/dev/null || true
        
        success "Odoo system user and home directory removed."
    else
        warn "Odoo system user '$ODOO_USER' does not exist."
    fi
}

# --- Remove Odoo Configuration ---
remove_odoo_config() {
    info "Removing Odoo configuration file..."
    if [ -f "$ODOO_CONFIG_FILE" ]; then
        rm -f "$ODOO_CONFIG_FILE"
        success "Odoo configuration file removed."
    else
        warn "Odoo configuration file not found."
    fi
}

# --- Remove Odoo Log Files ---
remove_odoo_logs() {
    info "Removing Odoo log directory..."
    if [ -d "$ODOO_LOG_DIR" ]; then
        rm -rf "$ODOO_LOG_DIR"
        success "Odoo log directory removed."
    else
        warn "Odoo log directory not found."
    fi
}

# --- Remove Nginx Configuration ---
remove_nginx_config() {
    info "Removing Nginx configuration..."
    
    NGINX_CONFIGS=$(find /etc/nginx/sites-available/ -type f 2>/dev/null | xargs grep -l "odoo\|8069\|8072" 2>/dev/null || true)
    
    if [ -n "$NGINX_CONFIGS" ]; then
        while IFS= read -r config; do
            if [ -f "$config" ]; then
                BASENAME=$(basename "$config")
                info "Removing Nginx config: $config"
                rm -f "$config"
                rm -f "/etc/nginx/sites-enabled/$BASENAME"
            fi
        done <<< "$NGINX_CONFIGS"
        success "Nginx Odoo configurations removed."
    else
        rm -f /etc/nginx/sites-available/odoo 2>/dev/null || true
        rm -f /etc/nginx/sites-enabled/odoo 2>/dev/null || true
        warn "No Odoo-specific Nginx configuration found."
    fi
    
    if [ -f /etc/nginx/sites-available/default ] && [ ! -L /etc/nginx/sites-enabled/default ]; then
        ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
        info "Restored default Nginx site."
    fi
    
    if command -v nginx &> /dev/null; then
        if nginx -t 2>/dev/null; then
            systemctl reload nginx 2>/dev/null || warn "Failed to reload Nginx."
            success "Nginx configuration reloaded."
        else
            warn "Nginx configuration test failed. Please check manually."
        fi
    fi
}

# --- Remove SSL Certificates ---
remove_ssl_certificates() {
    read -p "Do you want to remove SSL certificates? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Skipping SSL certificate removal."
        return
    fi
    
    info "Searching for SSL certificates..."
    
    if [ -d /etc/letsencrypt ]; then
        if command -v certbot &> /dev/null; then
            echo "Found certificates:"
            certbot certificates 2>/dev/null || true
            
            read -p "Enter domain name to remove certificate (or 'all' for all, or 'skip' to skip): " -r
            case $REPLY in
                skip)
                    info "Skipping certificate removal."
                    ;;
                all)
                    info "Removing all certificates..."
                    rm -rf /etc/letsencrypt
                    success "All SSL certificates removed."
                    ;;
                *)
                    if [ -n "$REPLY" ]; then
                        certbot delete --cert-name "$REPLY" 2>/dev/null || warn "Failed to remove certificate for: $REPLY"
                    fi
                    ;;
            esac
        else
            warn "Certbot not installed. Checking for certificate directories..."
            ls -la /etc/letsencrypt/live/ 2>/dev/null || warn "No certificates found."
        fi
    else
        warn "No SSL certificates directory found."
    fi
}

# --- Remove System Dependencies ---
remove_dependencies() {
    read -p "Do you want to remove Odoo dependencies (wkhtmltopdf, nginx, postgresql)? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Skipping dependency removal."
        return
    fi
    
    info "Removing Odoo-specific dependencies..."
    
    if dpkg -l | grep -q wkhtmltox; then
        apt-get remove --purge -y wkhtmltox 2>/dev/null || warn "Failed to remove wkhtmltopdf."
        success "wkhtmltopdf removed."
    fi
    
    read -p "Remove PostgreSQL? This will remove ALL databases! (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        apt-get remove --purge -y postgresql postgresql-* 2>/dev/null || warn "Failed to remove PostgreSQL."
        rm -rf /etc/postgresql /var/lib/postgresql
        success "PostgreSQL removed."
    fi
    
    read -p "Remove Nginx? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        apt-get remove --purge -y nginx nginx-* 2>/dev/null || warn "Failed to remove Nginx."
        rm -rf /etc/nginx /var/log/nginx
        success "Nginx removed."
    fi
    
    read -p "Remove Certbot? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        apt-get remove --purge -y certbot python3-certbot-nginx 2>/dev/null || warn "Failed to remove Certbot."
        success "Certbot removed."
    fi
    
    apt-get autoremove -y 2>/dev/null || true
    apt-get autoclean -y 2>/dev/null || true
}

# --- Update Firewall Rules ---
update_firewall() {
    info "Updating firewall rules..."
    
    if command -v ufw &> /dev/null; then
        read -p "Remove firewall rules for Nginx? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            ufw delete allow 'Nginx Full' 2>/dev/null || true
            ufw delete allow 'Nginx HTTP' 2>/dev/null || true
            ufw delete allow 'Nginx HTTPS' 2>/dev/null || true
            ufw delete allow 80/tcp 2>/dev/null || true
            ufw delete allow 443/tcp 2>/dev/null || true
            success "Firewall rules updated."
        fi
    else
        warn "UFW not installed. Skipping firewall update."
    fi
}

# --- Final Cleanup ---
final_cleanup() {
    info "Performing final cleanup..."
    
    find /tmp -name "*odoo*" -type f -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -name "*odoo*" -type f -mtime +1 -delete 2>/dev/null || true
    
    success "Final cleanup completed."
}

# --- Summary ---
final_summary() {
    echo
    success "╔════════════════════════════════════════════════════════════════╗"
    success "║         ODOO UNINSTALLATION COMPLETED SUCCESSFULLY             ║"
    success "╚════════════════════════════════════════════════════════════════╝"
    echo
    info "The following items have been removed:"
    echo "  ✓ Odoo service and systemd configuration"
    echo "  ✓ Odoo user and home directory"
    echo "  ✓ PostgreSQL odoo user and databases"
    echo "  ✓ Odoo configuration files"
    echo "  ✓ Odoo log files"
    echo "  ✓ Nginx Odoo configuration"
    echo
    info "Your system has been cleaned up."
    echo
}

# --- Main Execution ---
main() {
    confirm_uninstall
    pre_run_checks
    stop_odoo_service
    remove_systemd_service
    remove_postgres_data
    remove_odoo_user
    remove_odoo_config
    remove_odoo_logs
    remove_nginx_config
    remove_ssl_certificates
    remove_dependencies
    update_firewall
    final_cleanup
    final_summary
}

main "$@"
