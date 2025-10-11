{
  pkgs ? import <nixpkgs> { },
  stdenv ? pkgs.stdenv,
  lib ? pkgs.lib,
}:

stdenv.mkDerivation {
  pname = "Minestalgia";
  version = "0.0.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./src
      ./build.zig
      ./build.zig.zon
    ];
  };

  nativeBuildInputs = [
    pkgs.zig_0_14
  ];

  buildPhase = ''
    zig build \
      --global-cache-dir $TMPDIR/zig-cache \
      --release=safe
  '';

  installPhase = ''
    mkdir -p $out/bin
    mv zig-out/bin/Minestalgia $out/bin
  '';
}
