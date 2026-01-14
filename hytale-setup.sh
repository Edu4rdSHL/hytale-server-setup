#!/usr/bin/env bash
# Hytale Server Setup Script
# This script sets up a Hytale server environment on a Debian/Ubuntu Linux system.

set -euo pipefail

# Configuration Options

# Can be changed to a specific version if needed. Some distro versions aren't directly supported by
# https://packages.adoptium.net/ui/native/deb/dists/, but most will work with the closest supported version.
# Default: "trixie" - it works for latest Debian and Ubuntu, adjust if needed.
DISTRO_VERSION="${DISTRO_VERSION:-trixie}"
# Adoptium JDK version to install
# Default: "25"
readonly ADOPTIUM_JDK_VERSION="${ADOPTIUM_JDK_VERSION:-25}"
# Hytale Downloader url
readonly HYTALE_DOWNLOADER_URL="${HYTALE_DOWNLOADER_URL:-https://downloader.hytale.com/hytale-downloader.zip}"
# Installation path
readonly INSTALL_PATH="${INSTALL_PATH:-/opt/Hytale}"
# Hytale server version to download. Can be "release", "pre-release", or a specific version string like "0.9.1".
# Default: "release"
readonly HYTALE_SERVER_VERSION="${HYTALE_SERVER_VERSION:-release}"
# Firewall port to open for Hytale server (default: 5520)
readonly FIREWALL_PORT="${FIREWALL_PORT:-5520/udp}"
# Download filename for the Hytale server zip
HYTALE_SERVER_ZIP_FILENAME="hytale-server.zip"
# Support locally downloaded .zip file for the Hytale Server. If you already have the server .zip file,
# you can specify its path here to skip the download step.
# Default: "" - use downloader
readonly LOCAL_HYTALE_SERVER_ZIP="${LOCAL_HYTALE_SERVER_ZIP:-}"
# Server cmd to start the Hytale server after setup. Depends on whether systemctl is available.
SERVER_START_CMD="cd '${INSTALL_PATH}/Server' && java -jar HytaleServer.jar --assets Assets.zip --disable-sentry &"
# Server password (I still don't know the command line argument for this, so this is just a placeholder for now)
# If you know how to set the server password via command line, please let me know!
# readonly SERVER_PASSWORD="${SERVER_PASSWORD:-your_password_here}"

# Script mode: "install" (default) or "update"
SCRIPT_MODE="install"

# Parse command line arguments
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --update    Check for and apply server updates"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  INSTALL_PATH              Installation directory (default: /opt/Hytale)"
    echo "  HYTALE_SERVER_VERSION     Server version: release, pre-release, or specific (default: release)"
    echo "  ADOPTIUM_JDK_VERSION      JDK version to install (default: 25)"
    echo "  LOCAL_HYTALE_SERVER_ZIP   Path to local server zip file (skips download)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--update)
            SCRIPT_MODE="update"
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Color definitions
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$1${NC}"
}


# Bail if not running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root."
    exit 1
fi

DISTRO=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')

if [ "$DISTRO" != "debian" ] && [ "$DISTRO" != "ubuntu" ]; then
  log_error "Unsupported distribution: $DISTRO"
  log_info "This script only supports Debian and Ubuntu."
  log_info "Feel free to send a pull request to add support for your distribution!"
  exit 1
fi

# Verify system architecture (only x86_64 is supported)
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    log_error "Unsupported architecture: $ARCH"
    log_info "The Hytale server only supports x86_64 (amd64)."
    exit 1
fi

# Check if systemctl is available to determine if we can create a systemd service
if command -v systemctl >/dev/null 2>&1; then
    IS_SYSTEMCTL_AVAILABLE=true
else
    IS_SYSTEMCTL_AVAILABLE=false
fi

# Cleanup function for partial installations
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Error occurred. Cleaning up partial installation..."
        # Only remove if we created it during this run
        if [ -d "$INSTALL_PATH" ] && [ -f "$INSTALL_PATH/.setup_in_progress" ]; then
            rm -rf "$INSTALL_PATH"
        fi
    fi
    exit $exit_code
}
trap cleanup EXIT

# Function to print error message and exit
bail() {
  log_error "$1"
  exit 1
}

# Update function to check and apply server updates
do_update() {
    log_step "Checking for Hytale server updates"

    # Verify installation exists
    if [ ! -d "$INSTALL_PATH/Server" ]; then
        bail "Hytale server not found at $INSTALL_PATH/Server. Please run the installer first."
    fi

    if [ ! -f "$INSTALL_PATH/Server/HytaleServer.jar" ]; then
        bail "HytaleServer.jar not found. Please run the installer first."
    fi

    # Get current installed version
    log_info "Getting current server version..."
    cd "$INSTALL_PATH/Server" || bail "Failed to change to server directory"
    
    CURRENT_VERSION=$(java -jar HytaleServer.jar --version 2>/dev/null || echo "unknown")
    CURRENT_VERSION=$(echo "$CURRENT_VERSION" | tr -d '\n' | tr -d '\r')
    
    if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" = "unknown" ]; then
        log_warn "Could not determine current server version. Will proceed with update check."
        CURRENT_VERSION="unknown"
    else
        log_info "Current version: ${CYAN}$CURRENT_VERSION${NC}"
    fi

    # Ensure downloader exists, download if needed
    cd "$INSTALL_PATH" || bail "Failed to change to installation directory"
    
    if [ ! -f "$INSTALL_PATH/hytale-downloader-linux-amd64" ]; then
        log_info "Downloader not found, downloading..."
        wget -O hytale-downloader.zip "$HYTALE_DOWNLOADER_URL" \
            || bail "Failed to download Hytale Downloader."
        unzip -o hytale-downloader.zip -d "$INSTALL_PATH" > /dev/null \
            || bail "Failed to unzip Hytale Downloader."
    fi

    # Run downloader briefly to get latest version info
    log_info "Checking latest available version..."
    
    # Run the downloader and capture output, kill it after getting version info
    DOWNLOADER_OUTPUT=$(timeout 10s ./hytale-downloader-linux-amd64 -patchline "$HYTALE_SERVER_VERSION" 2>&1 || true)
    
    # Extract version from output like: downloading latest ("pre-release" patchline) to "2026.01.14-3e7a0ba6c.zip"
    LATEST_VERSION=$(echo "$DOWNLOADER_OUTPUT" | grep -oP 'to "\K[^"]+(?=\.zip")' | head -1 || echo "")
    
    if [ -z "$LATEST_VERSION" ]; then
        # Try alternative pattern
        LATEST_VERSION=$(echo "$DOWNLOADER_OUTPUT" | grep -oP '"[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+' | tr -d '"' | head -1 || echo "")
    fi

    if [ -z "$LATEST_VERSION" ]; then
        log_error "Could not determine latest version from downloader output."
        log_info "Downloader output:"
        echo "$DOWNLOADER_OUTPUT"
        bail "Update check failed."
    fi

    log_info "Latest version: ${CYAN}$LATEST_VERSION${NC}"

    # Normalize current version for comparison
    # Extract just the date-hash part (e.g., "2026.01.13-50e69c385" from "HytaleServer v2026.01.13-50e69c385 (release)")
    CURRENT_VERSION_NORMALIZED=$(echo "$CURRENT_VERSION" | grep -oP '[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+' | head -1 || echo "$CURRENT_VERSION")

    # Compare versions
    if [ "$CURRENT_VERSION_NORMALIZED" = "$LATEST_VERSION" ]; then
        log_success "Server is already up to date! ($LATEST_VERSION)"
        exit 0
    fi

    if [ "$CURRENT_VERSION" = "unknown" ]; then
        log_warn "Could not compare versions. Proceeding with update..."
    else
        log_info "Update available: $CURRENT_VERSION_NORMALIZED -> $LATEST_VERSION"
    fi

    # Ask for confirmation
    echo
    echo -e "${YELLOW}Do you want to update the server? [y/N]${NC}"
    read -r -n 1 CONFIRM
    echo
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Update cancelled."
        exit 0
    fi

    # Track how the server was stopped so we can suggest how to restart it
    STOPPED_VIA=""

    # Check if server is running (systemd)
    if [ "$IS_SYSTEMCTL_AVAILABLE" = true ]; then
        if systemctl is-active --quiet hytale-server.service 2>/dev/null; then
            log_warn "Hytale server is currently running (systemd)."
            echo -e "${YELLOW}Stop the server before updating? [Y/n]${NC}"
            read -r -n 1 STOP_CONFIRM
            echo
            
            if [[ ! "$STOP_CONFIRM" =~ ^[Nn]$ ]]; then
                log_step "Stopping Hytale server..."
                systemctl stop hytale-server.service || bail "Failed to stop server."
                log_success "Server stopped."
                STOPPED_VIA="systemd"
            else
                bail "Cannot update while server is running. Please stop the server first."
            fi
        fi
    fi

    # Check if server is running (Docker)
    if command -v docker >/dev/null 2>&1; then
        DOCKER_CONTAINER=$(docker ps --filter "name=hytale" --format "{{.Names}}" 2>/dev/null | head -1)
        if [ -n "$DOCKER_CONTAINER" ]; then
            log_warn "Hytale server is currently running in Docker container: $DOCKER_CONTAINER"
            echo -e "${YELLOW}Stop the Docker container before updating? [Y/n]${NC}"
            read -r -n 1 STOP_DOCKER_CONFIRM
            echo
            
            if [[ ! "$STOP_DOCKER_CONFIRM" =~ ^[Nn]$ ]]; then
                log_step "Stopping Docker container: $DOCKER_CONTAINER..."
                docker stop "$DOCKER_CONTAINER" || bail "Failed to stop Docker container."
                log_success "Docker container stopped."
                STOPPED_VIA="docker:$DOCKER_CONTAINER"
            else
                bail "Cannot update while server is running in Docker. Please stop the container first."
            fi
        fi
    fi

    # Check if server is running (Podman)
    if command -v podman >/dev/null 2>&1; then
        PODMAN_CONTAINER=$(podman ps --filter "name=hytale" --format "{{.Names}}" 2>/dev/null | head -1)
        if [ -n "$PODMAN_CONTAINER" ]; then
            log_warn "Hytale server is currently running in Podman container: $PODMAN_CONTAINER"
            echo -e "${YELLOW}Stop the Podman container before updating? [Y/n]${NC}"
            read -r -n 1 STOP_PODMAN_CONFIRM
            echo
            
            if [[ ! "$STOP_PODMAN_CONFIRM" =~ ^[Nn]$ ]]; then
                log_step "Stopping Podman container: $PODMAN_CONTAINER..."
                podman stop "$PODMAN_CONTAINER" || bail "Failed to stop Podman container."
                log_success "Podman container stopped."
                STOPPED_VIA="podman:$PODMAN_CONTAINER"
            else
                bail "Cannot update while server is running in Podman. Please stop the container first."
            fi
        fi
    fi

    # Download the update
    log_step "Downloading update..."
    UPDATE_ZIP="$LATEST_VERSION.zip"
    
    ./hytale-downloader-linux-amd64 -download-path "$UPDATE_ZIP" -patchline "$HYTALE_SERVER_VERSION" \
        || bail "Failed to download server update."

    # Backup current files
    log_step "Backing up current server files..."
    BACKUP_DIR="$INSTALL_PATH/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR" || bail "Failed to create backup directory."
    
    cp -f "$INSTALL_PATH/Server/HytaleServer.jar" "$BACKUP_DIR/" 2>/dev/null || true
    cp -f "$INSTALL_PATH/Server/HytaleServer.aot" "$BACKUP_DIR/" 2>/dev/null || true
    cp -f "$INSTALL_PATH/Server/Assets.zip" "$BACKUP_DIR/" 2>/dev/null || true
    
    log_success "Backup saved to: $BACKUP_DIR"

    # Extract and update files
    log_step "Extracting update..."
    TEMP_DIR=$(mktemp -d)
    unzip -o "$UPDATE_ZIP" -d "$TEMP_DIR" > /dev/null \
        || bail "Failed to unzip update."

    log_step "Updating server files..."
    
    # Update the server files
    if [ -f "$TEMP_DIR/Server/HytaleServer.jar" ]; then
        cp -f "$TEMP_DIR/Server/HytaleServer.jar" "$INSTALL_PATH/Server/" \
            || bail "Failed to update HytaleServer.jar"
    fi
    
    if [ -f "$TEMP_DIR/Server/HytaleServer.aot" ]; then
        cp -f "$TEMP_DIR/Server/HytaleServer.aot" "$INSTALL_PATH/Server/" \
            || bail "Failed to update HytaleServer.aot"
    fi
    
    if [ -f "$TEMP_DIR/Assets.zip" ]; then
        cp -f "$TEMP_DIR/Assets.zip" "$INSTALL_PATH/Server/Assets.zip" \
            || bail "Failed to update Assets.zip"
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    rm -f "$INSTALL_PATH/$UPDATE_ZIP"
    
    log_success "Server updated successfully!"
    echo
    log_info "Updated from $CURRENT_VERSION_NORMALIZED to $LATEST_VERSION"
    log_info "Backup of previous version saved to: $BACKUP_DIR"
    echo
    
    # Show restart instructions based on how the server was stopped
    log_info "To start the server, run:"
    case "$STOPPED_VIA" in
        systemd)
            echo -e "  ${GREEN}sudo systemctl start hytale-server.service${NC}"
            ;;
        docker:*)
            CONTAINER_NAME="${STOPPED_VIA#docker:}"
            echo -e "  ${GREEN}docker start $CONTAINER_NAME${NC}"
            ;;
        podman:*)
            CONTAINER_NAME="${STOPPED_VIA#podman:}"
            echo -e "  ${GREEN}podman start $CONTAINER_NAME${NC}"
            ;;
        *)
            # Server wasn't running, show generic instructions
            if [ "$IS_SYSTEMCTL_AVAILABLE" = true ] && [ -f "/etc/systemd/system/hytale-server.service" ]; then
                echo -e "  ${GREEN}sudo systemctl start hytale-server.service${NC}"
            else
                echo -e "  ${GREEN}cd $INSTALL_PATH/Server && java -jar HytaleServer.jar --assets Assets.zip --disable-sentry${NC}"
            fi
            ;;
    esac
    
    exit 0
}

# Run update if requested
if [ "$SCRIPT_MODE" = "update" ]; then
    do_update
fi

# Main Installation Logic

log_step "Creating installation directory"
mkdir -p "$INSTALL_PATH" || { bail "Failed to create installation directory: $INSTALL_PATH"; }
touch "$INSTALL_PATH/.setup_in_progress" || { bail "Failed to create setup marker file"; }
cd "$INSTALL_PATH" || { bail "Failed to change to installation directory: $INSTALL_PATH"; }

log_step "Installing required base packages"
apt update
apt install -y wget apt-transport-https gpg unzip || { bail "Failed to install required packages."; }

log_step "Setting up Adoptium JDK repository"
# https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual#server-setup
## Import Adoptium GPG key and add repository
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public > /tmp/adoptium.key \
    || { bail "Failed to download Adoptium GPG key."; }
gpg --dearmor < /tmp/adoptium.key > /etc/apt/trusted.gpg.d/adoptium.gpg \
    || { bail "Failed to import Adoptium GPG key."; }
rm -f /tmp/adoptium.key

## Add the Adoptium repository
if [ -n "$DISTRO_VERSION" ]; then
  echo "deb https://packages.adoptium.net/artifactory/deb $DISTRO_VERSION main" | tee /etc/apt/sources.list.d/adoptium.list \
    || { bail "Failed to add Adoptium repository."; }
else
  echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" | tee /etc/apt/sources.list.d/adoptium.list \
    || { bail "Failed to add Adoptium repository."; }
fi

## Update package lists to reflect new repository
apt update
log_step "Installing Adoptium JDK $ADOPTIUM_JDK_VERSION"
apt install -y temurin-"$ADOPTIUM_JDK_VERSION"-jdk || { bail "Failed to install Adoptium JDK."; }
log_success "Adoptium JDK installed successfully"

# Download and set up Hytale server files
if [ -z "$LOCAL_HYTALE_SERVER_ZIP" ]; then
    log_step "Downloading Hytale Downloader"
    wget -O hytale-downloader.zip "$HYTALE_DOWNLOADER_URL" \
        || { bail "Failed to download Hytale Downloader."; }

    unzip -o hytale-downloader.zip -d "$INSTALL_PATH" > /dev/null \
        || { bail "Failed to unzip Hytale Downloader."; }
    # Run the Hytale Downloader to download the server files
    log_step "Starting Hytale Downloader"
    log_warn "You will now need to authenticate with your Hytale account, please keep an eye on the terminal for prompts."
    echo

    ./hytale-downloader-linux-amd64 -download-path "$HYTALE_SERVER_ZIP_FILENAME" -patchline "$HYTALE_SERVER_VERSION" \
        || { bail "Hytale Downloader failed to download the server files."; }
else
    HYTALE_SERVER_ZIP_FILENAME="$LOCAL_HYTALE_SERVER_ZIP"
    log_info "Using locally provided Hytale server zip file: $HYTALE_SERVER_ZIP_FILENAME"
fi

log_step "Extracting Hytale server files"
unzip -o "$HYTALE_SERVER_ZIP_FILENAME" -d "$INSTALL_PATH" > /dev/null \
  || { bail "Failed to unzip Hytale server files."; }

mv Assets.zip "$INSTALL_PATH/Server/Assets.zip" \
  || { bail "Failed to move Assets.zip to server directory."; }
log_success "Hytale server files extracted successfully"

# Open firewall port for Hytale server
log_step "Configuring firewall"
if command -v ufw >/dev/null 2>&1; then
    ufw allow "$FIREWALL_PORT" || { bail "Failed to open firewall port $FIREWALL_PORT."; }
    log_success "Firewall port $FIREWALL_PORT opened for Hytale server."
else
    log_warn "ufw not found, skipping firewall configuration. Make sure to open port $FIREWALL_PORT manually if needed."
fi

if [ "$IS_SYSTEMCTL_AVAILABLE" = true ]; then
    log_step "Creating systemd service"
    # Create a systemd service for the Hytale server
    SERVICE_FILE="/etc/systemd/system/hytale-server.service"
    if [ ! -f "$SERVICE_FILE" ]; then
        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Hytale Server
After=network.target
[Service]
WorkingDirectory=$INSTALL_PATH/Server
ExecStart=/usr/bin/java -jar HytaleServer.jar --assets Assets.zip --disable-sentry
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    fi
    # Enable the Hytale server service to start on boot
    systemctl enable hytale-server.service || { bail "Failed to enable Hytale server service."; }
    log_success "Systemd service created and enabled"
    SERVER_START_CMD="systemctl start hytale-server.service"
fi

# Run the server once to generate config files, but first tell the user that he needs to run the following commands first
# after seeing the "Hytale Server Booted!" message.
#
# /auth persistence Encrypted
# /auth login device
#
echo
log_success "Hytale server files downloaded successfully!"
echo
log_info "To complete the setup, you will need to run the server once and authenticate your Hytale account."
log_info "After seeing the 'Hytale Server Booted!' message, run the following commands in the server console:"
log_info "Note: the server console is just the terminal where this script is running."
echo
log_warn "IMPORTANT: Make sure to run these commands EXACTLY as shown to avoid any issues with authentication:"
echo
echo -e "  ${CYAN}/auth persistence Encrypted${NC}"
echo -e "  ${CYAN}/auth login device${NC}"
echo
log_info "After completing these steps, stop the server (Ctrl+C) and run it again with:"
echo -e "  ${GREEN}$SERVER_START_CMD${NC}"
echo

# Ask the user to press any key to continue
# Remove setup marker as setup is basically complete
rm -f "$INSTALL_PATH/.setup_in_progress"

echo -e "${YELLOW}Press any key to start the Hytale server...${NC}"
read -n 1 -s -r
echo ""
log_step "Starting Hytale server"
cd "$INSTALL_PATH/Server" || { bail "Failed to change to server directory: $INSTALL_PATH/Server"; }

# Run the server and allow Ctrl+C without triggering error
java -jar HytaleServer.jar --assets Assets.zip || {
    exit_code=$?
    if [ $exit_code -eq 130 ]; then
        echo ""
        log_info "Server stopped by user (Ctrl+C)"
    else
        bail "Failed to start Hytale server (exit code: $exit_code)."
    fi
}

echo ""
log_success "Hytale server stopped."
log_info "Add the server to your Hytale client using the following address:"
echo -e "  ${GREEN}your_ip_address:5520${NC}"
log_info "If you're running the server locally, you can use 'localhost:5520' as the address."
log_info "To start the server again, run:"
echo -e "  ${GREEN}$SERVER_START_CMD${NC}"
log_success "Setup complete!"