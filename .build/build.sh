#!/bin/bash

# Enable exporting of all variables defined in the script and sourced files
set -o allexport
# Load environment variables from the .env file
source .env
# Disable exporting of variables
set +o allexport

# Define source and temporary directories
SOURCE_DIR=~/.cloudflared       # Directory where cloudflared-related files are stored locally
TEMP_DIR=temp                   # Temporary directory to store files before transferring to the container

# Define paths for the origin certificate (both local and inside the container)
ORIGIN_CERT_LOCAL="$SOURCE_DIR"/cert.pem                  # Local path to the origin certificate
ORIGIN_CERT_CONTAINER=/etc/cloudflared/cert.pem           # Path inside the container for the origin certificate

# Define paths for the credentials file (both local and inside the container)
CREDENTIALS_FILE_LOCAL="$SOURCE_DIR"/"$TUNNEL_ID".json    # Local path to the tunnel credentials file
CREDENTIALS_FILE_CONTAINER=/etc/cloudflared/"$TUNNEL_ID".json  # Path inside the container for the credentials file

# Define path for the configuration file inside the container
CONFIG_FILE_CONTAINER=/etc/cloudflared/config.yml


# Function to check if a command exists on the system
command_exists() {
    command -v "$1" >/dev/null 2>&1  # Check if the command is available and suppress output
}

# Determine which container runtime is available: prefer Docker, fall back to Podman
if command_exists docker; then
    CONTAINER_RUNTIME="docker"
elif command_exists podman; then
    CONTAINER_RUNTIME="podman"
else
    echo "Neither Podman nor Docker is installed. Please install one of them."
    exit 1
fi

# Display which container runtime will be used
echo "Using $CONTAINER_RUNTIME as the container runtime."

# Create necessary directories and copy certificates and credentials to the temporary directory
sudo mkdir -p "$TEMP_DIR"/etc/cloudflared
sudo cp "$ORIGIN_CERT_LOCAL" "$TEMP_DIR"/"$ORIGIN_CERT_CONTAINER" # Copy origin certificate to the temporary directory
sudo cp "$CREDENTIALS_FILE_LOCAL" "$TEMP_DIR"/"$CREDENTIALS_FILE_CONTAINER" # Copy credentials file to the temporary directory

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

# Set permissions for directories and files in the temporary directory
sudo find "$TEMP_DIR" -type d -exec chmod 755 {} +  # Set directory permissions to be readable and executable
sudo find "$TEMP_DIR" -type f -exec chmod 644 {} +  # Set file permissions to be readable

# Remove any existing container with the same name, ignore errors if not found
$CONTAINER_RUNTIME rm -f "$NAME" || true

# Determine the architecture of the current machine
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    ARCHITECTURE="amd64"              # Set architecture to amd64 if the system is 64-bit x86
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCHITECTURE="arm64"              # Set architecture to arm64 if the system is 64-bit ARM
else
    # Exit if the architecture is unsupported
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Define the image tag based on the version and architecture
IMAGE_TAG="cloudflared:${VERSION}-${ARCHITECTURE}"

# Build the Docker or Podman image using the specified version and architecture
$CONTAINER_RUNTIME build --build-arg VERSION=$VERSION --build-arg ARCHITECTURE=$ARCHITECTURE -t $IMAGE_TAG .

# Remove the temporary directory and its contents
sudo rm -rf "$TEMP_DIR"

# Create and start the container using the built image
$CONTAINER_RUNTIME run -d --name $NAME $IMAGE_TAG