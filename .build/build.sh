#!/bin/bash

set -o allexport # Enable exporting of all variables defined
source .env      # Load environment variables from .env
set +o allexport # Disable exporting of variables

TEMP_DIR=temp                                                         # Path (local): temporary directory
ORIGIN_CERT_LOCAL="$CLOUDFLARED_SOURCE_DIR"/cert.pem                  # Path (local): origin certificate
ORIGIN_CERT_CONTAINER=/etc/cloudflared/cert.pem                       # Path (container): origin certificate
CREDENTIALS_FILE_LOCAL="$CLOUDFLARED_SOURCE_DIR"/"$TUNNEL_ID".json    # Path (local): tunnel credentials file
CREDENTIALS_FILE_CONTAINER=/etc/cloudflared/"$TUNNEL_ID".json         # Path (container): credentials file
CONFIG_FILE_CONTAINER=/etc/cloudflared/config.yml                     # Path (container): generated config file

# Check if command exists on the system
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Starts docker daemon
start_docker() {
  case "$(uname -s)" in
    Linux*)
      sudo systemctl start docker
      while ! sudo systemctl is-active --quiet docker; do
        sleep 2
      done
      ;;
    Darwin*)
      open -a Docker
      while ! docker info > /dev/null 2>&1; do
        sleep 2
      done
      ;;
    MINGW* | CYGWIN* | MSYS*)
      powershell.exe -Command "Start-Process 'Docker Desktop' -Wait"
      while ! docker info > /dev/null 2>&1; do
          sleep 2
      done
      ;;
    *)
      echo "Could not start Docker Daemon. Linux | Darwin* |MINGW* | CYGWIN* | MSYS* are supported. Build will be tried anyways. If failure occures this could be one reason"
      ;;
  esac
}

# Checks if the Podman machine exists and is running. Uses default machine unless a name is provided.
# Creates and/or starts the machine if it does not exist or is stopped.
start_podman() {
  local MACHINE_NAME="${1:-default}"

  if ! podman machine ls --format "{{.Name}} {{.Running}}" | grep -q "^${MACHINE_NAME} true$"; then
    if podman machine ls --format "{{.Name}}" | grep -q "^${MACHINE_NAME}$"; then
      podman machine start "${MACHINE_NAME}" || {
        echo "Failed to start Podman machine '${MACHINE_NAME}'."
        return 1
      }
    else
      podman machine init "${MACHINE_NAME}" || {
        echo "Failed to create Podman machine '${MACHINE_NAME}'."
        return 1
      }
      podman machine start "${MACHINE_NAME}" || {
        echo "Failed to start Podman machine '${MACHINE_NAME}' after creation."
        return 1
      }
    fi
  fi
  return 0
}

# Determine which container runtime is available: Docker, Podman
if command_exists docker; then
  CONTAINER_RUNTIME="docker"
  start_docker
elif command_exists podman; then
  CONTAINER_RUNTIME="podman"
  start_podman
else
  echo "Neither Podman nor Docker is installed. Please install one of them."
  exit 1
fi

sudo mkdir -p "$TEMP_DIR"/etc/cloudflared                                   # Make temporary directory
sudo cp "$ORIGIN_CERT_LOCAL" "$TEMP_DIR"/"$ORIGIN_CERT_CONTAINER"           # Copy origin certificate to temporary directory
sudo cp "$CREDENTIALS_FILE_LOCAL" "$TEMP_DIR"/"$CREDENTIALS_FILE_CONTAINER" # Copy credentials file to temporary directory

# Description of the dynamically generated cloudflared configuration file:
# - tunnel: Specifies the Tunnel ID used for routing traffic through Cloudflare.
# - credentials-file: Specifies the path to the credentials file used for tunnel authentication.
# - origincert: Specifies the path to the origin certificate used for securing the tunnel.
# - originRequest: Configures various request settings, such as:
#     - noTLSVerify: Whether to verify TLS certificates (false means verification is enabled).
#     - http2Origin: Enables HTTP/2 protocol for origin connections.
#     - noHappyEyeballs: Disables the Happy Eyeballs algorithm, enhancing reliability for IPv6/IPv4 connections.
# - ingress: Defines ingress rules for routing requests:
#     - hostname: Specifies the domain name for incoming requests.
#     - service: Specifies the service URL to route traffic to.
#     - Default ingress route: Provides a fallback service (404 status) for unmatched requests.
sudo tee "$TEMP_DIR$CONFIG_FILE_CONTAINER" > /dev/null <<EOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CREDENTIALS_FILE_CONTAINER}
origincert: ${ORIGIN_CERT_CONTAINER}
originRequest:
  noTLSVerify: false
  http2Origin: true
  noHappyEyeballs: false

ingress:
  - hostname: ${HOSTNAME}
    service: ${SERVICE_URL}
  - service: http_status:404
EOF

# Set permissions directories/files in temp directory
sudo find "$TEMP_DIR" -type d -exec chmod 755 {} +            # Set directory to read/execute
sudo find "$TEMP_DIR" -type f -exec chmod 644 {} +            # Set file to readable

# Remove existing container with same name
$CONTAINER_RUNTIME rm -f "$NAME" || true

# Detects architecture (amd64, arm64, 386, arm, armhf) exits with error if unsupported
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    ARCHITECTURE="amd64"                                      # 64-bit x86
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCHITECTURE="arm64"                                      # 64-bit ARM
elif [ "$ARCH" = "386" ] || [ "$ARCH" = "i386" ]; then
    ARCHITECTURE="386"                                        # 32-bit x86
elif [ "$ARCH" = "arm" ]; then
    ARCHITECTURE="arm"                                        # 32-bit ARM
elif [ "$ARCH" = "armhf" ]; then
    ARCHITECTURE="armhf"                                      # ARM with hardware floating-point support
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Image tag based on version and architecture
IMAGE_TAG="williamveith/cloudflared:${VERSION}.${ARCHITECTURE}"

# Builds image using specified version and architecture
$CONTAINER_RUNTIME build --build-arg VERSION=$VERSION --build-arg ARCHITECTURE=$ARCHITECTURE -t $IMAGE_TAG .

# Deletes temporary directory
sudo rm -rf "$TEMP_DIR"

# Create/start container using built image
$CONTAINER_RUNTIME run -d --name $NAME $IMAGE_TAG