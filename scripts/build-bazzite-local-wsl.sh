#!/usr/bin/env bash

set -Eeuo pipefail

REPO_DIR="/mnt/d/Bazzite-Custom/image-template"
OUTPUT_DIR="/mnt/d/Bazzite-Custom/OUTPUT"
IMAGE_REF="localhost/bazzite-custom-deck-nvidia:stable"
BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"
FINAL_ISO="$OUTPUT_DIR/Bazzite-Custom-Deck-NVIDIA.iso"
FINAL_SHA="$FINAL_ISO.sha256"

echo "=== Local Bazzite ISO build started: $(date -Is) ==="

if [[ ! -d "$REPO_DIR" ]]; then
  echo "Missing repository directory: $REPO_DIR" >&2
  exit 1
fi

if ! command -v dnf5 >/dev/null 2>&1; then
  echo "This script expects Fedora WSL with dnf5." >&2
  exit 1
fi

dnf5 -y install \
  podman \
  git \
  just \
  jq \
  gawk \
  curl \
  unzip \
  findutils \
  coreutils \
  util-linux \
  shadow-utils \
  sudo \
  python3 \
  xz \
  tar \
  which

mkdir -p "$OUTPUT_DIR"
cd "$REPO_DIR"

find . -type f \( -name "*.sh" -o -name "*.ps1" -o -name "*.toml" -o -name "Containerfile" -o -name "Justfile" -o -name "*.env" -o -name "*.service" -o -name "*.timer" \) -print0 |
  xargs -0 sed -i 's/\r$//'

chmod 0755 build_files/build.sh
chmod 0755 system_files/usr/bin/bazzite-custom-firststart

echo "--- Host and toolchain ---"
cat /etc/os-release
uname -a
podman version
podman info --format '{{.Store.GraphRoot}}'

echo "--- Building local bootc image: $IMAGE_REF ---"
podman build \
  --pull=newer \
  --tag "$IMAGE_REF" \
  --file Containerfile \
  .

echo "--- Verifying local image ---"
podman image exists "$IMAGE_REF"
podman run --rm "$IMAGE_REF" bootc container lint

echo "--- Building installer ISO with bootc-image-builder ---"
rm -rf output
mkdir -p output

podman run \
  --rm \
  --privileged \
  --pull=newer \
  --net=host \
  --security-opt label=disable \
  -v "$(pwd)/disk_config/iso.toml:/config.toml:ro" \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  "$BIB_IMAGE" \
  --type iso \
  --local \
  --use-librepo=True \
  --rootfs=btrfs \
  "$IMAGE_REF"

iso_path=""
if [[ -f output/bootiso/install.iso ]]; then
  iso_path="output/bootiso/install.iso"
else
  iso_path="$(find output -type f -name "*.iso" | head -n 1)"
fi

if [[ -z "$iso_path" || ! -f "$iso_path" ]]; then
  echo "No ISO was produced by bootc-image-builder." >&2
  find output -maxdepth 4 -type f -print >&2 || true
  exit 1
fi

cp -f "$iso_path" "$FINAL_ISO"
hash_line="$(sha256sum "$FINAL_ISO")"
printf '%s  Bazzite-Custom-Deck-NVIDIA.iso\n' "${hash_line%% *}" > "$FINAL_SHA"
sync

echo "--- Final artifact ---"
ls -lh "$FINAL_ISO" "$FINAL_SHA"
cat "$FINAL_SHA"
echo "=== Local Bazzite ISO build finished: $(date -Is) ==="
