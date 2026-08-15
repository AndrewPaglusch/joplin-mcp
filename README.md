# joplin-mcp

Runs [Joplin](https://github.com/laurent22/joplin)'s native MCP server from the Joplin terminal app in Docker. Joplin added an MCP server in the 3.7 pre-release but doesn't publish a terminal/MCP image, so this repo builds the terminal app from source and pushes one to GHCR whenever they cut a new 3.x release.

## Image

```
ghcr.io/andrewpaglusch/joplin-mcp
```

Tags follow Joplin's `vMAJOR.MINOR.PATCH` scheme (the `v` is dropped):

- `latest` (most recent 3.x release)
- `3` (latest 3.x)
- `3.7` (latest 3.7.x)
- `3.7.10` (specific release)

## Usage

`docker-compose.yml`:

```yaml
services:
  joplin-mcp:
    image: ghcr.io/andrewpaglusch/joplin-mcp:latest
    container_name: joplin-mcp
    restart: unless-stopped
    environment:
      - JOPLIN_SERVER_URL=https://your-joplin-server
      - JOPLIN_SERVER_EMAIL=you@example.com
      - JOPLIN_SERVER_PASSWORD=your-password
      - JOPLIN_SYNC_INTERVAL=300
      - JOPLIN_E2EE_PASSWORD=          # empty = disabled
    volumes:
      - ./profile:/profile
    # front it with a reverse proxy that handles auth, forwarding to :8080
```

The container syncs from your Joplin Server and serves `POST /mcp` on port `8080` with no auth of its own. If this is being exposed to any untrusted networks, you need to **bring your own auth** (via a proxy). Every MCP tool is disabled by default; the entrypoint enables all of them except the AI-dependent tools (`semantic_search_notes`, `read_image`). To read end-to-end-encrypted notes, set `JOPLIN_E2EE_PASSWORD` to your master password.

## How it works

A GitHub Actions workflow runs daily at 06:00 UTC. It checks the latest `v3.x` tag on the [upstream repo](https://github.com/laurent22/joplin), and if there isn't already an image in GHCR for that version, it builds the terminal app from source at that tag and pushes.

Joplin's REST API binds only to localhost, so the image runs nginx alongside it to expose `/mcp` on `0.0.0.0:8080`. Right now only `linux/amd64` is built.

## Manual builds

You can trigger a build from the Actions tab. There are two optional inputs:

- `tag`: build a specific Joplin release tag instead of the latest one
- `force`: rebuild even if the image tag already exists in GHCR

## Notes

I don't maintain Joplin itself. For bugs, features, or anything about how the app or its MCP server actually works, please go to the [upstream repo](https://github.com/laurent22/joplin). Issues here should be limited to packaging problems (build failures, missing tags, etc).
