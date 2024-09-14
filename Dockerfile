# Creates pre-configured cloudflare tunnel image
# ARG: VERSION (latest || version_number)
# ARG: ARCHITECTURE (arm64 amd64 386 arm armhf)
# Base Image 1: alpine:3.20 https://hub.docker.com/layers/library/alpine/3.20/images/sha256-33735bd63cf84d7e388d9f6d297d348c523c044410f553bd878c6d7829612735?context=explore
# Base Image 2: scratch https://hub.docker.com/_/scratch/

FROM alpine:3.20 AS builder

ARG VERSION
ARG ARCHITECTURE

# Copy the start_tunnel.c file into the container's root directory
COPY start_tunnel.c /start_tunnel.c

# Determine the architecture or use the provided ARCHITECTURE argument if set
RUN if [ -z "$ARCHITECTURE" ]; then \
        ARCH=$(uname -m) && \
        if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then ARCHITECTURE="amd64"; \
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then ARCHITECTURE="arm64"; \
        elif [ "$ARCH" = "386" ] || [ "$ARCH" = "i386" ]; then ARCHITECTURE="386"; \
        elif [ "$ARCH" = "arm" ]; then ARCHITECTURE="arm"; \
        elif [ "$ARCH" = "armhf" ]; then ARCHITECTURE="armhf"; \
        else echo "Unsupported architecture: $ARCH"; exit 1; fi; \
    fi && \
    echo "Architecture detected: $ARCHITECTURE"

# Set the download URL based on the VERSION argument within the same RUN command to ensure correct scope
RUN apk add --update --no-cache wget binutils gcc musl-dev ca-certificates && \
    update-ca-certificates && \
    if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then \
        DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCHITECTURE}"; \
    else \
        DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/cloudflared-linux-${ARCHITECTURE}"; \
    fi && \
    echo "Using DOWNLOAD_URL: $DOWNLOAD_URL" && \
    # Download cloudflared binary using the DOWNLOAD_URL
    wget -q $DOWNLOAD_URL -O /usr/local/bin/cloudflared && \
    # Strip binary
    strip --strip-unneeded /usr/local/bin/cloudflared && \
    # Compile start_tunnel.c binary executable
    gcc /start_tunnel.c -o /start_tunnel && \
    # Strip binary
    strip --strip-unneeded /start_tunnel && \
    # Remove build-time dependencies
    apk del --purge wget binutils gcc ca-certificates && \
    # Make temp lib directory to store necessary musl libraries
    mkdir -p /temp/lib && \
    # Copy musl libraries to temp lib directory
    cp /lib/*musl* /temp/lib/


# Change ownership of executable binaries to a non-root user for security
RUN addgroup -S cloudflare && adduser -S -G cloudflare cloudflare && \
    chown cloudflare:cloudflare /usr/local/bin/cloudflared /start_tunnel && \
    chmod +x /usr/local/bin/cloudflared /start_tunnel


FROM scratch

USER cloudflare:cloudflare

LABEL org.opencontainers.image.title="Preconfigured Cloudflared Tunnel Image"
LABEL org.opencontainers.image.authors="William Veith <software@williamveith.com>"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.description="This is a preconfigured cloudflared tunnel. During the build phase, configurations are set so this image requires no dependencies or arguments to run"

# Copy credential file & origin cert from local ~/.cloudflared file
COPY temp /
# Copy the cloudflared binary
COPY --from=builder /usr/local/bin/cloudflared /usr/local/bin/cloudflared
# Copy the start_tunnel binary
COPY --from=builder /start_tunnel /usr/local/bin/start_tunnel
# Copy environment file
COPY .env /.env
# Copy non-root user/group information
COPY --from=builder /etc/passwd /etc/group /etc/
# Copy CA certificates for HTTPS connection
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
# Copy all required musl libraries
COPY --from=builder /temp/lib /lib

# Set the start_tunnel executable as the default entry point for the container
ENTRYPOINT ["/usr/local/bin/start_tunnel"]
