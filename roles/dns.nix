# Role: DNS/pkarr address lookup for Tidefell peers.
{ config, lib, ... }:
{
  imports = [ ../modules/common.nix ];

  config.services.tidefell-dns = {
    enable = true;
    origin = lib.mkDefault "dns.${config.tidefell.domain}";
  };
}
