{
  description = "Tidefell hosted infrastructure: relay, DNS/pkarr lookup and full replicas";

  inputs = {
    # The monorepo release this infrastructure runs. Bump deliberately; flake.lock records it.
    tidefell.url = "github:tidefell/tidefell/v0.2.0";
    # One nixpkgs for everything: the monorepo's pin.
    nixpkgs.follows = "tidefell/nixpkgs";
    # Upstream relay and DNS server sources, built by ./packages.nix.
    iroh = {
      url = "github:n0-computer/iroh/v1.2.0";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      tidefell,
      iroh,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      packagesFor = pkgs: import ./packages.nix { inherit pkgs iroh; };
    in
    {
      packages = forAllSystems packagesFor;

      nixosModules = {
        relay = import ./modules/relay.nix { relayPackage = pkgs: (packagesFor pkgs).iroh-relay; };
        dns = import ./modules/dns.nix { dnsPackage = pkgs: (packagesFor pkgs).iroh-dns-server; };
        tidefelld = tidefell.nixosModules.tidefelld;
        # Roles, to import from a host's configuration alongside its hardware configuration.
        role-relay = {
          imports = [
            self.nixosModules.relay
            ./roles/relay.nix
          ];
        };
        role-dns = {
          imports = [
            self.nixosModules.dns
            ./roles/dns.nix
          ];
        };
        role-replica = {
          imports = [
            self.nixosModules.tidefelld
            ./roles/replica.nix
          ];
        };
      };

      # Each role, evaluated in a container system: builds its systemd unit and configuration.
      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          evalRole =
            role: extra:
            (nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                role
                {
                  boot.isContainer = true;
                  system.stateVersion = "25.11";
                  networking.hostName = "check";
                }
                extra
              ];
            }).config;
          relay = evalRole self.nixosModules.role-relay {
            tidefell.domain = "example.org";
            services.tidefell-relay.acmeContact = "ops@example.org";
          };
          dns = evalRole self.nixosModules.role-dns {
            tidefell.domain = "example.org";
            services.tidefell-dns.publicIPv4 = "203.0.113.10";
          };
          replica = evalRole self.nixosModules.role-replica {
            services.tidefelld.settings.folders = [
              {
                id = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
                path = "/srv/tidefell/photos";
                members = [ "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ];
                retention_days = 30;
              }
            ];
          };
          unit = config: name: "${config.systemd.units."${name}.service".unit}/${name}.service";
        in
        {
          relay =
            assert relay.networking.firewall.allowedUDPPorts == [ 7842 ];
            pkgs.runCommand "relay-check" { } ''
              grep -q 'iroh-relay --config-path' ${unit relay "tidefell-relay"}
              config=$(grep -o '/nix/store/[^ ]*-iroh-relay.toml' ${unit relay "tidefell-relay"})
              grep -q 'relay.example.org' "$config"
              grep -q 'ops@example.org' "$config"
              touch $out
            '';
          dns = pkgs.runCommand "dns-check" { } ''
            grep -q 'iroh-dns-server --config' ${unit dns "tidefell-dns"}
            config=$(grep -o '/nix/store/[^ ]*-iroh-dns-server.toml' ${unit dns "tidefell-dns"})
            grep -q 'dns.example.org' "$config"
            grep -q '203.0.113.10' "$config"
            touch $out
          '';
          replica = pkgs.runCommand "replica-check" { } ''
            grep -q 'tidefelld run --config' ${unit replica "tidefelld"}
            touch $out
          '';
          # The binaries run and report their versions.
          binaries = pkgs.runCommand "binaries-check" { } ''
            ${self.packages.x86_64-linux.iroh-relay}/bin/iroh-relay --version
            ${self.packages.x86_64-linux.iroh-dns-server}/bin/iroh-dns-server --help > /dev/null
            touch $out
          '';
        };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
