{
  description = "BuildKit images maintained by michibiki.io";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/2786a2a72088ecf32aea5b3ec52099e6a7cff78f";
    buildkit-src = {
      url = "github:moby/buildkit/412cc86ad3c4252b82e929f9b1b1ad167376ded8";
      flake = false;
    };
  };

  outputs = { nixpkgs, buildkit-src, ... }: {
    packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        buildkit = pkgs.callPackage ./package.nix { src = buildkit-src; };
      in {
        inherit buildkit;
        default = buildkit;
        dockerImage = pkgs.callPackage ./image.nix { inherit buildkit; };
      }
    );
  };
}
