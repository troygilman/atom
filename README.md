# Atom

Atom is a minimal agent environment on [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell). The MVP is two things:

1. Talk to an agent inside an OpenShell sandbox.
2. See that agent's desktop in a browser (noVNC).

Multi-tenant gateways, connectors, hibernation, billing, and the rest of a product platform are out of scope. The design is in [docs/architecture.md](docs/architecture.md).

The desktop path was run on OpenShell 0.1.2 (Docker driver) on 2026-10-06. Commands that worked, and what is still blocked, are in [docs/spike-notes.md](docs/spike-notes.md). Chat is not built: there was no model provider or API key.

## What is in the tree

| Path | Role |
| --- | --- |
| [sandbox/Dockerfile](sandbox/Dockerfile) | Desktop image: Xvfb, Openbox, xterm, Falkon, x11vnc, noVNC. `DISPLAY=:0`. noVNC on `127.0.0.1:6080`. Non-root user `agent` (uid 1500). |
| [sandbox/entrypoint.sh](sandbox/entrypoint.sh) | Starts that stack and stays in the foreground on websockify. |
| [policy/mvp-deny-default.yaml](policy/mvp-deny-default.yaml) | OpenShell policy stub. No network rules, so egress is deny-by-default. Model API and chat-bridge allowlists are comments only. |
| [scripts/up.sh](scripts/up.sh) | Creates one sandbox from the image, exposes noVNC, prints the desktop service and the chat gap. |
| [scripts/down.sh](scripts/down.sh) | Deletes that sandbox. |

## MVP goals

- One sandbox with a visible desktop and, later, an agent process.
- A chat path from the operator to that agent. Not built yet.
- A browser desktop via OpenShell service expose, not a published VNC port.
- A hand-written deny-by-default policy. Allowlists stay empty until the real model host and agent binary are known.

## How to run

These steps need a workstation with Docker (or Podman) and OpenShell. They are not run in CI here.

### 1. Install OpenShell

Follow [Installation](https://docs.nvidia.com/openshell/about/installation). The documented installer is:

```sh
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
openshell status
```

`openshell status` must succeed before `scripts/up.sh`. The script does not register a gateway. The installer default that worked is `https://127.0.0.1:17670` (mTLS). The sandbox overview's `http://127.0.0.1:18080` sample is a different port. A host with no systemd user manager does not get a gateway from the installer; start one as in [docs/spike-notes.md](docs/spike-notes.md).

### 2. Build the desktop image

`--from` does not build a Dockerfile. Build and tag first ([Manage Sandboxes](https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview)):

```sh
docker build -t atom-desktop:latest sandbox
```

The verified driver was Docker, and the image name it accepted was `atom-desktop:latest` with no `localhost/` prefix. Podman was not used.

Ubuntu 24.04's `chromium-browser` and `firefox` packages are snap stubs, so the image installs Falkon instead.

### 3. Create the sandbox and open the desktop

```sh
./scripts/up.sh
```

The script runs, in order:

```sh
openshell sandbox create \
  --name atom-mvp \
  --from atom-desktop:latest \
  --policy policy/mvp-deny-default.yaml \
  --detach \
  -- /usr/local/bin/atom-desktop-entrypoint

openshell service expose atom-mvp 6080 desktop
openshell service get atom-mvp desktop
```

Overrides: `ATOM_SANDBOX_NAME`, `ATOM_IMAGE`, `ATOM_POLICY`, `ATOM_NOVNC_PORT`.

Open the viewer URL the script prints. On the verified gateway that was `http://default--atom-mvp--desktop.openshell.localhost:17670/vnc.html`. The service base URL does not include `/vnc.html`. The VNC session is view-only and bound to loopback, with no password baked into the image.

### 4. Chat

There is no chat URL yet, and no model API key was available. OpenShell takes model credentials through a provider (`openshell provider`, then `sandbox create --provider`), not a secret in this repo. Until that exists, the stand-in is:

```sh
openshell sandbox connect atom-mvp
openshell sandbox exec --name atom-mvp --no-tty -- echo atom-desktop
```

### 5. Tear down

```sh
./scripts/down.sh
```

That runs `openshell sandbox delete atom-mvp`. Delete can return before cleanup finishes. If it does, wait until `openshell sandbox get atom-mvp` no longer finds the sandbox.

## Verify against the docs before trusting a failure

- [Installation](https://docs.nvidia.com/openshell/about/installation) — `openshell status`, local gateway.
- [Manage Sandboxes](https://docs.nvidia.com/openshell/how-it-works/sandboxes/overview) — `--from`, `--detach`, trailing command, `service expose`, `sandbox delete`.
- [Manage Sandbox Policies](https://docs.nvidia.com/openshell/how-it-works/policies/manage-policies) — `--policy` at create time.
- [Default Policy](https://docs.nvidia.com/openshell/how-it-works/policies/default-policy) — no network rules means egress denied; non-root image `USER`.
- [Policy schema](https://docs.nvidia.com/openshell/how-it-works/policies/schema)
- [First network policy](https://docs.nvidia.com/openshell/tutorials/first-network-policy) — shape used in the policy comments.
- [GitHub NVIDIA/OpenShell](https://github.com/NVIDIA/OpenShell)

## Next spike

Desktop and noVNC are running. See [docs/spike-notes.md](docs/spike-notes.md).

Still open: add one agent process in the same sandbox and a thin chat bridge. That needs a model provider attached to the sandbox. Then uncomment a real model-API allowlist in the policy and check that a random host is still denied.

Do not add tenancy, connectors, or hibernation until chat works.
