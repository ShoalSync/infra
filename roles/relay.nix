# Role: public relay for Tidefell peers.
{ config, lib, ... }:
{
  options.tidefell.domain = lib.mkOption {
    type = lib.types.str;
    example = "tidefell.org";
    description = "Base domain for Tidefell's hosted services.";
  };

  config.services.tidefell-relay = {
    enable = true;
    hostname = lib.mkDefault "relay.${config.tidefell.domain}";
  };
}
