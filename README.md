# buildkit

## Table of Contents / 目次

- [English](#english)
  - [Overview](#overview)
  - [Pull from GHCR](#pull-from-ghcr)
  - [Load a release archive](#load-a-release-archive)
  - [Build from source](#build-from-source)
  - [Update the upstream pin](#update-the-upstream-pin)
  - [Continuous integration and releases](#continuous-integration-and-releases)
- [日本語](#日本語)
  - [概要](#概要)
  - [GHCR からの取得](#ghcr-からの取得)
  - [リリースアーカイブの読み込み](#リリースアーカイブの読み込み)
  - [ソースからのビルド](#ソースからのビルド)
  - [上流バージョンの更新](#上流バージョンの更新)
  - [CI とリリース](#ci-とリリース)

## English

### Overview

michibiki.io maintains these BuildKit Docker images. The current build uses [BuildKit v0.35.1](https://github.com/moby/buildkit/tree/412cc86ad3c4252b82e929f9b1b1ad167376ded8) with a single patch for SBOM generation on `fuse-overlayfs`. When the scanner selects an entire snapshot root, BuildKit mounts the FUSE filesystem first and passes a bind mount to the OCI runtime.

The images run on AMD64 and ARM64 Linux hosts with Docker and Buildx. Nix builds the archives, and the release archives can be loaded directly with Docker. The BuildKit container needs access to `/dev/fuse` for its default `fuse-overlayfs` worker.

### Pull from GHCR

Releases that include `release-images.json` also provide a multi-platform image for Linux AMD64 and ARM64 on GHCR.
Use the release version without the leading `v`. Docker selects the image for the host architecture.

```sh
image=ghcr.io/michibiki-io/buildkit:0.2.0
docker pull "$image"
docker buildx create --name fuse-builder --driver docker-container --driver-opt "image=$image"
docker buildx inspect --bootstrap fuse-builder
```

For a digest-pinned pull or Buildx builder, use the `images.buildkit.reference` value from `release-images.json` or `approved-runtime-images.json`. [Release assets](https://github.com/michibiki-io/buildkit/releases)

### Load a release archive

Download `buildkit-amd64.tar.gz` or `buildkit-arm64.tar.gz` for your host, along with `SHA256SUMS`. [GitHub Releases](https://github.com/michibiki-io/buildkit/releases)

Verify the checksum and load the archive. Use the ARM64 filename for an ARM64 host.

```sh
sha256sum --ignore-missing --check SHA256SUMS &&
  docker load --input buildkit-amd64.tar.gz
```

Copy the tag from the image reference printed by `docker load` and replace `<tag>` below.

```sh
docker buildx create --name fuse-builder --driver docker-container \
  --driver-opt 'image=127.0.0.1:1/buildkit:<tag>'
docker buildx inspect --bootstrap fuse-builder
```

The reference points to loopback. Buildx tries to pull it and can use the loaded image when the pull fails. The CI regression checks that the builder uses the loaded image ID.

### Build from source

The flake provides `buildkit` (`buildkitd` and `buildctl`) and `dockerImage` (a compressed Docker archive) for `x86_64-linux` and `aarch64-linux`. Run these commands on a Nix host matching the target architecture.

```sh
nix build .#dockerImage
docker load --input result
image="$(nix eval --raw .#dockerImage.imageName):$(nix eval --raw .#dockerImage.imageTag)"
docker buildx create --name fuse-builder --driver docker-container --driver-opt "image=$image"
docker buildx inspect --bootstrap fuse-builder
```

### Update the upstream pin

1. Change the BuildKit commit in `flake.nix` and the version in `package.nix`, then run `nix flake update buildkit-src`.
2. Review the FUSE mount patch against the new source. When upstream includes the fix, remove the patch and its entry in `package.nix`. [FUSE mount patch](patches/fuse-overlayfs-sbom-mount.patch)
3. Verify that the AMD64 and ARM64 PR jobs generate digest-linked SPDX for a multi-layer Dockerfile and confirm that the scanner reads the image filesystem through the `fuse-overlayfs` worker.

### Continuous integration and releases

The Test workflow runs when a PR opens, reopens, or receives new commits. A separate Release workflow runs after a `feature/` PR with a releasable commit merges into the default branch. It builds and verifies both Docker archives from the merge commit. It publishes those same images to GHCR, verifies the versioned index, then tags the Git commit and publishes the archives, checksums, and registry metadata.

## 日本語

### 概要

michibiki.io が管理する BuildKit の Docker イメージです。
現在は [BuildKit v0.35.1](https://github.com/moby/buildkit/tree/412cc86ad3c4252b82e929f9b1b1ad167376ded8) に、`fuse-overlayfs` での SBOM 生成を修正するパッチを1枚適用しています。
スキャナーがスナップショットのルート全体を参照する場合、BuildKit が先に FUSE ファイルシステムをマウントし、OCI ランタイムに bind マウントを渡します。

イメージは Docker と Buildx が動作する AMD64 または ARM64 の Linux ホストで使えます。
Nix でビルドしたリリースアーカイブは、Docker で直接読み込めます。
既定の `fuse-overlayfs` ワーカーを動かすには、BuildKit コンテナから `/dev/fuse` にアクセスできる必要があります。

### GHCR からの取得

`release-images.json` が付属するリリースでは、AMD64 と ARM64 の Linux 向けイメージを GHCR から取得できます。
タグには先頭の `v` を除いたリリースバージョンを指定します。
Docker がホストのアーキテクチャに合うイメージを選びます。

```sh
image=ghcr.io/michibiki-io/buildkit:0.2.0
docker pull "$image"
docker buildx create --name fuse-builder --driver docker-container --driver-opt "image=$image"
docker buildx inspect --bootstrap fuse-builder
```

pull や Buildx で digest を固定する場合は、`release-images.json` または `approved-runtime-images.json` の `images.buildkit.reference` を使います。 [リリースの添付ファイル](https://github.com/michibiki-io/buildkit/releases)

### リリースアーカイブの読み込み

ホストに合った `buildkit-amd64.tar.gz` または `buildkit-arm64.tar.gz` と `SHA256SUMS` を取得します。 [GitHub Releases](https://github.com/michibiki-io/buildkit/releases)

チェックサムを照合してからアーカイブを読み込みます。
ARM64 の場合はアーカイブのファイル名を置き換えます。

```sh
sha256sum --ignore-missing --check SHA256SUMS &&
  docker load --input buildkit-amd64.tar.gz
```

`docker load` が表示したイメージ参照からタグを取り出し、以下の `<tag>` を置き換えます。

```sh
docker buildx create --name fuse-builder --driver docker-container \
  --driver-opt 'image=127.0.0.1:1/buildkit:<tag>'
docker buildx inspect --bootstrap fuse-builder
```

イメージ参照のホストはループバックです。
Buildx は取得を試み、失敗した場合は読み込み済みのイメージを使えます。
CI では、ビルダーが実際に読み込み済みのイメージ ID を使うことを確認します。

### ソースからのビルド

Flake は `x86_64-linux` と `aarch64-linux` 向けに、`buildkit`（`buildkitd` と `buildctl`）と `dockerImage`（圧縮済みの Docker アーカイブ）を提供します。
対象アーキテクチャの Nix ホストで実行します。

```sh
nix build .#dockerImage
docker load --input result
image="$(nix eval --raw .#dockerImage.imageName):$(nix eval --raw .#dockerImage.imageTag)"
docker buildx create --name fuse-builder --driver docker-container --driver-opt "image=$image"
docker buildx inspect --bootstrap fuse-builder
```

### 上流バージョンの更新

1. `flake.nix` の BuildKit コミットと `package.nix` のバージョンを更新し、`nix flake update buildkit-src` を実行します。
2. 新しいソースに対してパッチを確認します。上流に修正が入ったら、パッチファイルと `package.nix` の指定を削除します。 [FUSE マウントのパッチ](patches/fuse-overlayfs-sbom-mount.patch)
3. AMD64 と ARM64 の PR ジョブで、複数レイヤーの Dockerfile から digest に対応する SPDX を生成できることと、スキャナーが `fuse-overlayfs` ワーカーでイメージのファイルシステムを読めることを確認します。

### CI とリリース

PR の作成、再オープン、コミット追加で Test が起動します。
リリース対象のコミットを含む `feature/` ブランチの PR が既定ブランチにマージされると、別の Release ワークフローが起動します。
Release はマージコミットから両アーキテクチャの Docker アーカイブを作って検証します。
同じイメージを GHCR に公開してバージョン付きインデックスを確認してから、Git タグを付け、アーカイブ、チェックサム、レジストリのメタデータを公開します。
