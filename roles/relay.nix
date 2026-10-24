# Role: public relay for Shoal peers.
{ config, lib, ... }:
{
  imports = [ ../modules/common.nix ];

  config.services.shoal-relay = {
    enable = true;
    hostname = lib.mkDefault "relay.${config.shoal.domain}";
  };
}
