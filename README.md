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

| Image | Tags | With the AWS RDS CA bundle |
|---|---|---|
| `secure-container-image-base` | `latest`, `debian13` | `latest-rds`, `debian13-rds` |
| `secure-container-image-base-python3` | `latest`, `python3.13-debian13` | `latest-rds`, `python3.13-debian13-rds` |
| `secure-container-image-base-nodejs` | `latest`, `node26-debian13` | `latest-rds`, `node26-debian13-rds` |

The `-rds` variants trust the [AWS RDS global certificate bundle](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html) in addition to the system CAs. It is appended to `/etc/ssl/certs/ca-certificates.crt` and also kept on its own as `/etc/ssl/certs/aws-rds.crt`. For Node.js, the `-rds` variant sets `NODE_EXTRA_CA_CERTS` to that file, because Node.js ignores the system CA file by default. Use the plain tags unless your app connects to RDS over TLS.

Every image carries the label `io.fivexl.image.variant` (`production` or `rds`), so admission policies can tell variants apart.

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

The `examples` directory holds one app per base. CI builds them against the bases from the same commit, scans them and runs them with `--read-only --cap-drop=ALL --security-opt=no-new-privileges`. They are not published.

- `examples/go_app_example/Dockerfile.goapp`: a static Go binary on `secure-container-image-base`.
- `examples/node_examples/Dockerfile.node-app`: an Express 5 app on `secure-container-image-base-nodejs`, installed with `npm ci --omit=dev`.
- `examples/python_examples/Dockerfile.py-app-uv`: a uvicorn and pandas app on `secure-container-image-base-python3`. The builder is `debian:13` with its own `python3`, the same interpreter and ABI as the runtime, and `uv sync --frozen` installs the dependencies into `/app/.venv`.

Each example listens on port 8080, so it needs no `NET_BIND_SERVICE` capability. To build and smoke-test one family locally, use a `docker-container` builder; the default `docker` driver cannot pass a built base to the examples:

```shell
docker buildx create --name scimg --driver docker-container
docker buildx bake --builder scimg nodejs
scripts/smoke-test.sh base nodejs production local/nodejs-production:test
scripts/smoke-test.sh base nodejs rds local/nodejs-rds:test
scripts/smoke-test.sh example nodejs local/nodejs-example:test
```

Replace `nodejs` with `static` or `python3` for the other families.

## Deprecated Images

These packages are no longer built. They stay pullable but get no fixes.

| Deprecated | Replacement |
|---|---|
| `secure-container-image-base-python3-distroless-debian-11` | `secure-container-image-base-python3` |
| `secure-container-image-base-nodejs20-distroless-debian-11` | `secure-container-image-base-nodejs` |
| `secure-container-image-example-goapp`, `-example-node-app`, `-example-py-app-poetry`, `-example-py-app-poetry-no-venv` | build the matching example from `examples/` |

## Thoughts and Considerations

You always have to balance security and productivity. These images have no shell or debug tools, so you cannot exec into a running container. First export logs and telemetry so developers do not need to exec. When there is no other way, swap the secure image for a debug build of the same app, and require elevated permissions for that swap.
