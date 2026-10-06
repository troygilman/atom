#!/usr/bin/env bash
# Tear down the Atom MVP sandbox.
#
# https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview
# Delete stops processes, releases resources, and purges injected credentials.
# The command can return while cleanup is still pending ("deletion accepted").

set -euo pipefail

NAME="${ATOM_SANDBOX_NAME:-atom-mvp}"

if ! command -v openshell >/dev/null 2>&1; then
  echo "openshell CLI not found. Nothing to tear down from here." >&2
  echo "https://docs.nvidia.com/openshell/about/installation" >&2
  exit 1
fi

echo "Deleting sandbox '${NAME}'."
openshell sandbox delete "${NAME}"

echo "If the CLI said cleanup is pending, wait until this no longer finds it:"
echo "  openshell sandbox get ${NAME}"
echo "An already-absent sandbox is a successful no-op. Missing workspaces and authorization failures are still errors."
