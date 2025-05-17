{ pkgs ? import <nixpkgs> {} }:

let
  Sonos = pkgs.callPackage ./sonos.nix {
    perlPackages = pkgs.perlPackages;
  };
  depsOnly = Sonos.propagatedBuildInputs;

in
pkgs.mkShell {
  buildInputs = [
    (pkgs.perl.withPackages (ps: with ps; [
      depsOnly
    ]))
  ];

  shellHook = ''
    echo "Perl dev shell with Sonos dependencies"
  '';
}