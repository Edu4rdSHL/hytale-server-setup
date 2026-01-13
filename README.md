# Hytale Server Setup

Automated setup script for Hytale dedicated servers on Debian/Ubuntu Linux systems.

## Features

- Installs Adoptium JDK (recommended by Hytale)
- Downloads and configures the Hytale server
- Creates a systemd service for automatic startup
- Configures UFW firewall rules
- Colored terminal output for better visibility
- Automatic cleanup on installation failure

## Requirements

- **OS:** Debian or Ubuntu (x86_64 only)
- **Permissions:** Root access required
- **Network:** Internet connection for downloading packages
- **Account:** Valid Hytale account for authentication

## Quick Start

```bash
# Download and run the script
wget https://raw.githubusercontent.com/Edu4rdSHL/hytale-server-setup/main/hytale-setup.sh
chmod +x hytale-setup.sh
sudo ./hytale-setup.sh
```

## CRITICAL: Authentication Setup

After the server starts for the first time and you see the **"Hytale Server Booted!"** message, you **MUST** run the following commands in the server console:

```
/auth persistence Encrypted
/auth login device
```

**WARNING:** If you skip these commands or enter them incorrectly, the server will not function properly.

After completing authentication, stop the server with `Ctrl+C` and start it normally using:

```bash
# If systemd is available (recommended)
sudo systemctl start hytale-server.service

# Or manually
cd /opt/Hytale/Server && java -jar HytaleServer.jar --assets Assets.zip
```

## Configuration

The script supports environment variables for customization:

| Variable | Default | Description |
|----------|---------|-------------|
| `DISTRO_VERSION` | `trixie` | Debian/Ubuntu codename for Adoptium repository |
| `ADOPTIUM_JDK_VERSION` | `25` | JDK version to install |
| `INSTALL_PATH` | `/opt/Hytale` | Server installation directory |
| `HYTALE_SERVER_VERSION` | `release` | Version to download (`release`, `pre-release`, or specific version) |
| `FIREWALL_PORT` | `5520/udp` | Port to open in UFW |
| `LOCAL_HYTALE_SERVER_ZIP` | *(empty)* | Path to local server zip (skips downloads) |

### Example with custom configuration

```bash
sudo INSTALL_PATH=/home/hytale/server HYTALE_SERVER_VERSION=pre-release ./hytale-setup.sh
```

## Systemd Service

If systemd is available, the script creates a service at `/etc/systemd/system/hytale-server.service`:

```bash
# Start the server
sudo systemctl start hytale-server.service

# Stop the server
sudo systemctl stop hytale-server.service

# Check status
sudo systemctl status hytale-server.service

# View logs
sudo journalctl -u hytale-server.service -f
```

## Connecting to Your Server

After setup, players can connect using:

- **Remote/Public IP:** `your_server_ip:5520`
- **Local:** `localhost:5520`

Make sure port `5520/udp` is open on your firewall and any cloud provider security groups.

## Troubleshooting

### Server fails to start after reboot
Make sure you ran the `/auth` commands during initial setup. If not, you may need to re-authenticate.

### JDK installation fails
Try setting a different `DISTRO_VERSION` that matches your system:
```bash
sudo DISTRO_VERSION=bookworm ./hytale-setup.sh  # Debian 12
sudo DISTRO_VERSION=jammy ./hytale-setup.sh     # Ubuntu 22.04
```

### Port already in use
Check if another process is using port 5520:
```bash
sudo lsof -i :5520
```

## License

This project is open source, licensed under the MIT License. Feel free to contribute or submit issues!
