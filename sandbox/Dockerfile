# Atom MVP desktop sandbox image.
#
# Stack: Xvfb + Openbox + xterm + Falkon + x11vnc + noVNC/websockify.
# Display: DISPLAY=:0 (also set in the entrypoint).
#
# Ports inside the container (loopback only; do not publish with docker -p):
#   5900  x11vnc
#   6080  noVNC / websockify  (viewer page: /vnc.html)
#
# Reach 6080 through OpenShell, not a host port mapping:
#   openshell service expose <sandbox> 6080 desktop
# https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview
#
# Ubuntu 24.04 matches the OpenShell default workload base
# (nvcr.io/nvidia/base/ubuntu:24.04) but this image is built locally.
# `--from` does not build a Dockerfile; tag the image, then pass the tag.
#
# chromium-browser and firefox in Ubuntu 24.04 are transitional snap
# packages and are not installed. Falkon is the in-image browser.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:0 \
    SCREEN_GEOMETRY=1280x800x24 \
    VNC_PORT=5900 \
    NOVNC_PORT=6080 \
    LANG=C.UTF-8

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        dbus-x11 \
        falkon \
        fonts-dejavu-core \
        novnc \
        openbox \
        python3-websockify \
        x11-utils \
        x11vnc \
        xterm \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

# OpenShell rejects a root image USER unless the create-time policy sets a
# non-root run_as_user. Ubuntu 24.04 already owns uid/gid 1000 (`ubuntu`),
# so the desktop user is a separate unprivileged account. The MVP policy
# omits `process`, and Docker/Podman then use this USER.
# https://docs.nvidia.com/openshell/how-it-works/policies/default-policy
RUN groupadd --gid 1500 agent \
    && useradd --uid 1500 --gid 1500 --create-home --shell /bin/bash agent \
    && mkdir -p /tmp/.X11-unix /var/lib/xkb \
    && chmod 1777 /tmp/.X11-unix /var/lib/xkb

COPY nopriv.c atom-banner.c /tmp/atom-build/
# Compile the setuid workaround and a tiny labeled X window, then drop the
# compiler. OpenShell returns EPERM for uid/gid syscalls even when the ids
# do not change. The policy schema has no syscall allow. libX11 stays
# because Xvfb already needs it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev libx11-dev \
    && gcc -shared -fPIC -O2 -o /usr/local/lib/libopenshell-nopriv.so /tmp/atom-build/nopriv.c -ldl \
    && gcc -O2 -o /usr/local/bin/atom-banner /tmp/atom-build/atom-banner.c -lX11 \
    && rm -rf /tmp/atom-build \
    && apt-get purge -y gcc libc6-dev libx11-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/atom-desktop-entrypoint
RUN chmod 755 /usr/local/bin/atom-desktop-entrypoint

USER agent
WORKDIR /home/agent

# Documentation only. The process binds 127.0.0.1, not 0.0.0.0.
EXPOSE 6080

# OpenShell starts the trailing `sandbox create` command, not necessarily
# this ENTRYPOINT. scripts/up.sh passes the entrypoint explicitly.
ENTRYPOINT ["/usr/local/bin/atom-desktop-entrypoint"]
