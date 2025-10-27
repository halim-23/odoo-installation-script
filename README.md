
# Automated Odoo 18 Enterprise Deployment on Ubuntu 24.04

![Odoo Version](https://img.shields.io/badge/Odoo-18.0_Enterprise-blue.svg)
![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04_LTS-orange.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

This repository contains a comprehensive bash script to automate the deployment of a **production-ready Odoo 18 Enterprise** instance on a clean Ubuntu 24.04 LTS server.

The script is designed with DevOps best practices in mind, creating a secure, scalable, and manageable Odoo environment. It goes beyond a basic installation by configuring a full web stack with performance tuning and security hardening.

## ✨ Features

*   **🚀 Fully Automated:** From system updates to a live, running Odoo instance with a single command.
*   **🛡️ Secure by Default:**
    *   Runs Odoo under a dedicated, non-root system user.
    *   Sets up and enables a `UFW` firewall.
    *   Automatically obtains and configures a **free SSL certificate from Let's Encrypt** (HTTPS).
    *   Generates strong, random passwords for the database and Odoo admin.
*   **⚡ Performance Tuned:**
    *   Configures **Nginx** as a high-performance reverse proxy.
    *   Enables **WebSocket** support for real-time features (like Live Chat), with a fallback to longpolling.
    *   Automatically calculates the optimal number of **Odoo workers** based on server CPU cores.
*   **📦 Enterprise & Custom Addons Ready:** Clones community, enterprise, and your custom addons repositories into the correct structure.
*   **⚙️ Robust Management:**
    *   Creates a `systemd` service to manage the Odoo application (start, stop, status) and enable auto-start on boot.
    *   Organizes configuration, logs, and Odoo source code in a clean, predictable directory structure.

## 📋 Prerequisites

Before running the script, you must have the following:

1.  **A clean Ubuntu 24.04 LTS server.**
2.  **Root (`sudo`) access** to the server.
3.  **A domain or subdomain** (e.g., `odoo.yourcompany.com`) pointing to your server's public IP address. This is required for SSL certificate generation.
4.  **Access to the Odoo Enterprise GitHub repository.** You will need a URL with a **Personal Access Token (PAT)** for automated cloning.
    *   Example URL: `https://YOUR_USERNAME:YOUR_PAT@github.com/odoo/enterprise.git`

## 🚀 How to Use

1.  **Clone this repository:**
    ```bash
    git clone https://github.com/your-username/your-repo-name.git
    cd your-repo-name
    ```

2.  **Make the script executable:**
    ```bash
    chmod +x odoo-installation-script.sh
    ```

3.  **Run the script as root:**
    ```bash
    sudo ./odoo-installation-script.sh
    ```

4.  **Follow the prompts:**
    The script will ask for your domain name, an email address for SSL notifications, and the Git URLs for your Odoo Enterprise and custom addons repositories.

The script will handle the rest. Once completed, it will display a summary with your Odoo URL and the generated passwords.

## 🛠️ The Deployed Stack

The script provisions the following components:

| Component | Details |
| :--- | :--- |
| **Operating System** | Ubuntu 24.04 LTS |
| **Database** | PostgreSQL |
| **Application Server** | Odoo 18.0 (from source) |
| **Python Environment**| Python 3 `venv` for dependency isolation |
| **Odoo Source** | `/opt/odoo18e/` (community, enterprise, custom_addons) |
| **Process Manager** | `systemd` (`odoo18e.service`) |
| **Reverse Proxy** | Nginx (with WebSocket & SSL termination) |
| **Security** | UFW Firewall & Let's Encrypt SSL |
| **PDF Rendering** | `wkhtmltopdf` (patched version) |

## 🔧 Post-Installation Management

### Odoo Service Commands

Manage the Odoo application using `systemctl`:

```bash
# Check the status of the Odoo service
sudo systemctl status odoo18e

# Start the Odoo service
sudo systemctl start odoo18e

# Stop the Odoo service
sudo systemctl stop odoo18e

# Restart the Odoo service (e.g., after adding new custom modules)
sudo systemctl restart odoo18e
```

### Viewing Logs

To view real-time logs for the Odoo application:

```bash
sudo journalctl -fu odoo18e
```

### Custom Addons Workflow

1.  Add your new custom module to the `/opt/odoo18e/custom_addons` directory (e.g., via `git pull`).
2.  Restart the Odoo service: `sudo systemctl restart odoo18e`.
3.  Log in to Odoo, go to the **Apps** menu, and click **Update Apps List**.
4.  Your new module will now be available for installation.

## ⚙️ Configuration

The primary configuration variables (like the Odoo system user name) are located at the top of the `provision_odoo18e.sh` script. You can modify them before running the script if needed.

## 🗑️ Uninstallation

If you need to completely remove Odoo from your server, use the included uninstallation script:

### Features

The `odoo-uninstall.sh` script provides a complete cleanup:

*   **🛑 Stops and removes** the Odoo systemd service
*   **👤 Deletes** the Odoo system user and home directory (`/opt/odoo`)
*   **🗄️ Removes** PostgreSQL odoo user and all Odoo databases
*   **📝 Cleans up** Odoo configuration files and logs
*   **🌐 Removes** Nginx Odoo configuration
*   **🔐 Optionally removes** SSL certificates
*   **📦 Optionally removes** system dependencies (PostgreSQL, Nginx, wkhtmltopdf, etc.)
*   **🔥 Updates** firewall rules

### Usage

1.  **Make the script executable:**
    ```bash
    chmod +x odoo-uninstall.sh
    ```

2.  **Run the script as root:**
    ```bash
    sudo ./odoo-uninstall.sh
    ```

3.  **Follow the prompts:**
    The script will ask for confirmation before proceeding and provide options for:
    *   Removing all databases (including non-Odoo databases)
    *   Removing SSL certificates
    *   Removing system dependencies (PostgreSQL, Nginx, Certbot, wkhtmltopdf)
    *   Updating firewall rules

### Safety Features

*   **Double confirmation** required (yes/no + typing 'DELETE')
*   **Interactive prompts** for optional removals
*   **Detailed logging** of all actions
*   **Graceful handling** of missing components

⚠️ **WARNING:** This script will permanently delete all Odoo data, databases, and configurations. This action cannot be undone!

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.

## 🙏 Acknowledgements

*   The official Odoo documentation for providing excellent guidance on deployment and configuration.
