# Options shared by the roles, so that several roles can run on one host.
{ lib, ... }:
{
  options.tidefell.domain = lib.mkOption {
    type = lib.types.str;
    example = "tidefell.org";
    description = "Base domain of this deployment. Services run on names under it.";
  };
}
