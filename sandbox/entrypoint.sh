#!/bin/bash
# Desktop stack for the Atom OpenShell MVP image.
#
# DISPLAY=:0 is the virtual screen. noVNC listens on 127.0.0.1:6080 and
# proxies to x11vnc on 127.0.0.1:5900. Both ports stay on loopback so a
# host publish is not required; OpenShell service expose is the viewer path.
#
# https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview
# ("Run the service on loopback inside the sandbox, expose its port")

set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
# OpenShell's supervisor can launch the main process with a short PATH.
# Xvfb runs xkbcomp as /usr/bin/xkbcomp via /bin/sh, which needs this PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin${PATH:+:$PATH}"
# Xvfb and xterm call setuid/setgid/setegid to drop privileges they do not
# have. OpenShell returns EPERM. See sandbox/nopriv.c.
export LD_PRELOAD=/usr/local/lib/libopenshell-nopriv.so
mkdir -p /tmp/runtime-agent
chmod 700 /tmp/runtime-agent
export XDG_RUNTIME_DIR=/tmp/runtime-agent
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1280x800x24}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
NOVNC_WEB="${NOVNC_WEB:-/usr/share/novnc}"

cleanup() {
  # Kill the display stack we started. Ignore jobs that already exited.
  kill 0 2>/dev/null || true
}
trap cleanup TERM INT

mkdir -p /tmp/.X11-unix /home/agent
# The image creates this directory as root mode 1777. chmod fails for the
# unprivileged user when the directory already has the right mode.
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

echo "atom-desktop: starting Xvfb on ${DISPLAY} (${SCREEN_GEOMETRY})"
Xvfb "${DISPLAY}" -screen 0 "${SCREEN_GEOMETRY}" -ac +extension GLX +render -noreset \
  >/tmp/xvfb.log 2>&1 &
xvfb_pid=$!

ready=0
for _ in $(seq 1 100); do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "${ready}" -ne 1 ]]; then
  echo "atom-desktop: Xvfb did not become ready on ${DISPLAY} (pid ${xvfb_pid})" >&2
  cat /tmp/xvfb.log >&2 || true
  exit 1
fi

echo "atom-desktop: starting openbox"
openbox >/tmp/openbox.log 2>&1 &

# A labeled window that does not need a pty. xterm also starts when /dev/pts
# is writable under the policy.
atom-banner >/tmp/atom-banner.log 2>&1 &
xterm -geometry 90x18+80+400 -title "Atom desktop" -e bash -lc \
  'echo "Atom desktop (DISPLAY=${DISPLAY:-unset}). Watch-only VNC."; exec bash' \
  >/tmp/xterm.log 2>&1 &

# Falkon is a real Ubuntu deb (Qt WebEngine). The Ubuntu chromium and
# firefox packages are snap stubs and do not run in this image.
# --no-sandbox is required as non-root. --no-zygote skips the credential
# drop OpenShell rejects with EPERM (credentials.cc).
if command -v falkon >/dev/null 2>&1; then
  QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --no-zygote --disable-gpu" \
    falkon about:blank >/tmp/falkon.log 2>&1 &
fi

echo "atom-desktop: x11vnc on 127.0.0.1:${VNC_PORT} (view-only, no password)"
# -viewonly matches the MVP watch-only desktop.
# -localhost keeps VNC off the container's non-loopback interfaces.
# A VNC password, if wanted later, must be injected at runtime. Do not bake
# one into the image.
# https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview
x11vnc \
  -display "${DISPLAY}" \
  -forever \
  -shared \
  -viewonly \
  -rfbport "${VNC_PORT}" \
  -localhost \
  -nopw \
  -bg \
  -o /tmp/x11vnc.log

echo "atom-desktop: noVNC/websockify on 127.0.0.1:${NOVNC_PORT} (page /vnc.html)"
# Foreground process keeps the container alive. OpenShell records the sandbox
# as finished when this main process exits.
exec websockify --web="${NOVNC_WEB}" "127.0.0.1:${NOVNC_PORT}" "127.0.0.1:${VNC_PORT}"
