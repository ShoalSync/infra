{
  description = "Shoal infrastructure: relay, DNS/pkarr lookup, full replicas and self-run always-on peers";

  inputs = {
    # The monorepo release this infrastructure runs, from Forgejo over SSH (the repository is
    # private). Bump the tag deliberately; flake.lock records it. Until the release with storage
    # peers (Phase 6), main as of their configuration.
    shoal.url = "git+ssh://git@github.com/ShoalSync/shoal?ref=refs/tags/v0.24.0-rc.1";
    # One nixpkgs for everything: the monorepo's pin.
    nixpkgs.follows = "shoal/nixpkgs";
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
      shoal,
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
        shoald = shoal.nixosModules.shoald;
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
            self.nixosModules.shoald
            ./roles/replica.nix
          ];
        };
        # A storage peer: stores encrypted folders for others without reading them (ADR 0023).
        role-storage-peer = {
          imports = [
            self.nixosModules.shoald
            ./roles/storage-peer.nix
          ];
        };
        # A self-run always-on peer: full replica, web peer over HTTPS, optional relay.
        role-always-on = {
          imports = [
            self.nixosModules.relay
            self.nixosModules.shoald
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
            shoal.domain = "example.org";
            services.shoal-relay.acmeContact = "ops@example.org";
          };
          dns = evalRole self.nixosModules.role-dns {
            shoal.domain = "example.org";
            services.shoal-dns.publicIPv4 = "203.0.113.10";
          };
          storagePeer = evalRole self.nixosModules.role-storage-peer {
            services.shoald.settings.storage.folders = [
              {
                id = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";
                members = [ "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ];
                quota_bytes = 1000000000;
              }
            ];
          };
          replica = evalRole self.nixosModules.role-replica {
            services.shoald.settings.folders = [
              {
                id = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";
                path = "/srv/shoal/photos";
                members = [ "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ];
                retention_days = 30;
              }
            ];
          };
          alwaysOn = evalRole self.nixosModules.role-always-on {
            shoal = {
              domain = "example.org";
              alwaysOn.relay.enable = true;
              alwaysOn.web.shareLinks = true;
            };
          };
          unit = config: name: "${config.systemd.units."${name}.service".unit}/${name}.service";
          # Shell, Nix and spelling checks over the source (ADR 0031).
          lint =
            name: tools: script:
            pkgs.runCommand name { nativeBuildInputs = tools; } ''
              cd ${self}
              ${script}
              touch $out
            '';
        in
        {
          shellcheck = lint "shellcheck" [ pkgs.shellcheck ] ''
            find . -name '*.sh' -print0 | xargs -0 --no-run-if-empty shellcheck
          '';
          statix = lint "statix" [ pkgs.statix ] "statix check .";
          deadnix = lint "deadnix" [ pkgs.deadnix ] "deadnix --fail .";
          typos = lint "typos" [ pkgs.typos ] "typos";
          relay =
            assert relay.networking.firewall.allowedUDPPorts == [ 7842 ];
            pkgs.runCommand "relay-check" { } ''
              grep -q 'iroh-relay --config-path' ${unit relay "shoal-relay"}
              config=$(grep -o '/nix/store/[^ ]*-iroh-relay.toml' ${unit relay "shoal-relay"})
              grep -q 'relay.example.org' "$config"
              grep -q 'ops@example.org' "$config"
              touch $out
            '';
          # A relay that admits only holders of a token gets it from a credential, never the store.
          relay-token =
            let
              tokened = evalRole self.nixosModules.role-relay {
                shoal.domain = "example.org";
                services.shoal-relay.accessTokenFile = "/run/secrets/relay-token";
              };
            in
            assert tokened.systemd.services.shoal-relay.serviceConfig.LoadCredential == [
              "access-token:/run/secrets/relay-token"
            ];
            pkgs.runCommand "relay-token-check" { } ''
              unit=${unit tokened "shoal-relay"}
              script=$(grep -o '/nix/store/[^ ]*-shoal-relay' "$unit" | head -n 1)
              grep -q 'CREDENTIALS_DIRECTORY/access-token' "$script"
              config=$(grep -o '/nix/store/[^ ]*-iroh-relay.toml' "$script")
              grep -q 'shared_token = \[\]' "$config"
              touch $out
            '';
          dns = pkgs.runCommand "dns-check" { } ''
            grep -q 'iroh-dns-server --config' ${unit dns "shoal-dns"}
            config=$(grep -o '/nix/store/[^ ]*-iroh-dns-server.toml' ${unit dns "shoal-dns"})
            grep -q 'dns.example.org' "$config"
            grep -q '203.0.113.10' "$config"
            touch $out
          '';
          replica = pkgs.runCommand "replica-check" { } ''
            grep -q 'shoald run --config' ${unit replica "shoald"}
            touch $out
          '';
          # The stored folder reaches shoald's configuration, checked by shoald at build.
          storage-peer-config = pkgs.runCommand "storage-peer-config-check" { } ''
            config=$(grep -o '/nix/store/[^ ]*-shoald.toml' ${unit storagePeer "shoald"} | head -1)
            grep -q 'quota_bytes = 1000000000' "$config"
            touch $out
          '';
          always-on-config =
            assert alwaysOn.services.caddy.enable;
            assert alwaysOn.services.shoald.settings.web.bind == "127.0.0.1:8080";
            assert alwaysOn.services.shoald.settings.web.share_links;
            assert alwaysOn.services.shoald.settings.network.relay.urls == [ "https://relay.example.org" ];
            assert builtins.elem 443 alwaysOn.networking.firewall.allowedTCPPorts;
            assert builtins.elem 7777 alwaysOn.networking.firewall.allowedUDPPorts;
            pkgs.runCommand "always-on-config-check" { } ''
              grep -q 'shoald run --config' ${unit alwaysOn "shoald"}
              config=$(grep -o '/nix/store/[^ ]*-iroh-relay.toml' ${unit alwaysOn "shoal-relay"})
              grep -q '127.0.0.1:3340' "$config"
              ! grep -q 'cert_mode' "$config"
              touch $out
            '';
          # The exit criterion of Phase 6 (ADR 0023): two devices sync an encrypted folder only
          # through a storage peer, whose disk holds none of its plaintext; three VMs, needs KVM.
          storage-peer = import ./tests/storage-peer.nix {
            inherit pkgs;
            storagePeer = self.nixosModules.role-storage-peer;
            shoald = self.nixosModules.shoald;
          };
          # The exit criterion of Phase 5: three VMs; needs KVM.
          always-on = import ./tests/always-on.nix {
            inherit pkgs;
            alwaysOn = self.nixosModules.role-always-on;
            shoald = self.nixosModules.shoald;
          };
          # A phone behind NAT backs up to a server directly and through the relay (ADR 0039);
          # three VMs, needs KVM.
          nat-backup = import ./tests/nat-backup.nix {
            inherit pkgs;
            shoald = self.nixosModules.shoald;
            relay = self.nixosModules.relay;
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
