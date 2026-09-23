# Role: DNS/pkarr address lookup for Tidefell peers.
{ config, lib, ... }:
{
  options.tidefell.domain = lib.mkOption {
    type = lib.types.str;
    example = "tidefell.org";
    description = "Base domain for Tidefell's hosted services.";
  };

  config.services.tidefell-dns = {
    enable = true;
    origin = lib.mkDefault "dns.${config.tidefell.domain}";
  };
}
