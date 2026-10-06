#!/usr/bin/env bash
# Create the Atom MVP sandbox and print how to watch the desktop.
#
# Requires the `openshell` CLI and a gateway the CLI can already reach.
# This script does not install OpenShell, does not register a gateway, and
# does not build the image. A missing CLI or a failed `openshell status`
# is a hard stop so CI without a gateway does not look like success.
#
# Command shapes checked against docs on 2026-10-06. Flags that were not
# on those pages are not used.
#   https://docs.nvidia.com/openshell/about/installation
#   https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview
#   https://docs.nvidia.com/openshell/how-it-works/policies/manage-policies

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${ATOM_SANDBOX_NAME:-atom-mvp}"
IMAGE="${ATOM_IMAGE:-atom-desktop:latest}"
POLICY="${ATOM_POLICY:-${ROOT}/policy/mvp-deny-default.yaml}"
NOVNC_PORT="${ATOM_NOVNC_PORT:-6080}"
ENTRYPOINT="/usr/local/bin/atom-desktop-entrypoint"

if ! command -v openshell >/dev/null 2>&1; then
  echo "openshell CLI not found." >&2
  echo "Install (starts a local gateway on a workstation):" >&2
  echo "  curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh" >&2
  echo "  https://docs.nvidia.com/openshell/about/installation" >&2
  exit 1
fi

echo "Checking the selected gateway with 'openshell status'."
# This script does not call 'openshell gateway add'. The installer registers
# https://127.0.0.1:17670 when a user systemd manager exists. The sandbox
# overview sample http://127.0.0.1:18080 is not the installer default.
# On a host without systemd, start the gateway by hand first. See
# docs/spike-notes.md.
if ! openshell status; then
  echo "Gateway is not reachable. Fix 'openshell status' before creating a sandbox." >&2
  exit 1
fi

if [[ ! -f "${POLICY}" ]]; then
  echo "Policy file not found: ${POLICY}" >&2
  exit 1
fi

image_present=0
if command -v docker >/dev/null 2>&1 && docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  image_present=1
elif command -v podman >/dev/null 2>&1 && podman image exists "${IMAGE}" >/dev/null 2>&1; then
  image_present=1
fi
if [[ "${image_present}" -ne 1 ]]; then
  echo "Local image '${IMAGE}' was not found." >&2
  echo "Build it with the same engine the gateway uses, then re-run." >&2
  echo "  docker build -t ${IMAGE} ${ROOT}/sandbox" >&2
  echo "Docker tag '${IMAGE}' is what the Docker driver accepted (no localhost/ prefix)." >&2
  echo "A Podman gateway was not used on the verified host. If the driver is Podman," >&2
  echo "rebuild with that engine and set ATOM_IMAGE to the name it records." >&2
  echo "'openshell sandbox create --from' does not build a Dockerfile." >&2
  echo "https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview" >&2
  exit 1
fi

if openshell sandbox get "${NAME}" >/dev/null 2>&1; then
  echo "Sandbox '${NAME}' already exists. Run scripts/down.sh, wait until it is gone, then re-run." >&2
  exit 1
fi

# Trailing command is the canonical main process. With no command, OpenShell
# starts a login shell instead, so the image ENTRYPOINT is not relied on.
# --detach returns after Ready and keeps that process running.
# Verified with OpenShell 0.1.2 on 2026-10-06. See docs/spike-notes.md.
echo "Creating sandbox '${NAME}' from '${IMAGE}'."
openshell sandbox create \
  --name "${NAME}" \
  --from "${IMAGE}" \
  --policy "${POLICY}" \
  --detach \
  --no-tty \
  -- "${ENTRYPOINT}"

echo "Exposing noVNC on loopback port ${NOVNC_PORT} as service 'desktop'."
openshell service expose "${NAME}" "${NOVNC_PORT}" desktop

echo
echo "Desktop service:"
service_out="$(openshell service get "${NAME}" desktop)"
printf '%s\n' "${service_out}"
desktop_base="$(printf '%s\n' "${service_out}" | grep -oE 'https?://[^[:space:]]+' | head -1 || true)"
if [[ -z "${desktop_base}" ]]; then
  echo "Could not parse a desktop URL from 'openshell service get'." >&2
  exit 1
fi
desktop_base="${desktop_base%/}"
viewer_url="${desktop_base}/vnc.html"
echo
echo "Viewer page: ${viewer_url}"
echo "The service URL does not include /vnc.html. The image serves that path on port ${NOVNC_PORT}."

echo "Waiting for ${viewer_url} to serve the noVNC page."
ready=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 2 "${viewer_url}" | grep -q 'noVNC'; then
    ready=1
    break
  fi
  sleep 0.5
done
if [[ "${ready}" -ne 1 ]]; then
  echo "noVNC did not become reachable at ${viewer_url}." >&2
  echo "If the sandbox phase is Error, read the main-process output with:" >&2
  echo "  openshell sandbox exec --name ${NAME} --no-tty -- cat /tmp/xvfb.log" >&2
  exit 1
fi
echo "noVNC page is up."
echo
echo "Chat URL: none. No model provider is attached."
echo "Shell stand-in until a provider exists:"
echo "  openshell sandbox connect ${NAME}"
echo "  openshell sandbox exec --name ${NAME} --no-tty -- echo atom-desktop"
echo "Docs: https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview"
