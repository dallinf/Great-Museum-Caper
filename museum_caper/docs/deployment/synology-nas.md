# Deploying Museum Caper to a Synology NAS

This guide deploys Museum Caper as a private Phoenix release container on a Synology NAS using Container Manager.

The fastest path is:

1. Build a Docker image locally.
2. Copy the image and Compose project to the NAS.
3. Run it with Synology Container Manager or over SSH.

Museum Caper currently stores lobby and game state in memory. Restarting the container clears active rooms and games. That is fine for a local/private prototype, but it is not durable hosting.

## References

- Synology Container Manager supports managing multi-container projects from Compose files: https://www.synology.com/en-us/dsm/feature/docker
- Synology Project docs: https://kb.synology.com/en-global/DSM/help/ContainerManager/docker_project?version=7
- Phoenix deployment docs describe the required production pieces: secrets, assets, and starting the server: https://phoenix.hexdocs.pm/deployment.html
- Phoenix releases package the Erlang VM, application code, dependencies, and runtime config into a production artifact: https://phoenix.hexdocs.pm/releases.html

## Prerequisites

On your development machine:

- Docker with Buildx enabled.
- SSH access to the NAS if you want the automated deploy script.

On the Synology NAS:

- DSM 7.x with Container Manager installed from Package Center.
- A shared folder such as `/volume1/docker`.
- SSH enabled for the automated path: Control Panel > Terminal & SNMP > Enable SSH service.

Know your NAS CPU architecture:

```sh
ssh YOUR_USER@YOUR_NAS 'uname -m'
```

Use:

- `PLATFORM=linux/amd64` for `x86_64` Synology models.
- `PLATFORM=linux/arm64` for `aarch64`/ARM64 models.

## Files Added for Deployment

- `Dockerfile`: builds a production Phoenix release image.
- `.dockerignore`: keeps local build artifacts out of Docker builds.
- `deploy/synology/docker-compose.yml`: Container Manager project definition.
- `deploy/synology/museum-caper.env.example`: environment template.
- `scripts/synology-build-image.sh`: builds and packages a Synology deploy bundle.
- `scripts/synology-deploy-ssh.sh`: copies the bundle to the NAS, loads the image, and starts Compose.

## Option A: Automated Build and SSH Deploy

From the project root, build a NAS-ready bundle:

```sh
PLATFORM=linux/amd64 \
PHX_HOST=192.168.1.50 \
HOST_PORT=4000 \
scripts/synology-build-image.sh
```

Change `PHX_HOST` to your NAS IP address, hostname, or internal DNS name.

The script writes:

```txt
deploy/synology/dist/
  museum-caper-<tag>-linux-amd64.tar.gz
  docker-compose.yml
  .env
```

Then deploy over SSH:

```sh
NAS_HOST=192.168.1.50 \
NAS_USER=your-synology-user \
NAS_PATH=/volume1/docker/museum-caper \
scripts/synology-deploy-ssh.sh
```

Open:

```txt
http://192.168.1.50:4000
```

### Updating Later

Build a fresh image and redeploy:

```sh
PLATFORM=linux/amd64 PHX_HOST=192.168.1.50 scripts/synology-build-image.sh
NAS_HOST=192.168.1.50 NAS_USER=your-synology-user scripts/synology-deploy-ssh.sh
```

The script loads the new image and runs:

```sh
docker compose --env-file .env up -d
```

If your Synology only has the legacy command, the script falls back to `docker-compose`.

## Option B: Manual Container Manager Project

Use this if you do not want to enable SSH.

1. Build the image bundle locally:

   ```sh
   PLATFORM=linux/amd64 PHX_HOST=192.168.1.50 scripts/synology-build-image.sh
   ```

2. In Synology File Station, create:

   ```txt
   /volume1/docker/museum-caper
   ```

3. Upload these files from `deploy/synology/dist/` into that folder:

   ```txt
   museum-caper-<tag>-linux-amd64.tar.gz
   docker-compose.yml
   .env
   ```

4. Load the image. The most reliable way is a one-time SSH command:

   ```sh
   cd /volume1/docker/museum-caper
   gzip -dc museum-caper-<tag>-linux-amd64.tar.gz | docker load
   ```

   If you prefer the UI, use Container Manager's image import feature if your DSM version exposes it.

5. In Container Manager:

   - Open Project.
   - Click Create.
   - Use `/volume1/docker/museum-caper` as the project path.
   - Use the uploaded `docker-compose.yml`.
   - Create and start the project.

6. Open:

   ```txt
   http://192.168.1.50:4000
   ```

## Environment Variables

The generated `.env` contains:

```dotenv
IMAGE_NAME=museum-caper
TAG=<generated tag>
HOST_PORT=4000
PHX_HOST=192.168.1.50
PHX_URL_SCHEME=http
PHX_URL_PORT=4000
PHX_CHECK_ORIGIN=http://192.168.1.50:4000
PHX_SERVER=true
PORT=4000
SECRET_KEY_BASE=<generated secret>
```

Important values:

- `SECRET_KEY_BASE`: required by Phoenix to sign/encrypt cookies. Keep it private.
- `PHX_HOST`: the host/IP users type into the browser.
- `HOST_PORT`: the NAS port exposed to your LAN.
- `PHX_URL_SCHEME` and `PHX_URL_PORT`: use `http`/`4000` for direct LAN access.
- `PHX_CHECK_ORIGIN`: comma-separated browser origins allowed to connect LiveView.

If you want both a LAN URL and a DuckDNS URL to work, set `PHX_HOST` to the canonical public hostname and list both origins:

```dotenv
PHX_HOST=dallinfrandsen.duckdns.org
PHX_URL_SCHEME=http
PHX_URL_PORT=4040
PHX_CHECK_ORIGIN=http://192.168.86.41:4040,http://dallinfrandsen.duckdns.org:4040
```

For an existing Synology deployment, edit the NAS `.env` directly:

```sh
cd /volume1/docker/museum-caper
sudo cp .env .env.bak-origins

sudo sed -i 's/^PHX_HOST=.*/PHX_HOST=dallinfrandsen.duckdns.org/' .env
sudo sed -i 's/^HOST_PORT=.*/HOST_PORT=4040/' .env
sudo sed -i 's/^PHX_URL_SCHEME=.*/PHX_URL_SCHEME=http/' .env
sudo sed -i 's/^PHX_URL_PORT=.*/PHX_URL_PORT=4040/' .env
sudo sed -i 's|^PHX_CHECK_ORIGIN=.*|PHX_CHECK_ORIGIN=http://192.168.86.41:4040,http://dallinfrandsen.duckdns.org:4040|' .env

sudo docker compose --env-file .env up -d
```

If your Synology uses the legacy Compose command, use this final restart command instead:

```sh
sudo docker-compose --env-file .env up -d
```

## HTTPS with Synology Reverse Proxy

For a polished private setup, put Synology's reverse proxy in front of the container.

1. Keep the container listening on internal port `4000`.
2. In DSM, create a reverse proxy rule from `https://museum-caper.your-domain` to `http://127.0.0.1:4000`.
3. Build with SSL redirects enabled:

   ```sh
   PHX_FORCE_SSL=true \
   PHX_HOST=museum-caper.your-domain \
   HOST_PORT=4000 \
   scripts/synology-build-image.sh
   ```

4. Edit the generated `.env`:

   ```dotenv
   PHX_HOST=museum-caper.your-domain
   PHX_URL_SCHEME=https
   PHX_URL_PORT=443
   PHX_CHECK_ORIGIN=https://museum-caper.your-domain
   ```

5. Deploy as usual.

For direct LAN HTTP, leave `PHX_FORCE_SSL=false`, which is the script default.

## Troubleshooting

### Browser redirects to HTTPS unexpectedly

You probably built with SSL redirects enabled. Rebuild with:

```sh
PHX_FORCE_SSL=false scripts/synology-build-image.sh
```

Then redeploy.

### Container starts and exits

Check logs:

```sh
ssh YOUR_USER@YOUR_NAS 'cd /volume1/docker/museum-caper && docker compose logs --tail=100 web'
```

Common causes:

- Missing `SECRET_KEY_BASE` in `.env`.
- The image tag in `.env` does not match the loaded image.
- The NAS architecture does not match the build platform.

### Port already in use

Change `HOST_PORT` in `.env`, then restart:

```sh
docker compose --env-file .env up -d
```

For example:

```dotenv
HOST_PORT=4010
PHX_URL_PORT=4010
```

### Wrong architecture image

If `docker load` works but the container cannot start, check architecture:

```sh
ssh YOUR_USER@YOUR_NAS 'uname -m'
```

Rebuild with the matching platform:

```sh
PLATFORM=linux/arm64 scripts/synology-build-image.sh
```

or:

```sh
PLATFORM=linux/amd64 scripts/synology-build-image.sh
```

### Active games disappear

That is expected for this prototype. Game state is in memory. Restarting or recreating the container clears rooms and active games.
