# services.shoal-relay: a self-hosted iroh relay for Shoal peers.
#
# `settings` is iroh-relay's TOML configuration. With TLS in LetsEncrypt mode, certificates
# are stored in the state directory. Ports: TCP 80 (HTTP, ACME), TCP 443 (HTTPS relay),
# UDP 7842 (QUIC address discovery). With `tls.enable = false` the relay serves plain HTTP on
# `settings.http_bind_addr` for a TLS-terminating reverse proxy, without QUIC address discovery.
{ relayPackage }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.shoal-relay;
  format = pkgs.formats.toml { };
  relay = "${lib.getExe cfg.package} --config-path ${format.generate "iroh-relay.toml" cfg.settings}";
in
{
  options.services.shoal-relay = {
    enable = lib.mkEnableOption "the Shoal (iroh) relay server";

    package = lib.mkOption {
      type = lib.types.package;
      default = relayPackage pkgs;
      defaultText = lib.literalExpression "infra.packages.\${system}.iroh-relay";
      description = "Package providing `iroh-relay`.";
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "relay.shoal.org";
      description = "Public DNS name of the relay; used for its LetsEncrypt certificate.";
    };

    acmeContact = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ops@shoal.org";
      description = "Contact email given to LetsEncrypt.";
    };

    tls.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Terminate TLS in the relay with a LetsEncrypt certificate. Turn off to run it behind a
        reverse proxy that terminates TLS.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open TCP 80 and 443 and UDP 7842.";
    };

    accessTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File holding the token that devices must present to use the relay
        (`access.shared_token`); without it, the relay serves any device that reaches it.
        Given to the service as a systemd credential, so it may be readable by root alone. Use a
        path to a secret, not a Nix path literal, which would copy it into the store. The relay
        does not start if the file is missing or empty.
      '';
    };

    settings = lib.mkOption {
      inherit (format) type;
      default = { };
      description = "Additional iroh-relay configuration, merged over the defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.shoal-relay.settings = {
      enable_relay = lib.mkDefault true;
      http_bind_addr = lib.mkDefault "[::]:80";
      enable_quic_addr_discovery = lib.mkDefault cfg.tls.enable;
      enable_metrics = lib.mkDefault true;
      metrics_bind_addr = lib.mkDefault "127.0.0.1:9090";
    }
    # The token itself comes from the credential, through the environment: never the store.
    # An empty list with no token makes iroh-relay refuse to start, so it fails closed.
    // lib.optionalAttrs (cfg.accessTokenFile != null) {
      access.shared_token = [ ];
    }
    // lib.optionalAttrs cfg.tls.enable {
      tls = {
        https_bind_addr = lib.mkDefault "[::]:443";
        hostname = lib.mkDefault [ cfg.hostname ];
        cert_mode = lib.mkDefault "LetsEncrypt";
        cert_dir = lib.mkDefault "/var/lib/shoal-relay/certs";
        prod_tls = lib.mkDefault true;
      }
      // lib.optionalAttrs (cfg.acmeContact != null) { contact = lib.mkDefault cfg.acmeContact; };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        80
        443
      ];
      allowedUDPPorts = [ 7842 ];
    };

    systemd.services.shoal-relay = {
      description = "Shoal relay (iroh-relay)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart =
          if cfg.accessTokenFile == null then
            relay
          else
            pkgs.writeShellScript "shoal-relay" ''
              set -eu
              IROH_RELAY_ACCESS_TOKEN=$(cat "$CREDENTIALS_DIRECTORY/access-token")
              export IROH_RELAY_ACCESS_TOKEN
              exec ${relay}
            '';
        LoadCredential = lib.optional (cfg.accessTokenFile != null) "access-token:${toString cfg.accessTokenFile}";
        DynamicUser = true;
        StateDirectory = "shoal-relay";
        WorkingDirectory = "/var/lib/shoal-relay";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        PrivateDevices = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RemoveIPC = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
          "AF_UNIX"
        ];
        LockPersonality = true;
        RestrictSUIDSGID = true;
      };
    };
  };
}
