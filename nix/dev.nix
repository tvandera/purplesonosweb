{ pkgs ? import <nixpkgs> {} }:

let
  Sonos = pkgs.callPackage ./sonos.nix {
    perlPackages = pkgs.perlPackages;
  };
  fsonosSim = pkgs.callPackage ./fsonos-sim.nix {};
  depsOnly = Sonos.propagatedBuildInputs;

in
pkgs.mkShell {
  buildInputs = [
    (pkgs.perl.withPackages (_: depsOnly))
    fsonosSim
  ];

  shellHook = ''
    export PERL5LIB="$PWD/lib''${PERL5LIB:+:$PERL5LIB}"
    export FSONOS_SIM_BIN="''${FSONOS_SIM_BIN:-${fsonosSim}/bin/fsonos}"
    echo "Perl dev shell with Sonos dependencies"
  '';
}