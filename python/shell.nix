let
  pkgs = import <nixpkgs> {};
in pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs.requests
      python-pkgs.tabulate
      python-pkgs.glom
      python-pkgs.textual
      python-pkgs.textual-dev
      python-pkgs.httpx
    ]))
  ];
}