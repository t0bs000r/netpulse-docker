# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
#
# NetPulse server (https://github.com/gnacho/netpulse) packaged from the
# upstream release binaries. Upstream ships static CGO-free builds for
# linux/amd64, linux/arm64 and linux/arm/v7 with the web UI embedded, so no
# Go/Node toolchain is needed here: we download the tarball for the target
# arch and verify it against the release's checksums.txt.

ARG NETPULSE_VERSION=2.43.0

FROM --platform=$BUILDPLATFORM debian:trixie-slim AS fetch
ARG NETPULSE_VERSION
ARG TARGETARCH
ARG TARGETVARIANT
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /dl
RUN set -eu; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)  arch=amd64 ;; \
      arm64)  arch=arm64 ;; \
      armv7)  arch=armv7 ;; \
      *) echo "unsupported platform: ${TARGETARCH}${TARGETVARIANT}" >&2; exit 1 ;; \
    esac; \
    v="${NETPULSE_VERSION#v}"; \
    base="https://github.com/gnacho/netpulse/releases/download/v${v}"; \
    file="netpulse_${v}_linux_${arch}.tar.gz"; \
    curl -fsSLO "${base}/${file}"; \
    curl -fsSLO "${base}/checksums.txt"; \
    grep " ${file}\$" checksums.txt | sha256sum -c -; \
    mkdir out; tar -xzf "${file}" -C out; \
    test -x out/netpulse

FROM debian:trixie-slim
ARG NETPULSE_VERSION
LABEL org.opencontainers.image.title="netpulse" \
      org.opencontainers.image.description="NetPulse home network monitoring server" \
      org.opencontainers.image.version="${NETPULSE_VERSION}" \
      org.opencontainers.image.url="https://github.com/gnacho/netpulse" \
      org.opencontainers.image.licenses="AGPL-3.0"

# Runtime tools the server shells out to: ssh/ssh-keygen/ssh-keyscan (router
# polling and key management), ip (gateway autodetection) and GNU grep -P
# (LAN discovery). tzdata so TZ works.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates openssh-client iproute2 grep tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /data --shell /usr/sbin/nologin netpulse \
 && mkdir -p /app /data && chown netpulse:netpulse /data

COPY --from=fetch /dl/out/netpulse /app/netpulse
COPY --from=fetch /dl/out/LICENSE /dl/out/THIRD_PARTY.md /app/

# The server reads ./.env from its working directory (optional) and resolves
# relative paths against it; DATA_DIR holds the SQLite DB, SSH keys and TLS
# material, so mount a volume there.
WORKDIR /app
ENV PORT=3000 \
    DATA_DIR=/data \
    HOME=/data \
    SSH_KEY_PATH=/data/.ssh/id_ed25519
VOLUME ["/data"]
EXPOSE 3000

USER netpulse
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${PORT} && printf 'GET /api/health HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && head -n1 <&3 | grep -q ' 200 '"]
ENTRYPOINT ["/app/netpulse"]
