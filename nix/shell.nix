{ pkgs ? import <nixpkgs> {} }:

let
  Sonos = pkgs.callPackage ./sonos.nix {
    perlPackages = pkgs.perlPackages;
  };
in
pkgs.mkShell {
  buildInputs = [
    (pkgs.perl.withPackages (ps: with ps; [
      Sonos
    ]))
  ];

  shellHook = ''
    echo "Perl dev shell with BLA and its dependencies"
  '';
}