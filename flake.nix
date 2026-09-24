{
  description = "Tidefell infrastructure: relay, DNS/pkarr lookup, full replicas and self-run always-on peers";

  inputs = {
    # The monorepo release this infrastructure runs. Bump deliberately; flake.lock records it.
    tidefell.url = "github:tidefell/tidefell/v0.5.0";
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
        # A self-run always-on peer: full replica, web peer over HTTPS, optional relay.
        role-always-on = {
          imports = [
            self.nixosModules.relay
            self.nixosModules.tidefelld
            ./roles/always-on.nix
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
          alwaysOn = evalRole self.nixosModules.role-always-on {
            tidefell.domain = "example.org";
            tidefell.alwaysOn.relay.enable = true;
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
          always-on-config =
            assert alwaysOn.services.caddy.enable;
            assert alwaysOn.services.tidefelld.settings.web.bind == "127.0.0.1:8080";
            assert alwaysOn.services.tidefelld.settings.network.relay.urls == [ "https://relay.example.org" ];
            assert builtins.elem 443 alwaysOn.networking.firewall.allowedTCPPorts;
            assert builtins.elem 7777 alwaysOn.networking.firewall.allowedUDPPorts;
            pkgs.runCommand "always-on-config-check" { } ''
              grep -q 'tidefelld run --config' ${unit alwaysOn "tidefelld"}
              config=$(grep -o '/nix/store/[^ ]*-iroh-relay.toml' ${unit alwaysOn "tidefell-relay"})
              grep -q '127.0.0.1:3340' "$config"
              ! grep -q 'cert_mode' "$config"
              touch $out
            '';
          # The exit criterion of Phase 5: three VMs; needs KVM.
          always-on = import ./tests/always-on.nix {
            inherit pkgs;
            alwaysOn = self.nixosModules.role-always-on;
            tidefelld = self.nixosModules.tidefelld;
          };
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
