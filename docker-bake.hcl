# Build every base variant and example of a family:
#   docker buildx bake static      # or python3, nodejs
# Locally, and in CI on pull requests, images load into the Docker image store
# as local/<target>:test. With PUBLISH=true, CI pushes bases untagged by digest
# and keeps examples local; .github/workflows/family.yml tags what passes.

variable "REGISTRY" {
  default = "ghcr.io/fivexl"
}

variable "PUBLISH" {
  type    = bool
  default = false
}

# Set by CI: the commit and the run's build time (RFC 3339, UTC).
variable "REVISION" {
  default = ""
}

variable "CREATED" {
  default = ""
}

# Variants of one family share a package and differ by tag suffix only.
variable "FAMILIES" {
  default = {
    static = {
      dockerfile  = "Dockerfile.base"
      package     = "secure-container-image-base"
      description = "Distroless Debian 13 base for static binaries, with lprobe"
      # No dev variant: distroless's busybox shell needs a libc.
      variants = ["production", "rds"]
    }
    python3 = {
      dockerfile  = "Dockerfile.base-python3"
      package     = "secure-container-image-base-python3"
      description = "Distroless Debian 13 Python 3.13 base, with lprobe"
      variants    = ["production", "rds", "dev"]
    }
    nodejs = {
      dockerfile  = "Dockerfile.base-nodejs"
      package     = "secure-container-image-base-nodejs"
      description = "Distroless Debian 13 Node.js 26 base, with dumb-init and lprobe"
      variants    = ["production", "rds", "dev"]
    }
  }
}

function "labels" {
  params = [title, description]
  result = {
    "org.opencontainers.image.title"       = title
    "org.opencontainers.image.description" = description
    "org.opencontainers.image.source"      = "https://github.com/fivexl/secure-container-image"
    "org.opencontainers.image.revision"    = REVISION
    "org.opencontainers.image.created"     = CREATED
    "org.opencontainers.image.licenses"    = "Apache-2.0"
    "org.opencontainers.image.vendor"      = "FivexL"
  }
}

function "local_output" {
  params = [name]
  result = ["type=docker,name=local/${name}:test"]
}

group "default" {
  targets = ["static", "python3", "nodejs"]
}

group "static" {
  targets = ["static-production", "static-rds", "static-example", "static-envoy-example"]
}

group "python3" {
  targets = ["python3-production", "python3-rds", "python3-dev", "python3-example"]
}

group "nodejs" {
  targets = ["nodejs-production", "nodejs-rds", "nodejs-dev", "nodejs-example"]
}

target "_common" {
  pull = true
}

# One target per family and variant, named <family>-<variant>.
target "base" {
  name     = "${base.family}-${base.variant}"
  inherits = ["_common"]
  matrix = {
    base = flatten([for f, v in FAMILIES : [for variant in v.variants : { family = f, variant = variant }]])
  }
  context    = "."
  dockerfile = FAMILIES[base.family].dockerfile
  target     = base.variant == "production" ? "base" : base.variant
  labels     = labels(FAMILIES[base.family].package, FAMILIES[base.family].description)
  attest     = PUBLISH ? ["type=sbom", "type=provenance,mode=max"] : []
  output = PUBLISH ? [
    "type=image,name=${REGISTRY}/${FAMILIES[base.family].package},push-by-digest=true,name-canonical=true,push=true"
  ] : local_output("${base.family}-${base.variant}")
}

# Examples build FROM the published base name; contexts swap in the base built
# by this same run, so they always test the candidate. They are never pushed.
# The context keys carry no tag: with ":latest" in the key, bake 0.33 ignores
# it and pulls the published image instead.
target "static-example" {
  inherits   = ["_common"]
  context    = "examples/go_app_example"
  dockerfile = "Dockerfile.goapp"
  contexts = {
    "ghcr.io/fivexl/secure-container-image-base" = "target:static-production"
  }
  output = local_output("static-example")
}

target "python3-example" {
  inherits   = ["_common"]
  context    = "examples/python_examples"
  dockerfile = "Dockerfile.py-app-uv"
  contexts = {
    "ghcr.io/fivexl/secure-container-image-base-python3" = "target:python3-production"
  }
  output = local_output("python3-example")
}

target "nodejs-example" {
  inherits   = ["_common"]
  context    = "examples/node_examples"
  dockerfile = "Dockerfile.node-app"
  contexts = {
    "ghcr.io/fivexl/secure-container-image-base-nodejs" = "target:nodejs-production"
  }
  output = local_output("nodejs-example")
}

# Envoy's own distroless image, not a base from this repo; the static family
# builds it because its smoke test proxies to the Go example.
target "static-envoy-example" {
  inherits   = ["_common"]
  context    = "examples/envoy_example"
  dockerfile = "Dockerfile.envoy"
  output     = local_output("static-envoy-example")
}
