# Role: public relay for Tidefell peers.
{ config, lib, ... }:
{
  imports = [ ../modules/common.nix ];

  config.services.tidefell-relay = {
    enable = true;
    hostname = lib.mkDefault "relay.${config.tidefell.domain}";
  };
}
