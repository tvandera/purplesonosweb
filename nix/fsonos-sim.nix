{ pkgs, lib ? pkgs.lib }:

let
  src = pkgs.fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "frankensonos";
    rev = "099cfa84da4a02a203075f4cfb0e6cee888ceba5";
    hash = "sha256-bY4KIvRKQfF65oqMfXh1k6Vzzbhg+zUQYCtmRma4/EE=";
  };
  rustOverlaySrc = pkgs.fetchFromGitHub {
    owner = "oxalica";
    repo = "rust-overlay";
    rev = "5424e1e6dda30b0626935d2a03a6526db4858d60";
    hash = "sha256-arni7i+yH5ZnkvAN9UotvhMml5+fZyXcMHpiOvI3WFY=";
  };
  rustPkgs = pkgs.extend (import rustOverlaySrc);
  toolchain = rustPkgs.rust-bin.nightly."2026-08-31".minimal;
  rustPlatform = rustPkgs.makeRustPlatform {
    rustc = toolchain;
    cargo = toolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "fsonos";
  version = "0.1.0";
  inherit src;

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "fastapi-core-0.4.4" = "sha256-elyc1WtUmwl7ma8ZIp8200rJJLZLqpgES6tuGzbdh1E=";
      "fastapi-macros-0.4.4" = "sha256-elyc1WtUmwl7ma8ZIp8200rJJLZLqpgES6tuGzbdh1E=";
      "fastapi-openapi-0.4.4" = "sha256-elyc1WtUmwl7ma8ZIp8200rJJLZLqpgES6tuGzbdh1E=";
      "fastapi-router-0.4.4" = "sha256-elyc1WtUmwl7ma8ZIp8200rJJLZLqpgES6tuGzbdh1E=";
      "fastapi-rust-0.4.4" = "sha256-elyc1WtUmwl7ma8ZIp8200rJJLZLqpgES6tuGzbdh1E=";
      "fastapi-types-0.4.4" = "sha256-elyc1WtUmwl7ma8ZIp8200rJJLZLqpgES6tuGzbdh1E=";
      "fastmcp-client-0.10.0" = "sha256-T0JryzvUW8AMiNbwB+piXz99clPk9wdKBUEElIrKnJQ=";
      "fastmcp-console-0.10.0" = "sha256-T0JryzvUW8AMiNbwB+piXz99clPk9wdKBUEElIrKnJQ=";
      "fastmcp-core-0.10.0" = "sha256-T0JryzvUW8AMiNbwB+piXz99clPk9wdKBUEElIrKnJQ=";
      "fastmcp-derive-0.10.0" = "sha256-T0JryzvUW8AMiNbwB+piXz99clPk9wdKBUEElIrKnJQ=";
      "fastmcp-rust-0.10.0" = "sha256-T0JryzvUW8AMiNbwB+piXz99clPk9wdKBUEElIrKnJQ=";
    };
  };

  cargoBuildFlags = [ "--package" "fsonos-cli" "--bin" "fsonos" "--features" "sim" ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  doCheck = false;

  installPhase = ''
    runHook preInstall
    cargo install --offline --locked --path crates/fsonos-cli --root "$out" --bin fsonos --features sim
    makeWrapper "$out/bin/fsonos" "$out/bin/fsonos-sim" --add-flags sim
    runHook postInstall
  '';

  meta = {
    description = "FrankenSonos CLI with its virtual Sonos simulator";
    homepage = "https://github.com/Dicklesworthstone/frankensonos";
    license = lib.licenses.mit;
    mainProgram = "fsonos";
    platforms = lib.platforms.unix;
  };
}