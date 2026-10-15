# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
#
# NetPulse server (https://github.com/gnacho/netpulse) packaged from the
# upstream release binaries. Upstream ships static CGO-free builds for
# linux/amd64, linux/arm64 and linux/arm/v7 with the web UI embedded, so no
# Go/Node toolchain is needed: we download the tarball for the target arch,
# verify it against the release's checksums.txt and drop it on Alpine.
#
# The final image has two layers: the unmodified Alpine base (shared with
# other Alpine images and cached across updates) and one layer with the
# runtime packages, the user and the netpulse binary.

ARG NETPULSE_VERSION=2.43.0
ARG ALPINE_VERSION=3.22

# Download + verify on the build host (no QEMU needed for this part).
FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS fetch
ARG NETPULSE_VERSION
ARG TARGETARCH
ARG TARGETVARIANT
WORKDIR /dl
RUN set -eu; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64) arch=amd64 ;; \
      arm64) arch=arm64 ;; \
      armv7) arch=armv7 ;; \
      *) echo "unsupported platform: ${TARGETARCH}${TARGETVARIANT}" >&2; exit 1 ;; \
    esac; \
    v="${NETPULSE_VERSION#v}"; \
    base="https://github.com/gnacho/netpulse/releases/download/v${v}"; \
    file="netpulse_${v}_linux_${arch}.tar.gz"; \
    wget -q "${base}/${file}" "${base}/checksums.txt"; \
    grep " ${file}\$" checksums.txt | sha256sum -c -; \
    mkdir -p /out/app; \
    tar -xzf "${file}" -C /out/app netpulse LICENSE THIRD_PARTY.md; \
    test -x /out/app/netpulse

FROM alpine:${ALPINE_VERSION} AS base

# Install what the server needs on top of Alpine, then collect only the
# files that differ from the pristine base into /overlay. The final image is
# the untouched Alpine layer plus that one overlay layer.
# Runtime tools the server shells out to: ssh, ssh-keygen, ssh-keyscan
# (router polling, key management) and GNU grep for `grep -P` (LAN
# discovery). `ip` and `wget` (healthcheck) come from busybox.
FROM base AS overlay
COPY --from=fetch /out/app /app
RUN --mount=type=bind,from=base,target=/base \
    set -euo pipefail; \
    apk add --no-cache openssh-client-default grep; \
    adduser -S -D -H -u 10001 -h /data -s /sbin/nologin netpulse; \
    mkdir -p /data; \
    chown netpulse /data; \
    find / -mindepth 1 \( -path /base -o -path /proc -o -path /sys -o -path /dev \
      -o -path /tmp -o -path /run -o -path /etc/hosts -o -path /etc/hostname \
      -o -path /etc/resolv.conf \) -prune -o -print \
    | while IFS= read -r f; do \
        b="/base$f"; \
        if [ -L "$f" ]; then \
          [ -L "$b" ] && [ "$(readlink "$f")" = "$(readlink "$b")" ] && continue; \
        elif [ -e "$b" ] && [ ! -L "$b" ] \
             && [ "$(stat -c %F:%u:%g:%a "$f")" = "$(stat -c %F:%u:%g:%a "$b")" ]; then \
          [ -d "$f" ] && continue; \
          cmp -s "$f" "$b" && continue; \
        fi; \
        echo "$f"; \
      done > /tmp/changed; \
    mkdir /overlay; \
    tar -cf - --no-recursion -T /tmp/changed | tar -xpf - -C /overlay

FROM base
ARG NETPULSE_VERSION
COPY --from=overlay /overlay/ /

LABEL org.opencontainers.image.title="netpulse" \
      org.opencontainers.image.description="NetPulse home network monitoring server (unofficial image)" \
      org.opencontainers.image.version="${NETPULSE_VERSION}" \
      org.opencontainers.image.url="https://github.com/gnacho/netpulse" \
      org.opencontainers.image.licenses="AGPL-3.0"

# Configuration comes from environment variables (see upstream
# server-go/.env.example). DATA_DIR holds the SQLite DB, SSH keys and TLS
# material, so mount a volume there. No WORKDIR on purpose: it would add a
# third layer, and the server only uses its working directory to look for
# an optional .env file.
ENV PORT=3000 \
    DATA_DIR=/data \
    HOME=/data \
    SSH_KEY_PATH=/data/.ssh/id_ed25519
VOLUME ["/data"]
EXPOSE 3000

USER netpulse
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["sh", "-c", "wget -q -O /dev/null http://127.0.0.1:${PORT}/api/health || exit 1"]
ENTRYPOINT ["/app/netpulse"]
