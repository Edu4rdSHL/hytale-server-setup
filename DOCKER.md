# Running Hytale Server with Docker

It's recommended to run the Hytale server in a containerized environment like Docker for easier management and isolation. The server is new and there maybe be security issues or bugs that could cause harm on a production system, Docker helps mitigate these risks.

If you want to use Docker after having the `/opt/Hytale/Server` configured, follow these steps:

## Prerequisites

- A working setup of the Hytale server. See the main [README](README.md) for installation instructions.
- Docker and Docker Compose installed on your system. You can follow the official Docker [installation guide](https://docs.docker.com/get-started/get-docker/).

## Setup

1. **Create a `docker-compose.yml` file** in a convenient location (e.g., `/opt/Hytale/`):

```yaml
services:
  hytale-server: 
    image: eclipse-temurin:latest
    container_name: hytale-server
    restart: unless-stopped
    working_dir: /opt/Hytale/Server
    volumes:  
      - /opt/Hytale/Server:/opt/Hytale/Server
    ports:
      - "5520:5520/udp"
      - "5523:5523" # if you're using the https://github.com/nitrado/hytale-plugin-webserver plugin
    command: java -jar HytaleServer.jar --assets Assets.zip --disable-sentry
    stdin_open: true
    tty: true
```

2. **Start the server**:
```bash
docker-compose up -d
```

3. **View server logs**:
```bash
docker-compose logs -f
```

4. **Stop the server**: 
```bash
docker-compose down
```

The result will be the same as running it natively, but now encapsulated in a Docker container.

## Configuration Notes

### Java Version

The configuration uses `eclipse-temurin:latest` which may not always be compatible.  If you need a specific Java version, update the image tag: 

```yaml
image: eclipse-temurin:24-jre  # For Java 24
# or
image: eclipse-temurin:23-jre  # For Java 23
```

## Migration from Native Setup

Since you're already running the server natively in `/opt/Hytale/Server`:

1. Stop your native Java process
2. Create the `docker-compose.yml` file
3. Run `docker-compose up -d`
4. Your server will continue using the same files and configuration

No data migration is needed since the Docker container mounts your existing directory directly. 
