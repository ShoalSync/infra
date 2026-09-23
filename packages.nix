# Upstream iroh relay and DNS servers, built from the iroh release pinned in flake.lock using
# its committed Cargo.lock. nixpkgs does not package them.
{ pkgs, iroh }:
let
  common = {
    version = "1.2.0";
    src = iroh;
    cargoLock.lockFile = "${iroh}/Cargo.lock";
    # Upstream's test suites need network access; the binaries are exercised by our checks.
    doCheck = false;
  };
in
{
  iroh-relay = pkgs.rustPlatform.buildRustPackage (
    common
    // {
      pname = "iroh-relay";
      cargoBuildFlags = [
        "--package"
        "iroh-relay"
        "--features"
        "server"
        "--bin"
        "iroh-relay"
      ];
      meta = {
        description = "iroh relay server";
        homepage = "https://github.com/n0-computer/iroh";
        license = with pkgs.lib.licenses; [
          mit
          asl20
        ];
        mainProgram = "iroh-relay";
      };
    }
  );

  iroh-dns-server = pkgs.rustPlatform.buildRustPackage (
    common
    // {
      pname = "iroh-dns-server";
      cargoBuildFlags = [
        "--package"
        "iroh-dns-server"
        "--bin"
        "iroh-dns-server"
      ];
      meta = {
        description = "iroh pkarr relay and DNS server for address lookup";
        homepage = "https://github.com/n0-computer/iroh";
        license = with pkgs.lib.licenses; [
          mit
          asl20
        ];
        mainProgram = "iroh-dns-server";
      };
    }
  );
}
