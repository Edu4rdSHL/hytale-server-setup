# Hytale Server Setup

Automated setup script for Hytale dedicated servers on Debian/Ubuntu Linux systems.

After finishing this setup, it's recommended to setup Docker. See [DOCKER.md](DOCKER.md) for instructions.

## Features

- Installs Adoptium JDK (recommended by Hytale)
- Downloads and configures the Hytale server
- Creates a systemd service for automatic startup
- Configures UFW firewall rules
- Colored terminal output for better visibility
- Automatic cleanup on installation failure
- **Built-in update mechanism** with automatic backups

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

## Memory Configuration (Important!)

For optimal server performance, you should configure the Java memory settings (`-Xms` and `-Xmx`) based on your server's available RAM:

- **`-Xms`**: Initial heap size (minimum memory allocated at startup)
- **`-Xmx`**: Maximum heap size (maximum memory the JVM can use)

### Recommended Settings

| Server RAM | `-Xms` | `-Xmx` | Example |
|------------|--------|--------|---------|
| 4 GB | 1024m | 2560m | `-Xms1024m -Xmx2560m` |
| 8 GB | 2048m | 6144m | `-Xms2048m -Xmx6144m` |
| 16 GB | 4096m | 12288m | `-Xms4096m -Xmx12288m` |
| 32 GB | 8192m | 24576m | `-Xms8192m -Xmx24576m` |

> **Tip:** Always leave some RAM for the operating system and other processes. A good rule of thumb is to allocate 75-80% of your total RAM to `-Xmx`.

### Applying Memory Settings

If using the systemd service, edit `/etc/systemd/system/hytale-server.service`:

```bash
sudo systemctl edit hytale-server.service
```

And add/modify the `ExecStart` line to include memory flags:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/java -Xms2048m -Xmx6144m -jar /opt/Hytale/Server/HytaleServer.jar --assets /opt/Hytale/Server/Assets.zip
```

Then reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl restart hytale-server.service
```

If running manually:

```bash
cd /opt/Hytale/Server && java -Xms2048m -Xmx6144m -jar HytaleServer.jar --assets Assets.zip
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

## Updating the Server

The script includes a built-in update mechanism that:

- Checks your current server version
- Compares it with the latest available version
- Creates a backup of your current files before updating
- Updates only the necessary server files (preserves your configuration)

### Check for and apply updates

```bash
sudo ./hytale-setup.sh --update
# or
sudo ./hytale-setup.sh -u
```

### What gets updated

The update process replaces only the required server files that need updating:

- `Server/HytaleServer.jar`
- `Server/HytaleServer.aot`
- `Server/Assets.zip`

Your server configuration, world data, and other custom files are **preserved**.

### Backups

Before each update, a backup is automatically created at:

```bash
/opt/Hytale/backups/YYYYMMDD_HHMMSS/
```

To restore a backup, simply copy the files back:

```bash
sudo systemctl stop hytale-server.service # adjust the stop command if you're using docker/podman
sudo cp /opt/Hytale/backups/YYYYMMDD_HHMMSS/* /opt/Hytale/Server/
sudo systemctl start hytale-server.service # adjust the start command if you're using docker/podman
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
