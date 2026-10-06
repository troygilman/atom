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
echo "TODO: this script does not call 'openshell gateway add'. Doc examples disagree on the local URL (install: https://127.0.0.1:17670, sandbox overview sample: http://127.0.0.1:18080). Use the gateway the installer already registered."
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
  echo "  # Podman gateway: podman build -t localhost/${IMAGE} ${ROOT}/sandbox" >&2
  echo "  # then set ATOM_IMAGE=localhost/${IMAGE}" >&2
  echo "'openshell sandbox create --from' does not build a Dockerfile." >&2
  echo "https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview" >&2
  exit 1
fi

# Trailing command is the canonical main process. With no command, OpenShell
# starts a login shell instead, so the image ENTRYPOINT is not relied on.
# --detach returns after Ready and keeps that process running.
# TODO: not executed in this repo's CI. Re-check `openshell sandbox create --help`
# on the installed CLI before treating a failure as an image bug.
echo "Creating sandbox '${NAME}' from '${IMAGE}'."
openshell sandbox create \
  --name "${NAME}" \
  --from "${IMAGE}" \
  --policy "${POLICY}" \
  --detach \
  -- "${ENTRYPOINT}"

echo "Exposing noVNC on loopback port ${NOVNC_PORT} as service 'desktop'."
openshell service expose "${NAME}" "${NOVNC_PORT}" desktop

echo
echo "Desktop URL (gateway-managed; loopback gateways use an openshell.localhost host):"
openshell service get "${NAME}" desktop
echo "TODO: confirm whether that URL already ends at /vnc.html. The image serves noVNC at /vnc.html on port ${NOVNC_PORT}."
echo
echo "Chat URL: none. This scaffold has no chat HTTP service."
echo "TODO: chat glue. Until an agent process exists, attach with:"
echo "  openshell sandbox connect ${NAME}"
echo "Docs: https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview"
