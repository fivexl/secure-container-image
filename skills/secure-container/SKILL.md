---
name: secure-container
description: Harden a Dockerfile or container image on FivexL's distroless secure-container-image bases. Use when the user asks to harden, secure, slim down or reduce CVEs in a Dockerfile or container image, to move an app to distroless or non-root, or to create a new production Dockerfile for a Go, Rust, Python or Node.js app.
---

# Secure container

Upstream: https://github.com/fivexl/secure-container-image

## Images and tags

Registry: `ghcr.io/fivexl/`.

| Runtime | Image | Plain tags | With AWS RDS CA bundle | With a shell, for troubleshooting |
|---|---|---|---|---|
| Static binary (Go `CGO_ENABLED=0`, Rust musl) | `secure-container-image-base` | `debian13` | `debian13-rds` | none |
| Python 3.13 | `secure-container-image-base-python3` | `python3.13-debian13` | `python3.13-debian13-rds` | `python3.13-debian13-dev` |
| Node.js 26 | `secure-container-image-base-nodejs` | `node26-debian13` | `node26-debian13-rds` | `node26-debian13-dev` |

Facts every base shares: Google distroless Debian 13, `linux/amd64` and
`linux/arm64`, user `nonroot` uid/gid 65532, `WORKDIR /app` owned by 65532,
`TMPDIR=/tmp`, no shell (`-dev` adds busybox at `/busybox/sh`), no package
manager, and lprobe at `/usr/bin/lprobe`, copied from `ghcr.io/fivexl/lprobe:0.2.3`.
The Node.js base sets `ENTRYPOINT ["/usr/bin/dumb-init", "--", "/nodejs/bin/node"]`.
The Python base's entrypoint is the Python interpreter.

Matching builders, so the runtime's libc, interpreter and ABI match:

| Runtime | Builder |
|---|---|
| Static | `golang:<version>-trixie` with `CGO_ENABLED=0`, or a Rust musl target |
| Python | `debian:13` with apt `python3` (3.13), not `python:3.13-*`, whose interpreter lives in `/usr/local/bin`, so its virtualenv points at a Python the runtime lacks |
| Node.js | `node:26-trixie` |

Examples. Read the one that matches the runtime before proposing a base, then
adapt it to the app; link it rather than copying it:

- Go: https://github.com/fivexl/secure-container-image/tree/main/examples/go_app_example
- Python with uv: https://github.com/fivexl/secure-container-image/tree/main/examples/python_examples
- Node.js with `npm ci`: https://github.com/fivexl/secure-container-image/tree/main/examples/node_examples
- Go entrypoint instead of Bash, for Envoy: https://github.com/fivexl/secure-container-image/tree/main/examples/envoy_example
  and the rationale: https://github.com/fivexl/secure-container-image#entrypoints-in-go-not-bash

If the example cannot be read, say so and name the facts above you could not
check against it.

## 1. Inspect

For an existing image, read the Dockerfile, its build context, the entrypoint
scripts, the compose files or Kubernetes manifests that run it, and the CI that
builds it. Build the current image if it is not local (`<name>:before`), then
`docker image inspect` it for user, entrypoint, exposed ports and healthcheck;
Verify scans it as the baseline. For a new image, get the same facts
from the source tree, the dependency manifests and the user.

Inspect is done when every item below has a finding with the file and line
that shows it, or "none found":

- **Runtime type.** Static binary, glibc-linked binary, Python, Node.js, or
  something else. For Go, check for `cgo`, `CGO_ENABLED=1`, or dependencies
  such as `mattn/go-sqlite3`. For a compiled binary, `ldd` or `file` in the
  builder settles it.
- **Native dependencies.** Python wheels or Node addons with compiled code,
  the shared libraries they and the app load (`ldd`), and OS packages used at
  runtime (`libpq`, `ffmpeg`, `imagemagick`, fonts, a browser). Note whether
  today's base is Alpine: musl-built wheels and addons do not load on glibc.
- **Subprocesses.** `subprocess(..., shell=True)`, `os.system`,
  `child_process.exec`, `exec.Command("sh", ...)`, or calls to CLI tools.
- **Signal handling and PID 1.** Shell-form `CMD`/`ENTRYPOINT` (`CMD node app.js`
  runs as `/bin/sh -c`, which these bases lack, so it fails to start), wrapper
  scripts without `exec`, and whether the app handles `SIGTERM`: Python and
  Node.js as PID 1 ignore it unless they install a handler. On the Node.js
  base, dumb-init is PID 1, so node exits on `SIGTERM` without one.
- **Entrypoint script.** Is it trivial (`cd`, `export` and one command, which
  map to `WORKDIR`, `ENV` and `CMD`), or real logic: validating env vars,
  rendering config with `envsubst`/`sed`, waiting for dependencies, running
  migrations?
- **Writable paths.** Every path the app writes: caches, uploads, temp files,
  pid files, `HOME`, `.pyc` files, `node_modules/.cache`. A read-only root
  filesystem leaves only mounted volumes and a tmpfs on `/tmp` writable.
- **User and ownership.** Current `USER`, `chown` to other uids, and
  `runAsUser` or volume ownership in deployments.
- **Ports.** A non-root process binds a port below 1024 only where the
  runtime lowers `net.ipv4.ip_unprivileged_port_start`: Docker does, many
  Kubernetes runtimes do not, and `NET_BIND_SERVICE` does not help uid 65532.
- **Secrets and build context.** `.dockerignore`, broad `COPY . .`,
  credentials in `ARG` or `ENV`, and package-manager tokens (`.npmrc`,
  `pip.conf`, `GOPRIVATE`) that end up in a layer.
- **TLS.** RDS hostnames (`*.rds.amazonaws.com`), `sslmode=verify-full`,
  a downloaded `global-bundle.pem`, private CAs, `NODE_EXTRA_CA_CERTS`, and a
  client-level CA option (`ca:` in Node.js, `sslrootcert` in libpq).
- **Healthcheck.** What it runs (`curl`, `wget`, a script) and what it proves.
  An endpoint that always returns 200 proves only that the port is open; one
  that checks the database proves more but can restart the app when the
  database is down. Note which one it is, and any Kubernetes probes.
- **How it runs.** Service or batch job, its port, and the arguments,
  environment, mounts and dependencies it needs to start. Verify reuses this.
- **Update policy.** Does the user follow floating tags, pin digests, or
  rebuild on a schedule? Is there Dependabot or Renovate?

## 2. Propose

Show the user the findings, then a list of changes. Every finding maps to a
proposed change with a one-line reason, or to "no change needed". Propose is
done when the user approves the list; change no file before that.

- **Base and variant.** Pick the image from the table by runtime type; a
  runtime with no row goes to "When the app does not fit". When the app runs
  an older major today (Node.js 20, Python 3.11), propose the upgrade as its
  own change, with the app's tests run on the new major; if the user declines
  it, the app does not fit. Distroless removes packages, not bytes: the image
  can end up larger than an Alpine one, so promise fewer CVEs, not a smaller
  image. Propose `-rds`
  only when the app talks TLS to RDS: the plain tags do not trust the RDS CAs,
  and most apps do not need them. For Node.js the `-rds` base sets
  `NODE_EXTRA_CA_CERTS`. If the app also trusts a private CA, propose one
  combined bundle with both; a client-level CA option bypasses the extra CA
  store, so point it at the bundle too. Propose `-dev` only for
  troubleshooting: rebuild on it, swap it in, swap back. It lacks the RDS
  bundle.
- **Multi-stage build.** Build in the matching builder from the table, copy
  only the artifacts into the runtime stage, and `COPY --chown=65532:65532`
  only what the app must write. Use the lockfile: `uv sync --frozen --no-dev`,
  `go build -trimpath`, and `npm ci --omit=dev` when the build needs no dev
  dependencies. When it does (TypeScript, a bundler), run `npm ci` and the
  build in the builder, then copy the output and production dependencies
  only. For Python, build the virtualenv in `/app/.venv` on `debian:13` and
  start the app with `/app/.venv/bin/python`, as the Python example does.
  Matching the ABI does not supply missing shared libraries: list the ones
  Inspect found and check each exists in the runtime image.
- **Secrets.** Narrow `.dockerignore` and `COPY`. Delete credentials nothing
  uses; move the rest out of `ARG`/`ENV` into `RUN --mount=type=secret` or
  runtime configuration. A credential that was ever in a pushed image is
  leaked: tell the user to rotate it.
- **Exec-form entrypoint.** Use JSON-array `ENTRYPOINT`/`CMD`. On the Node.js
  base, set only `CMD ["server.js"]`: a new `ENTRYPOINT` replaces dumb-init,
  and node becomes PID 1.
- **SIGTERM.** If the app ignores `SIGTERM` as PID 1, propose a signal handler
  in the app. Until it lands, `docker run --init` adds an init process in
  Docker; Kubernetes has no equivalent.
- **Healthcheck.** Replace `curl` or `wget` with lprobe, keeping the endpoint;
  ask before changing what it proves:
  `HEALTHCHECK CMD ["lprobe", "-mode=http", "-endpoint=/health", "-port=8080"]`.
  Kubernetes ignores `HEALTHCHECK`; there, choose readiness and liveness
  separately. A dependency check belongs in the `readinessProbe`; the
  `livenessProbe` checks only what a restart can repair.
- **Entrypoint script.** If it is trivial, drop it and move its parts to
  `WORKDIR`, `ENV` and `ENTRYPOINT`, or `CMD` on the Node.js base. If it is real
  logic, propose a small Go entrypoint that validates input, renders config
  into `$TMPDIR` and replaces itself with the process through `syscall.Exec`,
  and link the Envoy example. Rendering config with `envsubst` in a shell
  needs a shell and lets an env var inject config.
- **Subprocesses.** Replace shell calls with direct exec of the binary, or
  with a library. If the app truly needs a CLI tool at runtime, see "When the
  app does not fit".
- **Port.** Move a port below 1024 to 8080 or another port above 1024,
  through the app's port setting (`ENV PORT=8080`) where it has one, and map
  it outside (`-p 80:8080`, a Service `targetPort`). Then it binds as uid
  65532 with `--cap-drop=ALL` on any runtime, with no sysctl or capability.
- **Writable paths.** Point temp and cache paths at `/tmp`. Give every other
  writable path a volume. The root filesystem stays read-only.
- **User.** In the runtime stage, remove `useradd`, `USER root`, and `chown`
  to other uids; builder stages keep theirs. In deployments, set
  `runAsUser: 65532` and fix volume ownership.
- **Tag or digest.** Follow the update policy Inspect found; ask only if it
  found none. A floating tag gets the daily patched base when the build pulls
  it (`docker build --pull`). Prefer the versioned tag (`python3.13-debian13`)
  over `latest`, so a runtime major upgrade is a deliberate change. A digest
  pin (`FROM <image>:<tag>@sha256:<digest>`) is reproducible but patches
  nothing until someone bumps it; pair it with Dependabot or Renovate.
- **Hardened run flags.** `--read-only --cap-drop=ALL --security-opt=no-new-privileges
  --user 65532 --tmpfs /tmp:uid=65532,mode=1777`. In Kubernetes:
  `runAsNonRoot: true`, `runAsUser: 65532`, `readOnlyRootFilesystem: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
  `seccompProfile.type: RuntimeDefault`, and an `emptyDir` on `/tmp`.
- **Scheduled rebuild.** Propose a daily or weekly CI job that rebuilds with
  `--pull --no-cache`, runs the tests and a vulnerability scan, then redeploys.
  The upstream bases rebuild daily; the user's image gets those fixes only
  through this loop.

### When the app does not fit

Say so, and propose the base-independent steps instead of a base switch:
non-root, a read-only root filesystem, dropped capabilities, an unprivileged
port, exec-form commands, no secrets in layers and the scheduled rebuild.
Common cases:

- **glibc-linked binary** (cgo, Rust `-gnu`, Envoy): the static base has no
  libc. Build static if the code allows. Otherwise pick the distroless image
  that has the libraries Inspect found: `gcr.io/distroless/base-nossl-debian13`
  for glibc only, `base-debian13` to add OpenSSL, `cc-debian13` to add
  libstdc++ (each with the `:nonroot` tag). Copy lprobe in, as the Envoy
  example does with Envoy's own distroless image.
- **Alpine or musl-only dependencies:** rebuild them for glibc on Debian 13.
  If that is not possible, stay on Alpine and apply the base-independent steps.
- **Needs a shell or OS tools at runtime** (cron, supervisord, `ffmpeg`, a
  browser): keep a slim Debian base and apply the base-independent steps.
- **Other runtimes** (Java, Ruby, PHP, .NET, other Python or Node.js majors):
  no base here. Point to the matching distroless or slim upstream image and
  apply the base-independent steps.

lprobe can be copied into any image with
`COPY --from=<lprobe image> /lprobe /usr/bin/lprobe`, using the lprobe image
named under "Images and tags".

## 3. Apply

After the user approves:

- In a git repository, create a branch and edit the files in place. Outside
  git, write the new file beside the old one (`Dockerfile.hardened`), with
  its own `Dockerfile.hardened.dockerignore` so the old build is unchanged,
  and leave files the new build no longer uses in place. Say before you
  delete a Dockerfile, entrypoint or manifest.
- Change only what the user approved.
- Update everything that depends on the image: compose files, manifests,
  CI build arguments, documentation that names the old user or port.

## 4. Verify

Run each step and show the output. Report each as passed, failed or not run,
with the reason for not run. Remove the containers you start, on success or
failure, after collecting diagnostics.

1. Build: `docker build --pull -t <name>:hardened -f <Dockerfile> <context>`.
   Record the base digest it used:
   `docker buildx imagetools inspect <base image>:<tag>` prints it as `Digest:`.
2. Run it with the hardened flags plus the arguments, environment, mounts and
   dependencies recorded under "How it runs". For a service on `<port>`
   with a `HEALTHCHECK`, also add a fast healthcheck and an unprivileged host
   port:

   ```shell
   cid=$(docker run -d --read-only --cap-drop=ALL --security-opt=no-new-privileges \
     --user 65532 --tmpfs /tmp:uid=65532,mode=1777 \
     --health-interval=2s --health-retries=3 --health-start-period=10s \
     -p 127.0.0.1::<port> <name>:hardened)
   ```

   For a batch job, run it in the foreground; it passes when it exits 0 with
   the expected output.
3. For a service, wait with a deadline. With a `HEALTHCHECK` the last line
   must print `running healthy`; without one, `running no-healthcheck`.
   Anything else fails: show `docker logs` and `docker inspect -f '{{json .State}}'`.

   ```shell
   for _ in $(seq 60); do
     [ "$(docker inspect -f '{{.State.Status}}' "$cid")" = running ] || break
     [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$cid")" = healthy ] && break
     sleep 1
   done
   docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$cid"
   ```

4. Call one real endpoint through the mapped port
   (`docker port "$cid" <port>/tcp`), and exercise every writable path and
   subprocess recorded in Inspect.
5. Check `SIGTERM`: `time docker stop -t 10 "$cid"` should return in a few
   seconds, not after the 10-second timeout.
6. If `cosign` is available and the base is a FivexL image, verify the digest
   recorded in step 1:

   ```shell
   cosign verify ghcr.io/fivexl/<image>@sha256:<digest> \
     --certificate-identity https://github.com/fivexl/secure-container-image/.github/workflows/family.yml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com
   ```

   Another publisher's base is verified only by that publisher's documented
   policy; otherwise report it as not verified.
7. If a scanner such as Trivy is available, scan `<name>:hardened` and
   `<name>:before` and compare the counts by severity.

Finish with a short summary. List every approved change as done, blocked
(with the reason) or deferred by the user, and every Verify step as passed,
failed or not run.
