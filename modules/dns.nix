# services.shoal-dns: a self-hosted iroh DNS/pkarr server for address lookup.
#
# `settings` is iroh-dns-server's TOML configuration. Ports: UDP and TCP 53 (DNS), TCP 80 and
# 443 (pkarr publishing over HTTP(S), ACME).
{ dnsPackage }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.shoal-dns;
  format = pkgs.formats.toml { };
in
{
  options.services.shoal-dns = {
    enable = lib.mkEnableOption "the Shoal (iroh) DNS and pkarr server";

    package = lib.mkOption {
      type = lib.types.package;
      default = dnsPackage pkgs;
      defaultText = lib.literalExpression "infra.packages.\${system}.iroh-dns-server";
      description = "Package providing `iroh-dns-server`.";
    };

    origin = lib.mkOption {
      type = lib.types.str;
      example = "dns.shoal.org";
      description = "DNS zone the server is authoritative for; also its HTTPS hostname.";
    };

    publicIPv4 = lib.mkOption {
      type = lib.types.str;
      example = "203.0.113.10";
      description = "Public IPv4 address returned for the zone apex.";
    };

    acmeContact = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ops@shoal.org";
      description = "Contact email given to LetsEncrypt.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open UDP/TCP 53 and TCP 80 and 443.";
    };

    settings = lib.mkOption {
      inherit (format) type;
      default = { };
      description = "Additional iroh-dns-server configuration, merged over the defaults.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.shoal-dns.settings = {
      pkarr_put_rate_limit = lib.mkDefault "smart";
      data_dir = lib.mkDefault "/var/lib/shoal-dns";
      http = {
        port = lib.mkDefault 80;
        bind_addr = lib.mkDefault "::";
      };
      https = {
        port = lib.mkDefault 443;
        bind_addr = lib.mkDefault "::";
        domains = lib.mkDefault [ cfg.origin ];
        cert_mode = lib.mkDefault "lets_encrypt";
        letsencrypt_prod = lib.mkDefault true;
      }
      // lib.optionalAttrs (cfg.acmeContact != null) {
        letsencrypt_contact = lib.mkDefault cfg.acmeContact;
      };
      dns = {
        port = lib.mkDefault 53;
        bind_addr = lib.mkDefault "::";
        default_soa = lib.mkDefault "ns1.${cfg.origin} hostmaster.${cfg.origin} 0 10800 3600 604800 3600";
        default_ttl = lib.mkDefault 30;
        origins = lib.mkDefault [
          "${cfg.origin}."
          "."
        ];
        rr_a = lib.mkDefault cfg.publicIPv4;
        rr_ns = lib.mkDefault "ns1.${cfg.origin}.";
      };
      mainline.enabled = lib.mkDefault false;
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        53
        80
        443
      ];
      allowedUDPPorts = [ 53 ];
    };

    systemd.services.shoal-dns = {
      description = "Shoal DNS and pkarr server (iroh-dns-server)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} --config ${format.generate "iroh-dns-server.toml" cfg.settings}";
        DynamicUser = true;
        StateDirectory = "shoal-dns";
        WorkingDirectory = "/var/lib/shoal-dns";
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
