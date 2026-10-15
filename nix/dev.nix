{ pkgs ? import <nixpkgs> {} }:

let
  Sonos = pkgs.callPackage ./sonos.nix {
    perlPackages = pkgs.perlPackages;
  };
  depsOnly = Sonos.propagatedBuildInputs;

in
pkgs.mkShell {
  buildInputs = [
    (pkgs.perl.withPackages (_: depsOnly))
  ];

  shellHook = ''
    export PERL5LIB="$PWD/lib''${PERL5LIB:+:$PERL5LIB}"
    echo "Perl dev shell with Sonos dependencies"
  '';
}