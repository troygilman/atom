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
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1280x800x24}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
NOVNC_WEB="${NOVNC_WEB:-/usr/share/novnc}"

cleanup() {
  # Kill the display stack we started. Ignore jobs that already exited.
  kill 0 2>/dev/null || true
}
trap cleanup TERM INT

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

echo "atom-desktop: starting Xvfb on ${DISPLAY} (${SCREEN_GEOMETRY})"
Xvfb "${DISPLAY}" -screen 0 "${SCREEN_GEOMETRY}" -ac +extension GLX +render -noreset &

ready=0
for _ in $(seq 1 50); do
  if xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "${ready}" -ne 1 ]]; then
  echo "atom-desktop: Xvfb did not become ready on ${DISPLAY}" >&2
  exit 1
fi

echo "atom-desktop: starting openbox"
openbox &

# A terminal makes the screen obviously alive before any browser starts.
xterm -geometry 100x30+40+40 -title "Atom desktop" -e bash -lc \
  'echo "Atom desktop (DISPLAY=${DISPLAY:-unset}). Watch-only VNC."; exec bash' &

# Falkon is a real Ubuntu deb (Qt WebEngine). The Ubuntu chromium and
# firefox packages are snap stubs and do not run in this image.
# Chromium-based browsers usually need --no-sandbox as non-root in a
# container. TODO: confirm Falkon actually starts on the first image build;
# the CLI flag is not assumed, only the Qt WebEngine environment variable.
if command -v falkon >/dev/null 2>&1; then
  QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox" \
    falkon about:blank >/tmp/falkon.log 2>&1 &
fi

echo "atom-desktop: x11vnc on 127.0.0.1:${VNC_PORT} (view-only, no password)"
# -viewonly matches the MVP watch-only desktop.
# -localhost keeps VNC off the container's non-loopback interfaces.
# TODO: a VNC password, if wanted, must be injected at runtime. Do not bake one
# into the image. https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview
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
