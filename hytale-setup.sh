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