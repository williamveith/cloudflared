# This Dockerfile sets up a lightweight, preconfigured Cloudflare tunnel with a minimal footprint,
# ensuring security by running as a non-root user and reducing unnecessary components in the final image.

# Start from an Alpine Linux base image for a lightweight and secure foundation
FROM alpine:3.20 AS builder

# Accept VERSION and ARCHITECTURE as build arguments to customize the build.
# VERSION: Defines the version of the cloudflared binary to be used.
# ARCHITECTURE: Defines the system architecture; if not set, it will be determined automatically.
ARG VERSION=2024.8.3
ARG ARCHITECTURE

# Copy the start_tunnel.c file into the container's root directory
COPY start_tunnel.c /start_tunnel.c

# Set available architectures and versions for the cloudflared binary
# ARCHITECTURE: arm64 amd64
# VERSION: 2024.8.3  2024.8.2  2024.6.1
# Download link for a specific version and architecture of cloudflared binary:
# version: https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/cloudflared-linux-${ARCHITECTURE}
# Link for the latest release:
# latest: https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCHITECTURE}

# Use the provided ARCHITECTURE argument if set; otherwise, determine it automatically
RUN if [ -z "$ARCHITECTURE" ]; then \
        ARCH=$(uname -m) && \
        # Match system architecture to cloudflared naming conventions
        if [ "$ARCH" = "x86_64" ]; then ARCHITECTURE="amd64"; \
        elif [ "$ARCH" = "aarch64" ]; then ARCHITECTURE="arm64"; \
        else echo "Unsupported architecture: $ARCH"; exit 1; fi; \
    fi && \
    echo "Architecture detected: $ARCHITECTURE" && \
    # Install required packages including wget, gcc, and other necessary tools
    apk add --update --no-cache wget binutils gcc musl-dev ca-certificates && \
    update-ca-certificates && \
    # Download the cloudflared binary based on the detected or specified version and architecture
    wget -q https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/cloudflared-linux-${ARCHITECTURE} -O /usr/local/bin/cloudflared && \
    # Strip unnecessary symbols from the binary to reduce its size
    strip --strip-unneeded /usr/local/bin/cloudflared && \
    # Compile the start_tunnel.c file to create the start_tunnel executable
    gcc /start_tunnel.c -o /start_tunnel && \
    # Strip unnecessary symbols from the start_tunnel binary
    strip --strip-unneeded /start_tunnel && \
    # Remove build-time dependencies to keep the image lightweight
    apk del --purge wget binutils gcc ca-certificates && \
    # Prepare a temporary directory to store necessary musl libraries
    mkdir -p /temp/lib && \
    # Copy musl libraries to the temporary directory
    cp /lib/*musl* /temp/lib/

# Change ownership of the cloudflared and start_tunnel binaries to a non-root user for security
RUN addgroup -S cloudflare && adduser -S -G cloudflare cloudflare && \
    chown cloudflare:cloudflare /usr/local/bin/cloudflared /start_tunnel && \
    # Make the binaries executable
    chmod +x /usr/local/bin/cloudflared /start_tunnel

# Create a minimal setup using the scratch base to reduce the size and attack surface of the final image
FROM scratch
# Use the non-root cloudflare user for running the container
USER cloudflare:cloudflare

# Add image metadata for better documentation and management
LABEL org.opencontainers.image.title="Preconfigured Cloudflared Tunnel Image"
LABEL org.opencontainers.image.authors="William Veith <software@williamveith.com>"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.description="This is a preconfigured cloudflared tunnel. During the build phase, configurations are set so this image can be deployed with minimal setup"

# Copy required musl libraries from the builder image
COPY temp /
# Copy the cloudflared binary from the builder stage
COPY --from=builder /usr/local/bin/cloudflared /usr/local/bin/cloudflared
# Copy the start_tunnel binary from the builder stage
COPY --from=builder /start_tunnel /usr/local/bin/start_tunnel
# Copy environment configuration file
COPY .env /.env
# Copy necessary user and group information for the non-root user
COPY --from=builder /etc/passwd /etc/group /etc/
# Copy CA certificates to ensure HTTPS connections work properly
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy all required musl libraries from the temporary directory created in the builder stage
COPY --from=builder /temp/lib /lib

# Set the start_tunnel executable as the default entry point for the container
ENTRYPOINT ["/usr/local/bin/start_tunnel"]
