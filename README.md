# buildkit-nix

Nix packaging for [BuildKit v0.35.1](https://github.com/moby/buildkit/tree/412cc86ad3c4252b82e929f9b1b1ad167376ded8) with one patch for SBOM generation on the `fuse-overlayfs` snapshotter. When the SBOM scanner selects a snapshot's entire root, the patch has BuildKit mount the FUSE filesystem first and pass a bind mount to the OCI runtime.

## Build and load

The flake exposes `buildkit` (`buildkitd` and `buildctl`) and `dockerImage` (a compressed Docker archive) for `x86_64-linux` and `aarch64-linux`. The image defaults to an OCI worker with `fuse-overlayfs`. The Docker host must make `/dev/fuse` available to the BuildKit container.

From a Nix host matching the target architecture:

```sh
nix build .#dockerImage
docker load --input result
image="$(nix eval --raw .#dockerImage.imageName):$(nix eval --raw .#dockerImage.imageTag)"
docker buildx create --name fuse-builder --driver docker-container --driver-opt "image=$image"
docker buildx inspect --bootstrap fuse-builder
```

The image reference includes a Nix-generated tag. Buildx tries the loopback image reference and uses the loaded image when the registry pull fails. The regression test checks that the bootstrapped container uses the loaded image ID.

GitHub Releases attach `buildkit-amd64.tar.gz`, `buildkit-arm64.tar.gz`, and `SHA256SUMS`. Download the archive for the target architecture and the checksum file, then run `sha256sum --ignore-missing --check SHA256SUMS` before `docker load`. Docker reports the image reference after loading.

## Update the upstream pin

1. Change the BuildKit commit in `flake.nix` and the version in `package.nix`, then run `nix flake update buildkit-src`.
2. Review the [FUSE mount patch](patches/fuse-overlayfs-sbom-mount.patch) against the new source. When upstream includes the fix, remove the patch and its entry in `package.nix`.
3. Verify that the PR's AMD64 and ARM64 jobs build the archives and generate a digest-linked SPDX document for a multi-layer Dockerfile. Both jobs verify that BuildKit uses the FUSE worker and that the scanner reads the image filesystem.

PR creation and updates run the Test workflow. Merging a `feature/` PR with a releasable commit runs the separate Release workflow. It rebuilds and checks both Docker archives from the merge commit before tagging and publishing the assets.
