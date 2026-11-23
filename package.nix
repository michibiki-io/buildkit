{ lib, buildGo126Module, pkg-config, libseccomp, src }:

buildGo126Module (finalAttrs: {
  pname = "buildkit";
  version = "0.35.1";
  inherit src;
  patches = [ ./patches/fuse-overlayfs-sbom-mount.patch ];
  vendorHash = null;
  subPackages = [ "cmd/buildctl" "cmd/buildkitd" ];
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libseccomp ];
  env.CGO_ENABLED = "1";
  tags = [ "osusergo" "netgo" "seccomp" "grpcnotrace" ];
  ldflags = [
    "-s"
    "-w"
    "-X github.com/moby/buildkit/version.Version=v${finalAttrs.version}"
    "-X github.com/moby/buildkit/version.Revision=${src.rev}"
  ];
  # The native Docker tests exercise the actual FUSE worker and scanner.
  doCheck = false;

  meta = {
    description = "BuildKit with the fuse-overlayfs SBOM mount fix";
    homepage = "https://github.com/moby/buildkit";
    license = lib.licenses.asl20;
    mainProgram = "buildkitd";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
