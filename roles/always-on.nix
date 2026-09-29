# Role: a self-run always-on peer (ADR 0018, option B).
#
# A full replica that is always online, so devices that are rarely awake together still sync
# through it. It is the owner's own machine, such as a small VPS: it stores plaintext, like any
# replica. Optionally it serves the web peer over HTTPS and a relay, both behind Caddy, which
# obtains their certificates.
#
# Identity, folders and web accounts are set up on the host with `tidefelld` and `tidefell`;
# see the always-on guide in the monorepo docs.
{ config, lib, ... }:
let
  cfg = config.tidefell.alwaysOn;
  domain = config.tidefell.domain;
  proxied = (cfg.web.enable && cfg.web.tls) || cfg.relay.enable;
in
{
  imports = [ ../modules/common.nix ];

  options.tidefell.alwaysOn = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 7777;
      description = "UDP port for sync, opened in the firewall.";
    };

    web = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Serve the web peer at `https://<tidefell.domain>`.";
      };
      tls = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Put the web peer behind Caddy with an automatic HTTPS certificate for
          `tidefell.domain`. Turn off only for testing: the web peer then listens on
          127.0.0.1:8080 without TLS.
        '';
      };
      shareLinks = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Let web accounts create share links (ADR 0019). Off by default.
        '';
      };
    };

    relay.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also run a relay at `https://relay.<tidefell.domain>`, behind Caddy, and have this
        peer use it. Other devices use it by listing it in their `network.relay` settings.
      '';
    };

    metrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Serve tidefelld's Prometheus metrics on `127.0.0.1:<port>` and scrape them with this
          host's Prometheus (`services.prometheus`), if it runs (ADR 0030). The endpoint has no
          authentication, so it stays on loopback.
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9477;
        description = "Loopback TCP port tidefelld serves `/metrics` on.";
      };
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "me@example.org";
      description = "Contact email for the HTTPS certificates.";
    };
  };

  config = lib.mkMerge [
    {
      services.tidefelld = {
        enable = true;
        openFirewall = true;
        settings.network.bind = lib.mkDefault "0.0.0.0:${toString cfg.port}";
      };
    }

    (lib.mkIf cfg.web.enable {
      services.tidefelld.settings.web = {
        bind = "127.0.0.1:8080";
        secure_cookies = cfg.web.tls;
      }
      // lib.optionalAttrs cfg.web.shareLinks { share_links = true; };
    })

    (lib.mkIf (cfg.web.enable && cfg.web.tls) {
      services.caddy.virtualHosts.${domain}.extraConfig = ''
        reverse_proxy 127.0.0.1:8080
      '';
    })

    (lib.mkIf cfg.metrics.enable {
      services.tidefelld.settings.metrics.listen = "127.0.0.1:${toString cfg.metrics.port}";
      services.prometheus.scrapeConfigs = [
        {
          job_name = "tidefelld";
          static_configs = [ { targets = [ "127.0.0.1:${toString cfg.metrics.port}" ]; } ];
        }
      ];
    })

    (lib.mkIf cfg.relay.enable {
      services.tidefell-relay = {
        enable = true;
        hostname = "relay.${domain}";
        tls.enable = false;
        openFirewall = false;
        settings.http_bind_addr = "127.0.0.1:3340";
      };
      services.caddy.virtualHosts."relay.${domain}".extraConfig = ''
        reverse_proxy 127.0.0.1:3340
      '';
      services.tidefelld.settings.network.relay = {
        mode = "custom";
        urls = [ "https://relay.${domain}" ];
      };
    })

    (lib.mkIf proxied {
      services.caddy = {
        enable = true;
        email = cfg.acmeEmail;
      };
      networking.firewall.allowedTCPPorts = [
        80
        443
      ];
    })
  ];
}
