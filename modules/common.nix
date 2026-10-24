# Options shared by the roles, so that several roles can run on one host.
{ lib, ... }:
{
  options.shoal.domain = lib.mkOption {
    type = lib.types.str;
    example = "shoal.org";
    description = "Base domain of this deployment. Services run on names under it.";
  };
}
