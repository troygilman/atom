# Spike notes (OpenShell 0.1.2, 2026-10-06)

Verified on this host with the Docker driver. Podman was not installed. Chat was not attempted: no model provider and no API key were present. Do not put either in the repo.

## What worked

Gateway (installer default, not the sandbox-overview sample port 18080):

```text
https://127.0.0.1:17670
```

`openshell status` after a manual gateway start:

```text
Gateway: openshell
Server: https://127.0.0.1:17670
Status: Connected
Authentication: Authenticated (mTLS transport)
Version: 0.1.2
```

Image name the Docker driver accepted:

```sh
docker build -t atom-desktop:latest sandbox
```

No `localhost/` prefix. `--from` does not build a Dockerfile.

Sandbox and viewer:

```sh
openshell sandbox create \
  --name atom-mvp \
  --from atom-desktop:latest \
  --policy policy/mvp-deny-default.yaml \
  --detach \
  --no-tty \
  -- /usr/local/bin/atom-desktop-entrypoint

openshell service expose atom-mvp 6080 desktop
openshell service get atom-mvp desktop
```

Service URL shape (workspace `default`, sandbox `atom-mvp`, service `desktop`):

```text
http://default--atom-mvp--desktop.openshell.localhost:17670/
```

Viewer page, appended by hand (the service URL does not include it):

```text
http://default--atom-mvp--desktop.openshell.localhost:17670/vnc.html
```

The hostname resolves to loopback. The gateway listens on `127.0.0.1:17670`. Inside the sandbox, websockify listens on `127.0.0.1:6080` and x11vnc on `127.0.0.1:5900`. A request before the desktop process is listening returns HTTP 502. A sandbox whose phase is not Ready returns HTTP 412.

Shell stand-in for chat:

```sh
openshell sandbox connect atom-mvp
openshell sandbox exec --name atom-mvp --no-tty -- echo atom-desktop
```

## Gateway on a host without systemd

The official installer is:

```sh
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
```

https://docs.nvidia.com/openshell/about/installation

On this VM, PID 1 is not systemd, so the installer installed the 0.1.2 deb and skipped the user gateway. These commands started it. Certs stay under the user home, not in the repo.

```sh
openshell-gateway generate-certs \
  --output-dir "${HOME}/.local/state/openshell/tls" \
  --server-san host.openshell.internal

OPENSHELL_LOCAL_TLS_DIR="${HOME}/.local/state/openshell/tls" \
OPENSHELL_COMPUTE_DRIVER=docker \
  openshell-gateway

openshell gateway add https://127.0.0.1:17670 --local --name openshell
openshell status
```

This host's Docker daemon needed `fuse-overlayfs` (nested overlayfs returns "invalid argument"). That is host setup, not an image change.

## Xvfb keymap failure, and the fix

Plain `docker run` of `atom-desktop:latest` starts Xvfb. The same binary under the MVP policy exits with:

```text
XKB: Failed to compile keymap
Failed to activate virtual core keyboard: 2
```

`/usr/bin/xkbcomp` itself succeeds inside the sandbox. Xorg's `Popen` calls `setgid(getgid())` and `setuid(getuid())` before exec of `xkbcomp`. Both return `EPERM` (errno 1) even though the process is already uid/gid 1500. The child then exits 127 and Xvfb treats the keymap compile as failed. The policy schema has Landlock filesystem rules and no syscall allow, so this is not something `policy/mvp-deny-default.yaml` can permit.

`sandbox/nopriv.c` is loaded for the desktop processes (`LD_PRELOAD=/usr/local/lib/libopenshell-nopriv.so`). It ignores `setuid`, `setgid`, `seteuid`, `setegid`, `setresuid`, and `setresgid` failure when the requested id is already current. A real id change still fails.

`/var/lib/xkb` is mode 1777 in the image and `read_write` in the policy because that is where Xvfb writes the compiled keymap.

`/dev/pts` and `/dev/ptmx` are `read_write`. With those paths, `python3` `os.openpty()` succeeds inside the sandbox. `/dev/tty` is also listed, and `open("/dev/tty")` still returns EACCES (Landlock does not treat that node like `/dev/null`). xterm then prints `open ttydev: Permission denied` and exits. The visible desktop does not depend on it: `atom-banner` draws the "Atom desktop" window, and Falkon opens an empty page.

Falkon is started with `QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox --no-zygote --disable-gpu"`. `--no-zygote` avoids the Chromium credential drop that also gets EPERM (`credentials.cc`). Ubuntu's `chromium` and `firefox` packages are snap stubs and are not installed.

`atom-banner` is a small Xlib window titled "Atom desktop" so the screen is identifiable even if the terminal cannot open a pty.

## Still blocked

- No chat process and no model provider. `openshell provider create` plus `sandbox create --provider` is the documented credential path. No provider profile was configured, and no key was in the environment. Do not pass a key with `--env`.
- Network policy stays deny-by-default until a real model host and agent binary path exist. The commented hosts in the policy are placeholders.
- VNC is view-only and has no password. The gateway URL is the viewer path.
- `scripts/up.sh` waits until `/vnc.html` contains `noVNC`. It does not click Connect in a browser.
