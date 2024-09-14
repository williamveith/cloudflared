# Table of Contents

1. [Cloudflared Tunnel Setup](#cloudflared-tunnel-setup)
2. [What This Setup Does](#what-this-setup-does)
3. [How to Run](#how-to-run)
4. [Configuration That MUST Be Changed by the User](#configuration-that-must-be-changed-by-the-user)
5. [Configuration That MAY Need to be Changed](#configuration-that-may-need-to-be-changed)
6. [Prerequisites](#prerequisites)
   - [Example Commands to Create These Prerequisites](#example-commands-to-create-these-prerequisites)
7. [Environment Variables in .env](#environment-variables-in-env)
8. [Troubleshooting](#troubleshooting)
9. [Conclusion](#conclusion)

## Cloudflared Tunnel Setup

IMPORT: CERTAIN VARIABLES IN .env NEED TO BE CHANGED FOR THE PROJECT TO WORK FOR YOU. READ SECTION Configuration That MUST Be Changed by the User.

This repository contains a setup for building a containerized image that runs a preconfigured Cloudflare tunnel using cloudflared. This setup allows you to create prebuilt images that encapsulate all necessary configurations, credentials, and dependencies. With these prebuilt images, deploying a secure and robust Cloudflare tunnel can be done quickly and easily without needing further configuration changes during deployment.

By using this approach, you can ensure consistent, repeatable deployments of your Cloudflare tunnel across different environments, leveraging the benefits of containerization with Docker or Podman.

## What This Setup Does

- **Environment Configuration**: Loads environment variables from a `.env` file to configure the tunnel, credentials, and other necessary settings.
- **Dynamic File Preparation**: Dynamically generates configuration files, including the tunnel credentials and origin certificate, and sets appropriate permissions.
- **Container Image Build**: Builds a Docker or Podman image based on the specified `cloudflared` version and architecture.
- **Container Deployment**: Deploys the built image, setting up the tunnel to run automatically inside a container.

## How to Run

To set up and run the tunnel, execute the following command from the root of this project:

```bash
./.build/build.sh
```

This script will automatically:

1. Determine the available container runtime (Docker or Podman).
2. Prepare the necessary directories and files, including certificates and configuration files.
3. Build the container image with the appropriate architecture.
4. Deploy the container, starting the tunnel with the specified settings.

## Configuration That MUST Be Changed by the User

Before running the setup, you need to adjust specific values in the `.env` file to match your Cloudflare tunnel configuration:

- **`TUNNEL_ID`**: Set this to your actual Cloudflare tunnel ID. This value is unique to your tunnel and is required for the tunnel to authenticate and operate correctly.

  ```env
  TUNNEL_ID=2dfa47fb-2f7d-48bc-93e7-9bc25c5420e5
  ```
  
- **`HOSTNAME`**: Set this to the hostname that will be used by the tunnel. This should match the domain or subdomain you have configured in your Cloudflare account.

  ```env
  HOSTNAME=example.com
  ```

## Configuration That MAY Need to be Changed

The following configurations use standard values but may need adjustment depending on your project setup or if the version is out of date:

- **`SERVICE_URL`**: Defines the backend service URL that Cloudflare will route traffic to. This should be set according to your application's specific endpoint:

  ```env
  SERVICE_URL=http://host.docker.internal:8000
  ```

- **`VERSION`**: Specifies the version of `cloudflared` to be used. It must be no older than one year to ensure compatibility. The version format follows `year.month.update` (e.g., `2024.8.3`). Check for the latest version here:
  [Version Release Manifest](https://github.com/cloudflare/cloudflared/releases)

  ```env
  VERSION=2024.8.3
  ```

## Prerequisites

- **Existing Tunnel**: Ensure that the Cloudflare tunnel has been created using the `cloudflared` command-line tool. You must have used `cloudflared` to generate the required credentials and certificate files.
  
- **Required Files**:
  - **Origin Certificate**: The certificate (`cert.pem`) authenticating your server's connection with Cloudflare. This should be located at `~/.cloudflared/cert.pem`.
  - **Tunnel Credential JSON**: The JSON file containing your tunnel credentials. It should be named after your `TUNNEL_ID` and located in `~/.cloudflared/[TUNNEL_ID].json`.

### Example Commands to Create These Prerequisites

```bash
cloudflared login
cloudflared tunnel create my-tunnel
cloudflared tunnel route dns my-tunnel example.com
```

1. **Login to Cloudflare and Download the Origin Certificate**:

    Use this command to authenticate your server with Cloudflare and download the origin certificate (`cert.pem`). This step is necessary to create and run tunnels securely.

    ```bash
    cloudflared login
    ```

2. **Create a Tunnel**:

    This command creates a new tunnel with a specified name. The tunnel name (`[TUNNEL_NAME]`) serves as an identifier within your Cloudflare account but does not directly affect how traffic is routed. When you run this command, `cloudflared` generates a credentials file named after your tunnel, such as `[TUNNEL_NAME].json`, which will be located at `~/.cloudflared/[TUNNEL_ID].json`.

    ```bash
    cloudflared tunnel create [TUNNEL_NAME]
    ```

    Replace `[TUNNEL_NAME]` with a friendly name for your tunnel, like `my-tunnel`. This name helps you identify and manage your tunnel within your Cloudflare account.

3. **Route Traffic to Your Domain or Subdomain**:

    After creating the tunnel, you need to associate it with a domain or subdomain in your Cloudflare account. This command sets up DNS routing, linking your specified hostname to the created tunnel.

    ```bash
    cloudflared tunnel route dns [TUNNEL_NAME] [DOMAIN_SUBDOMAIN]
    ```

    - Replace `[TUNNEL_NAME]` with the name of your tunnel.
    - Replace `[DOMAIN_SUBDOMAIN]` with the domain or subdomain you want to use for routing traffic (e.g., `example.yourdomain.com`).

## Environment Variables in `.env`

The `.env` file contains all necessary configurations, including paths and log levels. Here are the key variables:

- **`NAME`**: The name of the container (`cloudflared` by default).
- **`VERSION`**: Specifies the version of `cloudflared` to be used.
- **`SERVICE_URL`**: Defines the backend service URL that Cloudflare will route traffic to.
- **`LOG_LEVEL`**: Sets the log level for `cloudflared` (e.g., `debug`).
- **`CONFIG`**: Path to the generated configuration file inside the container.
- **`ORIGIN_CERT`**: Path to the origin certificate inside the container.

## Troubleshooting

- Ensure that Docker or Podman is installed and correctly configured on your system.
- Check that the required environment variables are set correctly, particularly `TUNNEL_ID` and `HOSTNAME`.
- Verify that the necessary files (`cert.pem` and the tunnel credentials JSON) are present in the `~/.cloudflared` directory.

## Conclusion

This setup streamlines the deployment of a Cloudflare tunnel using Docker or Podman. By modifying a few key configurations and ensuring that your tunnel is set up correctly with Cloudflare, you can quickly deploy a secure and reliable tunneling solution.

For further assistance, please consult the [Cloudflare documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
