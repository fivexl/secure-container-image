#!/usr/bin/env bash
# Smoke tests for the images built by docker-bake.hcl. CI runs them on every
# platform before anything is published.
#   scripts/smoke-test.sh base    <static|python3|nodejs> <production|rds|dev> <image>
#   scripts/smoke-test.sh example <static|python3|nodejs> <image>
#   scripts/smoke-test.sh envoy   <envoy image> <go example image>
set -euo pipefail

RDS_BUNDLE_URL=https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
# shellcheck disable=SC2054 # the commas belong to the --tmpfs option
HARDENED=(--read-only --cap-drop=ALL --security-opt=no-new-privileges --user 65532
  --tmpfs /tmp:uid=65532,mode=1777)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }

workdir=$(mktemp -d)
cleanup() {
  [[ -n "${cid:-}" ]] && docker rm -f "$cid" >/dev/null 2>&1
  [[ -n "${upstream:-}" ]] && docker rm -f "$upstream" >/dev/null 2>&1
  [[ -n "${network:-}" ]] && docker network rm "$network" >/dev/null 2>&1
  rm -rf "$workdir"
}
trap cleanup EXIT

fetch_rds_bundle() {
  curl -fsSL "$RDS_BUNDLE_URL" -o "$workdir/rds.pem"
  chmod 0644 "$workdir/rds.pem"
}

# Every certificate of the RDS bundle must be in the image's system CA file for
# the rds variant, and none of them for the production variant.
check_system_ca_file() {
  local image=$1 variant=$2 c
  c=$(docker create --entrypoint /usr/bin/lprobe "$image")
  docker cp -q "$c:/etc/ssl/certs/ca-certificates.crt" "$workdir/system.pem"
  docker rm "$c" >/dev/null
  python3 - "$workdir/rds.pem" "$workdir/system.pem" "$variant" <<'EOF'
import re, sys
def certs(path):
    return set(re.findall(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", open(path).read(), re.S))
rds, system, variant = certs(sys.argv[1]), certs(sys.argv[2]), sys.argv[3]
present = rds & system
if variant == "rds" and present != rds:
    sys.exit(f"{len(rds - present)} of {len(rds)} RDS certificates missing from the system CA file")
if variant != "rds" and present:
    sys.exit(f"{len(present)} RDS certificates found in a non-rds variant")
EOF
  pass "system CA file matches the $variant variant"
}

base_python3() {
  local image=$1 variant=$2
  docker run --rm "${HARDENED[@]}" "$image" -c 'import ssl; ssl.create_default_context()' \
    || fail "python3 cannot build a default TLS context"
  pass "python3 TLS context"
  docker run --rm "${HARDENED[@]}" -v "$workdir/rds.pem:/rds.pem:ro" "$image" -c '
import hashlib, re, ssl, sys
pems = re.findall(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", open("/rds.pem").read(), re.S)
rds = {hashlib.sha256(ssl.PEM_cert_to_DER_cert(p)).hexdigest() for p in pems}
loaded = {hashlib.sha256(d).hexdigest() for d in ssl.create_default_context().get_ca_certs(binary_form=True)}
if not loaded:
    sys.exit("python3 loaded no CA certificates")
if sys.argv[1] == "rds" and not rds <= loaded:
    sys.exit("python3 does not trust the RDS bundle")
if sys.argv[1] != "rds" and rds & loaded:
    sys.exit("python3 trusts RDS certificates in a non-rds variant")
' "$variant" || fail "python3 RDS trust check"
  pass "python3 trust store matches the $variant variant"
}

base_nodejs() {
  local image=$1 variant=$2
  docker run --rm "${HARDENED[@]}" "$image" -e '
if (process.versions.node.split(".")[0] !== "26") { console.error(process.versions.node); process.exit(1); }' \
    || fail "node is not version 26"
  pass "node 26"
  docker run --rm "${HARDENED[@]}" -v "$workdir/rds.pem:/rds.pem:ro" "$image" -e '
const { X509Certificate } = require("node:crypto");
const { getCACertificates } = require("node:tls");
const fp = (pem) => new X509Certificate(pem).fingerprint256;
const rds = (require("node:fs").readFileSync("/rds.pem", "utf8").match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g)).map(fp);
const extra = new Set(getCACertificates("extra").map(fp));
const dflt = new Set(getCACertificates("default").map(fp));
const variant = process.argv[1];
const inAll = (s) => rds.every((f) => s.has(f));
const inAny = (s) => rds.some((f) => s.has(f));
if (variant === "rds" && !(inAll(extra) && inAll(dflt))) { console.error("node does not trust the RDS bundle"); process.exit(1); }
if (variant !== "rds" && (inAny(extra) || inAny(dflt))) { console.error("node trusts RDS certificates in a non-rds variant"); process.exit(1); }
' "$variant" || fail "node RDS trust check"
  pass "node trust store matches the $variant variant"

  docker run --rm "${HARDENED[@]}" "$image" -e '
const cmd = require("node:fs").readFileSync("/proc/1/cmdline", "utf8").split("\0")[0];
if (!cmd.endsWith("dumb-init")) { console.error(`PID 1 is ${cmd}`); process.exit(1); }' \
    || fail "dumb-init is not PID 1"
  pass "dumb-init is PID 1"

  cid=$(docker run -d "${HARDENED[@]}" "$image" -e 'setInterval(() => {}, 1000)')
  sleep 1
  local start=$SECONDS
  docker stop -t 10 "$cid" >/dev/null
  (( SECONDS - start < 5 )) || fail "SIGTERM took $((SECONDS - start))s to stop the container"
  docker rm "$cid" >/dev/null && cid=
  pass "SIGTERM stops the container"
}

# Only the dev variant may have a shell.
check_shell() {
  local image=$1 variant=$2 c path found=()
  c=$(docker create --entrypoint /usr/bin/lprobe "$image")
  for path in /bin/sh /busybox/sh; do
    docker cp -q "$c:$path" - >/dev/null 2>&1 && found+=("$path")
  done
  docker rm "$c" >/dev/null
  if [[ $variant == dev ]]; then
    docker run --rm "${HARDENED[@]}" --entrypoint /busybox/sh "$image" -c 'exit 0' \
      || fail "dev variant has no working /busybox/sh"
    pass "dev variant has /busybox/sh"
  else
    (( ${#found[@]} == 0 )) || fail "$variant variant has a shell: ${found[*]}"
    pass "no shell"
  fi
}

cmd_base() {
  local family=$1 variant=$2 image=$3
  # lprobe -h exits 1, so check that it ran and printed its usage.
  local usage label
  usage=$(docker run --rm "${HARDENED[@]}" --entrypoint /usr/bin/lprobe "$image" -h 2>&1 || true)
  [[ $usage == Usage:* ]] || fail "lprobe -h: $usage"
  pass "lprobe runs"
  label=$(docker inspect -f '{{index .Config.Labels "io.fivexl.image.variant"}}' "$image")
  [[ $label == "$variant" ]] || fail "variant label is '$label', want '$variant'"
  pass "variant label"
  check_shell "$image" "$variant"
  fetch_rds_bundle
  check_system_ca_file "$image" "$variant"
  case $family in
    static) ;;
    python3) base_python3 "$image" "$variant" ;;
    nodejs) base_nodejs "$image" "$variant" ;;
    *) fail "unknown family $family" ;;
  esac
}

wait_healthy() {
  local deadline=$((SECONDS + 60)) state health
  while (( SECONDS < deadline )); do
    state=$(docker inspect -f '{{.State.Status}}' "$cid")
    health=$(docker inspect -f '{{.State.Health.Status}}' "$cid")
    [[ $state == running ]] || break
    [[ $health == healthy ]] && return 0
    sleep 1
  done
  docker inspect -f '{{json .State.Health.Log}}' "$cid" >&2 || true
  docker logs "$cid" >&2 || true
  fail "container did not become healthy (state=$state, health=${health:-none})"
}

expect_body() {
  local path=$1 want=$2 body
  body=$(curl -fsS --max-time 5 "http://127.0.0.1:$port$path") || fail "GET $path"
  [[ $body == *"$want"* ]] || fail "GET $path returned: $body"
  pass "GET $path"
}

cmd_example() {
  local family=$1 image=$2
  cid=$(docker run -d "${HARDENED[@]}" -p 127.0.0.1::8080 \
    --health-interval=2s --health-retries=3 --health-start-period=10s "$image")
  wait_healthy
  pass "container is healthy"
  port=$(docker port "$cid" 8080/tcp | head -n1 | cut -d: -f2)
  case $family in
    static) expect_body / "Hello, !" ;;
    python3) expect_body / "Uvicorn is working on root!"; expect_body /stats "Mean Score: 88.5" ;;
    nodejs) expect_body / "Express is working on root!"; expect_body /stats "Mean Score: 88.5" ;;
    *) fail "unknown family $family" ;;
  esac
}

# Envoy proxies to the Go example, which runs as its upstream on a private network.
cmd_envoy() {
  local image=$1 upstream_image=$2
  network=$(docker network create "smoke-$$")
  upstream=$(docker run -d "${HARDENED[@]}" --network "$network" --network-alias goapp "$upstream_image")
  cid=$(docker run -d "${HARDENED[@]}" --network "$network" -p 127.0.0.1::8080 \
    -e UPSTREAM_HOST=goapp -e UPSTREAM_PORT=8080 \
    --health-interval=2s --health-retries=3 --health-start-period=10s "$image")
  wait_healthy
  pass "envoy is healthy"
  port=$(docker port "$cid" 8080/tcp | head -n1 | cut -d: -f2)
  expect_body /envoy "Hello, envoy!"

  local out
  out=$(docker run --rm "${HARDENED[@]}" -e UPSTREAM_HOST='bad"host' "$image" 2>&1) \
    && fail "entrypoint accepted an invalid UPSTREAM_HOST"
  [[ $out == *UPSTREAM_HOST* ]] || fail "entrypoint error does not name UPSTREAM_HOST: $out"
  pass "entrypoint rejects an invalid UPSTREAM_HOST"
}

command=${1:-}
shift || true
case $command in
  base) cmd_base "$@" ;;
  example) cmd_example "$@" ;;
  envoy) cmd_envoy "$@" ;;
  *) sed -n '2,6p' "$0" >&2; exit 2 ;;
esac
