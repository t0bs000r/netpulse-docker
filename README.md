# netpulse-docker

Multi-arch Docker image for the [NetPulse](https://github.com/gnacho/netpulse) server,
published to `ghcr.io/t0bs000r/netpulse`.

The image wraps the upstream release binary (static Go build with the web UI
embedded), checksum-verified against the release's `checksums.txt`, on
`debian:trixie-slim` with `openssh-client` and `iproute2`, which the server
uses to poll routers and detect the gateway.

Platforms: `linux/amd64`, `linux/arm64`, `linux/arm/v7` (everything upstream
releases for the server).

## Run

```sh
docker run -d --name netpulse --network host \
  -e AUTH_PASS='at-least-10-chars' \
  -v netpulse-data:/data \
  ghcr.io/t0bs000r/netpulse:latest
```

Then open http://<host>:3000. See `docker-compose.yml` for a compose setup.
Every variable from upstream's
[`server-go/.env.example`](https://github.com/gnacho/netpulse/blob/main/server-go/.env.example)
can be passed with `-e`. `AUTH_PASS` is required.

`/data` holds the SQLite database, generated SSH keys (`/data/.ssh`) and TLS
material. Keep it on a volume.

The built-in updater only reports new versions in a container; update by
pulling a newer image.

## Tags

| Tag       | Meaning                          |
|-----------|----------------------------------|
| `2.43.0`  | exact upstream release           |
| `2.43`, `2` | newest build of that line      |
| `latest`  | newest upstream release          |

## Automation

`.github/workflows/docker.yml` checks upstream every 6 hours and builds and
pushes any stable release that isn't on GHCR yet. It also rebuilds on pushes
to `main` that touch the Dockerfile, and can be run by hand (optionally with
a specific version).

GitHub pauses scheduled workflows after 60 days without commits to the repo.
If that happens, re-enable it from the Actions tab.

## License

NetPulse is AGPL-3.0; the image ships its `LICENSE` and `THIRD_PARTY.md` in `/app`.
