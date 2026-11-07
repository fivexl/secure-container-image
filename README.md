[![FivexL](https://releases.fivexl.io/like-this-repo-banner.png)](https://fivexl.io/#email-subscription)

### Want practical AWS infrastructure insights?

👉 [Subscribe to our newsletter](https://fivexl.io/#email-subscription) to get:

- Real stories from real AWS projects  
- No-nonsense DevOps tactics  
- Cost, security & compliance patterns that actually work  
- Expert guidance from engineers in the field

=========================================================================

# secure-container-image

![Build and push Docker images](https://github.com/fivexl/secure-container-image/actions/workflows/ci.yml/badge.svg?branch=main)

Minimal runtime base images for containerized apps. Each image is Google [distroless](https://github.com/GoogleContainerTools/distroless) Debian 13 with no shell and no package manager. It runs as the `nonroot` user (uid 65532) and adds [lprobe](https://github.com/fivexl/lprobe) for exec-form `HEALTHCHECK`s. The images are built for `linux/amd64` and `linux/arm64`.

> **Using `secure-container-image-base` from before November 2026?** It moved from Alpine to Debian distroless, and its user changed from uid 2323 to 65532. See [Migrating from the Alpine-Based `secure-container-image-base`](#migrating-from-the-alpine-based-secure-container-image-base), which includes a one-line rollback.

## Images

| Image | Built from | For |
|---|---|---|
| `ghcr.io/fivexl/secure-container-image-base` | `gcr.io/distroless/static-debian13` | Static binaries: Go with `CGO_ENABLED=0`, Rust with musl |
| `ghcr.io/fivexl/secure-container-image-base-python3` | `gcr.io/distroless/python3-debian13` | Python 3.13 apps |
| `ghcr.io/fivexl/secure-container-image-base-nodejs` | `gcr.io/distroless/nodejs26-debian13` | Node.js 26 apps |

Every image sets `WORKDIR /app`, owned by uid 65532, and `TMPDIR=/tmp`. The Node.js image runs `dumb-init` as PID 1 with `ENTRYPOINT ["/usr/bin/dumb-init", "--", "/nodejs/bin/node"]`, so `CMD ["server.js"]` works and `SIGTERM` reaches your app.

### Tags

| Image | Tags | With the AWS RDS CA bundle | With a shell, for troubleshooting |
|---|---|---|---|
| `secure-container-image-base` | `latest`, `debian13` | `latest-rds`, `debian13-rds` | none |
| `secure-container-image-base-python3` | `latest`, `python3.13-debian13` | `latest-rds`, `python3.13-debian13-rds` | `latest-dev`, `python3.13-debian13-dev` |
| `secure-container-image-base-nodejs` | `latest`, `node26-debian13` | `latest-rds`, `node26-debian13-rds` | `latest-dev`, `node26-debian13-dev` |

The `-rds` variants trust the [AWS RDS global certificate bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html) in addition to the system CAs. It is appended to `/etc/ssl/certs/ca-certificates.crt` and also kept on its own as `/etc/ssl/certs/aws-rds.crt`. For Node.js, the `-rds` variant sets `NODE_EXTRA_CA_CERTS` to that file, because Node.js ignores the system CA file by default. Use the plain tags unless your app connects to RDS over TLS.

The `-dev` variants are built from distroless `:debug-nonroot` and add a busybox shell at `/busybox/sh`. Use one only to troubleshoot: rebuild your app on it, swap it in, then swap back. It does not include the RDS CA bundle. The static base has no `-dev` variant; to debug a static binary, attach a debug container to it, for example with `kubectl debug`.

Every image carries the label `io.fivexl.image.variant` (`production`, `rds` or `dev`), so admission policies can tell variants apart, for example to reject `dev` in production.

### Updates

CI rebuilds every image daily without cache, from floating upstream tags and unpinned packages, so each build includes the latest upstream security fixes. CI publishes a build only after it passes a Trivy scan (fixable `HIGH` and `CRITICAL`) and smoke tests on both platforms. Temporary scan exceptions live in `.trivyignore.yaml`, and each one expires on a set date.

All tags float. Follow a tag to get the daily patches. To freeze an image, pin its digest:

```dockerfile
FROM ghcr.io/fivexl/secure-container-image-base:debian13@sha256:<digest>
```

A floating base patches nothing until you rebuild and redeploy your image. Rebuild your app images on a schedule as well, daily or weekly, then test and redeploy them.

## Migrating from the Alpine-Based `secure-container-image-base`

Before this change, `secure-container-image-base` was Alpine 3.18 files on `scratch`. The new image keeps the name and changes the contents:

| | Before | Now |
|---|---|---|
| User | `app`, uid 2323 | `nonroot`, uid 65532 |
| `TMPDIR` | `/app/tmp` | `/tmp` |
| RDS CA bundle | always included | only in `latest-rds` and `debian13-rds` |
| OS files | Alpine | Debian 13 distroless |

To migrate:

- In Dockerfiles, replace `--chown=app:app` or `--chown=2323` with `--chown=65532:65532`, and `USER app` with `USER 65532`.
- In deployments, set `runAsUser: 65532`, fix the ownership of persistent volumes, and mount a writable `/tmp` (for example an `emptyDir`) when the root filesystem is read-only.
- If your app connects to RDS, switch to `latest-rds`.

To roll back, pin the last Alpine build:

```dockerfile
FROM ghcr.io/fivexl/secure-container-image-base:legacy-alpine
```

Old `:<commit sha>` tags stay in place.

## Verify an Image

CI signs each published image with keyless [cosign](https://github.com/sigstore/cosign) and attaches a signed SPDX SBOM to each platform image.

```shell
cosign verify ghcr.io/fivexl/secure-container-image-base:latest \
  --certificate-identity https://github.com/fivexl/secure-container-image/.github/workflows/family.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# The SBOM attestation is on the platform image, not on the multi-platform index.
image=ghcr.io/fivexl/secure-container-image-base
digest=$(docker buildx imagetools inspect "$image:latest" --raw \
  | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')
cosign verify-attestation --type spdxjson "$image@$digest" \
  --certificate-identity https://github.com/fivexl/secure-container-image/.github/workflows/family.yml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Each image also carries BuildKit SBOM and provenance attestations:

```shell
docker buildx imagetools inspect ghcr.io/fivexl/secure-container-image-base:latest --format '{{json .Provenance}}'
```

## Examples

The `examples` directory holds one app per base and an Envoy proxy. CI builds them against the bases from the same commit, scans them and runs them with `--read-only --cap-drop=ALL --security-opt=no-new-privileges`. They are not published.

- `examples/go_app_example/Dockerfile.goapp`: a static Go binary on `secure-container-image-base`.
- `examples/node_examples/Dockerfile.node-app`: an Express 5 app on `secure-container-image-base-nodejs`, installed with `npm ci --omit=dev`.
- `examples/python_examples/Dockerfile.py-app-uv`: a uvicorn and pandas app on `secure-container-image-base-python3`. The builder is `debian:13` with its own `python3`, the same interpreter and ABI as the runtime, and `uv sync --frozen` installs the dependencies into `/app/.venv`.
- `examples/envoy_example/Dockerfile.envoy`: Envoy in front of an app, configured from environment variables by a Go entrypoint. See [Entrypoints in Go, Not Bash](#entrypoints-in-go-not-bash).

Each example listens on port 8080, so it needs no `NET_BIND_SERVICE` capability. To build and smoke-test one family locally, use a `docker-container` builder; the default `docker` driver cannot pass a built base to the examples:

```shell
docker buildx create --name scimg --driver docker-container
docker buildx bake --builder scimg nodejs
scripts/smoke-test.sh base nodejs production local/nodejs-production:test
scripts/smoke-test.sh base nodejs rds local/nodejs-rds:test
scripts/smoke-test.sh base nodejs dev local/nodejs-dev:test
scripts/smoke-test.sh example nodejs local/nodejs-example:test
```

Replace `nodejs` with `static` or `python3` for the other families, and skip the `dev` line for `static`. The `static` family also builds the Envoy example, and its smoke test proxies to the Go example:

```shell
scripts/smoke-test.sh envoy local/static-envoy-example:test local/static-example:test
```

### Entrypoints in Go, Not Bash

Images often start with a shell script that reads environment variables, renders a config file with `envsubst` or `sed`, and then `exec`s the real process. That needs a shell in the image, and unvalidated values can rewrite the config: an `UPSTREAM_HOST` containing a quote and a newline injects YAML.

The Envoy example replaces that script with a small Go program, `examples/envoy_example/entrypoint`. It:

- reads `LISTEN_PORT` (default `8080`), `UPSTREAM_HOST` (default `localhost`) and `UPSTREAM_PORT` (default `8081`);
- rejects anything that is not a port number, a host name or an IP address, and names every bad variable in one error;
- refuses the admin port `9901` as `LISTEN_PORT`, and as `UPSTREAM_PORT` on a loopback host, so the admin API never reaches the public listener;
- renders `envoy.yaml.tmpl` into `$TMPDIR/envoy.yaml` (`/tmp` when `TMPDIR` is unset), with the admin listener on `127.0.0.1:9901` only;
- replaces itself with Envoy through `syscall.Exec`, so Envoy is PID 1 and receives signals directly. The entrypoint passes extra container arguments on to Envoy.

Docker runs the entrypoint's unit tests in the build stage. Envoy is linked against glibc, so the example runs on Envoy's own distroless image rather than on `secure-container-image-base`. The `HEALTHCHECK` uses lprobe against the admin `/ready` endpoint. Envoy resolves the upstream IPv4 first, so `localhost` reaches an app that listens on IPv4 only. CI reports Trivy findings in the Envoy image without failing, because its CVEs come from upstream Envoy and must not hold back a base.

Use a shell script when it is one line that `exec`s the process. Write the entrypoint in Go once it validates input or renders config.

## Agent Skill

`skills/secure-container` is an [Agent Skill](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) that hardens a Dockerfile with these images, or writes a new one. It first inspects the app: runtime, native dependencies, subprocesses, signal handling, writable paths, ports and what the healthcheck proves. Then it proposes only the changes that apply, such as a multi-stage build, the `-rds` variant, lprobe, a Go entrypoint or an unprivileged port, and asks before it edits. The last step runs the image with the hardened flags until it is healthy, verifies the base with `cosign` and reports any check it could not run. When an app does not fit these bases, it says so and applies the hardening steps that still fit.

To install it, copy the directory into your agent's skill directory. For Claude Code:

```shell
git clone --depth 1 https://github.com/fivexl/secure-container-image.git
mkdir -p ~/.claude/skills
cp -R secure-container-image/skills/secure-container ~/.claude/skills/
```

Then ask your agent to harden a Dockerfile.

## Deprecated Images

These packages are no longer built. They stay pullable but get no fixes.

| Deprecated | Replacement |
|---|---|
| `secure-container-image-base-python3-distroless-debian-11` | `secure-container-image-base-python3` |
| `secure-container-image-base-nodejs20-distroless-debian-11` | `secure-container-image-base-nodejs` |
| `secure-container-image-example-goapp`, `-example-node-app`, `-example-py-app-poetry`, `-example-py-app-poetry-no-venv` | build the matching example from `examples/` |

## Thoughts and Considerations

You always have to balance security and productivity. These images have no shell or debug tools, so you cannot exec into a running container. First export logs and telemetry so developers do not need to exec. When there is no other way, rebuild the app on the matching `-dev` tag, swap it in, and require elevated permissions for that swap.
