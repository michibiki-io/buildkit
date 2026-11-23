#!/usr/bin/env bash
set -euo pipefail

image=$1
architecture=$2
version=$3
revision=$4
fixture=$(mktemp -d)
builder="fuse-sbom-${fixture##*.}"
cleanup() {
  docker buildx rm "$builder" >/dev/null 2>&1 || true
  rm -rf -- "$fixture"
}
trap cleanup EXIT

test -c /dev/fuse
test "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")" = "linux/$architecture"
test "$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image")" = "$revision"
docker run --rm --entrypoint /bin/sh "$image" -ec '
  for executable in buildctl buildkit-runc fuse-overlayfs mount.fuse3 fusermount3; do
    command -v "$executable"
  done
  buildkitd --version
' | tee "$fixture/version"
grep -F -- "v$version $revision" "$fixture/version"
image_id=$(docker image inspect --format '{{.Id}}' "$image")

# The final stage must have multiple real layers. A single-parent view
# can use a bind mount and would not test the FUSE whole-root selector.
mkdir "$fixture/context"
cat > "$fixture/context/Dockerfile" <<'DOCKERFILE'
FROM docker.io/library/alpine:3.21@sha256:bc21487101ae47172509130ee1092cc273a831968d64b617776d1f69c81e42ab
RUN printf 'first layer\n' >/first
RUN test -s /first && printf 'second layer\n' >/second
DOCKERFILE

docker buildx create --name "$builder" --driver docker-container --driver-opt "image=$image"
docker buildx inspect --bootstrap "$builder" | tee "$fixture/worker"
grep -E 'org\.mobyproject\.buildkit\.worker\.snapshotter:[[:space:]]+fuse-overlayfs$' "$fixture/worker"
test "$(docker inspect --format '{{.Image}}' "buildx_buildkit_${builder}0")" = "$image_id"
docker buildx build --builder "$builder" --progress=plain --platform "linux/$architecture" \
  --provenance=false \
  --attest 'type=sbom,generator=docker.io/docker/buildkit-syft-scanner@sha256:873a7458c3c8ac8e32c7b796c10e1600b07b963d2aa000a72a2d97aaaa2d6315' \
  --output "type=oci,dest=$fixture/oci.tar" "$fixture/context"
python3 "$(dirname "$0")/verify-spdx.py" "$fixture/oci.tar" "$architecture"
