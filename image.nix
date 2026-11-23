{
  lib,
  buildEnv,
  buildkit,
  busybox,
  cacert,
  cni-plugins,
  dockerTools,
  fuse-overlayfs,
  fuse3,
  gitMinimal,
  iproute2,
  iptables,
  openssh,
  pigz,
  runCommand,
  runc,
  util-linux,
  xz,
}:

let
  tools = buildEnv {
    name = "buildkit-runtime-tools";
    paths = [
      (lib.getBin fuse3)
      fuse-overlayfs
      gitMinimal
      iproute2
      iptables
      openssh
      pigz
      util-linux
      xz
      (lib.setPrio 100 busybox)
    ];
    pathsToLink = [ "/bin" ];
  };

  root = runCommand "buildkit-image-root" { } ''
    mkdir -p "$out/usr/bin" "$out/opt/cni"
    ln -s ${lib.getBin cni-plugins}/bin "$out/opt/cni/bin"
    ln -s ${lib.getExe runc} "$out/usr/bin/buildkit-runc"
    ln -s ${lib.getBin util-linux}/bin/unshare "$out/usr/bin/unshare"
    ln -s ${buildkit}/bin/buildkitd "$out/usr/bin/buildkitd"
    ln -s ${buildkit}/bin/buildctl "$out/usr/bin/buildctl"
    install -m 0755 ${buildkit.src}/hack/{buildkitd-entrypoint,with-cgroupfs-remount} "$out/usr/bin"
    install -m 0755 ${buildkit.src}/examples/buildctl-daemonless/buildctl-daemonless.sh "$out/usr/bin"
    install -Dm644 ${buildkit.src}/LICENSE "$out/usr/share/licenses/buildkit/LICENSE"
    install -Dm644 ${./buildkitd.toml} "$out/etc/buildkit/buildkitd.toml"
  '';
in
dockerTools.buildLayeredImage {
  # Buildx can use the loaded archive when its initial registry pull fails.
  name = "127.0.0.1:1/buildkit";
  contents = [ root tools cacert dockerTools.fakeNss ];
  extraCommands = ''
    mkdir -p tmp var/lib/buildkit
    chmod 1777 tmp
  '';
  config = {
    Entrypoint = [ "/usr/bin/buildkitd-entrypoint" ];
    Env = [
      "PATH=/usr/bin:/bin"
      "BUILDKIT_SETUP_CGROUPV2_ROOT=1"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    Volumes."/var/lib/buildkit" = { };
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/moby/buildkit";
      "org.opencontainers.image.revision" = buildkit.src.rev;
      "org.opencontainers.image.version" = buildkit.version;
    };
  };
}
