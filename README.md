# netpulse-docker

> [!NOTE]
> **This repository is maintained with AI.** The Dockerfile, workflow and
> docs were written and are updated by [Claude Code](https://claude.ai/code)
> (Anthropic), on request of and reviewed by the repository owner. See
> [`CLAUDE.md`](CLAUDE.md) for the instructions the AI works from.

Unofficial, multi-arch Docker image for the
[NetPulse](https://github.com/gnacho/netpulse) server, published to
`ghcr.io/t0bs000r/netpulse`. Not affiliated with the NetPulse project.

The image is kept as small as possible:

- It wraps the upstream release binary (static Go build with the web UI
  embedded), checksum-verified against the release's `checksums.txt`.
- It is Alpine-based with only what the server shells out to: `ssh`,
  `ssh-keygen` and `ssh-keyscan` for polling routers, and GNU `grep` for LAN
  discovery. `ip` and `wget` come from busybox.
- It is a single layer (`FROM scratch` plus one copied root filesystem).
- It runs as an unprivileged user (uid 10001).

Platforms: `linux/amd64`, `linux/arm64` and `linux/arm/v7`. Upstream
releases the server for exactly these.

## Run

```sh
docker run -d --name netpulse --network host \
  -e AUTH_PASS='at-least-10-chars' \
  -v netpulse-data:/data \
  -v /etc/localtime:/etc/localtime:ro \
  ghcr.io/t0bs000r/netpulse:latest
```

Then open `http://<host>:3000`. See [`docker-compose.yml`](docker-compose.yml)
for a compose setup.

Every variable from upstream's
[`server-go/.env.example`](https://github.com/gnacho/netpulse/blob/main/server-go/.env.example)
can be passed with `-e`. `AUTH_PASS` is required.

`/data` holds the SQLite database, the generated SSH keys (`/data/.ssh`) and
TLS material, so keep it on a volume. The image has no timezone database.
Mount `/etc/localtime` as shown above to get local time.

Inside a container, the built-in updater only tells you a new version
exists. To update, pull a newer image.

## Tags

| Tag         | Meaning                       |
|-------------|-------------------------------|
| `2.43.0`    | that exact upstream release   |
| `2.43`, `2` | newest release of that line   |
| `latest`    | newest upstream release       |

## Automation

[`.github/workflows/docker.yml`](.github/workflows/docker.yml) checks
upstream every 6 hours. A new image is pushed only when there is a stable
NetPulse release that isn't on GHCR yet.

Changes to the Dockerfile or workflow are built and smoke-tested on push and
on pull requests, but never published. They ship with the next upstream
release. To publish one sooner, run the workflow by hand with `force`.

GitHub pauses scheduled workflows in repos with no activity for 60 days. If
that happens, re-enable the workflow from the Actions tab.

## License

NetPulse is AGPL-3.0. The image ships its `LICENSE` and `THIRD_PARTY.md` in `/app`.
