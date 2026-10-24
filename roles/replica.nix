# Role: always-on full replica running shoald from the pinned monorepo release.
# Folders, members and the device certificate are set per host.
{ lib, ... }:
{
  services.shoald = {
    enable = true;
    openFirewall = true;
    settings.network.bind = lib.mkDefault "0.0.0.0:7777";
  };
}
