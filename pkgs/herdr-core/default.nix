# herdr-core (`hc`): the runtime under the Herdr app, packaged from its
# official release builds rather than from source (that needs Rust plus Zig
# for libghostty). Nothing is compiled: Nix downloads the tarball for this
# machine, checks it against the hash below, and copies it into the store.
#
# To update: change `version`, then replace each hash with lib.fakeHash and
# build (`nix build .#herdr-core`). Nix stops with "hash mismatch ... got:
# sha256-…"; paste that in and build again. docs/updating.md walks through it.
# Release notes: https://github.com/herdrdev/herdr-core/blob/main/CHANGELOG.md
{ lib, stdenvNoCC, fetchurl }:
let
  version = "0.1.20";

  # One tarball per platform, so one hash each. The manifest at
  # https://releases.herdr.dev/core/<version>/manifest.json lists them too.
  releases = {
    x86_64-linux = { target = "linux-x86_64"; hash = "sha256-rGuGiQxFGjdYRiCqpDi3G8DQvUMKLnwdfglfBSxBTnQ="; };
    aarch64-linux = { target = "linux-aarch64"; hash = "sha256-XzA3N50VzHbPxy0v0aQmLqHFsk3yeL98/Yrc/3uRSGI="; };
    aarch64-darwin = { target = "macos-aarch64"; hash = "sha256-5YmF0/726QnzPTxaRCbkiYyBVkpVfUY2WRzsnjoGryY="; };
    x86_64-darwin = { target = "macos-x86_64"; hash = "sha256-NsAzHD/+oP+q2hlbiaPHSW9/P8W/NeRgXBnITlwgWlY="; };
  };
  release = releases.${stdenvNoCC.hostPlatform.system}
    or (throw "herdr-core: no release build for ${stdenvNoCC.hostPlatform.system}");

  # On macOS the binary lives inside a signed app bundle (macOS grants
  # permissions such as the microphone to the bundle); `hc` and `herdr-core`
  # both point at it, as the official installer does.
  exe = if stdenvNoCC.hostPlatform.isDarwin
    then "libexec/herdr-core/Herdr Core.app/Contents/MacOS/herdr-core"
    else "libexec/herdr-core/herdr-core";
in
stdenvNoCC.mkDerivation {
  pname = "herdr-core";
  inherit version;

  src = fetchurl {
    url = "https://releases.herdr.dev/core/${version}/herdr-core-${release.target}.tar.gz";
    inherit (release) hash;
  };
  # The tarball has several files at its top level, not one folder.
  sourceRoot = ".";

  # Copied as-is: the Linux build is a static binary (nothing to patch for
  # NixOS), and changing a byte of the macOS one would break its signature.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec/herdr-core $out/bin
    for f in herdr-core "Herdr Core.app" LICENSE THIRD-PARTY-NOTICES; do
      if [ -e "$f" ]; then cp -R "$f" $out/libexec/herdr-core/; fi
    done
    ln -s "$out/${exe}" $out/bin/herdr-core
    ln -s "$out/${exe}" $out/bin/hc
    runHook postInstall
  '';

  meta = {
    description = "Runs terminals and coding agents that outlive their windows (hc)";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames releases;
    mainProgram = "hc";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
