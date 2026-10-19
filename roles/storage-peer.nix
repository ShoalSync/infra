# Role: storage peer (ADR 0023). Stores encrypted folders for their members without being able to
# read them: it holds no key, only sealed versions and chunks, under its data directory. Stored
# folders are set per host in `services.tidefelld.settings.storage.folders`, each with its ID, the
# member users whose devices may sync it, a quota and a retention for replaced versions:
#
#   services.tidefelld.settings.storage.folders = [
#     { id = "<folder id>"; members = [ "<user id>" ]; quota_bytes = 100000000000; }
#   ];
#
# The members add this device's ID as a storage peer of the folder.
{ config, lib, ... }:
{
  services.tidefelld = {
    enable = true;
    openFirewall = true;
    settings.network.bind = lib.mkDefault "0.0.0.0:7777";
  };

  assertions = [
    {
      assertion = (config.services.tidefelld.settings.storage.folders or [ ]) != [ ];
      message = "role-storage-peer: list the folders it stores in services.tidefelld.settings.storage.folders";
    }
    {
      assertion = !(config.services.tidefelld.settings ? web);
      message = "role-storage-peer: a storage peer runs no web peer";
    }
  ];
}
