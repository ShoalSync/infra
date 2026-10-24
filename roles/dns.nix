# Role: DNS/pkarr address lookup for Shoal peers.
{ config, lib, ... }:
{
  imports = [ ../modules/common.nix ];

  config.services.shoal-dns = {
    enable = true;
    origin = lib.mkDefault "dns.${config.shoal.domain}";
  };
}
