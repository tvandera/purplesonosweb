{ pkgs ? import <nixpkgs> {} }:

let
  Sonos = pkgs.callPackage ./sonos.nix {
    perlPackages = pkgs.perlPackages;
  };
  fsonosSim = pkgs.callPackage ./fsonos-sim.nix {};
in
pkgs.mkShell {
  buildInputs = [
    (pkgs.perl.withPackages (ps: with ps; [
      Sonos
    ]))
    fsonosSim
  ];

  shellHook = ''
    export FSONOS_SIM_BIN="''${FSONOS_SIM_BIN:-${fsonosSim}/bin/fsonos}"
    echo "Perl dev shell with BLA and its dependencies"
  '';
}