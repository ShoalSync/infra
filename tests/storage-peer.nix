# Phase 6 exit criterion (ADR 0023): two devices of one user sync an encrypted folder only
# through a storage peer of another user's, deployed with role-storage-peer, and nothing of the
# folder's names or contents is on the storage peer's disk in the clear.
#
# Three VMs on one network, with no relays, address lookup or local discovery. The laptop and the
# phone each know only the storage peer, so the phone gets the folder's key, granted by the
# laptop, and its content through it. The user's key is a fixture: the storage peer's
# configuration names the user before any VM starts.
{
  pkgs,
  storagePeer,
  tidefelld,
}:
let
  # A user key made for this test only, and its user ID.
  userKey = pkgs.writeText "user.key" ''
    tidefell-user-key 1
    7f82bc1b7c2755f5ad1c4128c611d84c8cb95da6b432624419414a37377cbab7
  '';
  user = "439440322e8e8314f1e02c93e78369c46581f678e95dace2c87d0e2a0d0a70f2";
  folder = "abababababababababababababababababababababababababababababababab";
  network = {
    relay.mode = "disabled";
    address_lookup = false;
    local_discovery = false;
  };
  device = {
    imports = [ tidefelld ];
    services.tidefelld = {
      enable = true;
      settings.network = network // {
        bind = "0.0.0.0:7777";
      };
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "storage-peer";

  nodes = {
    storage = {
      imports = [ storagePeer ];
      services.tidefelld.settings = {
        inherit network;
        storage.folders = [
          {
            id = folder;
            members = [ user ];
            quota_bytes = 1000000000;
          }
        ];
      };
    };
    laptop = device;
    phone = device;
  };

  testScript = ''
    import json
    import re

    DATA = "/var/lib/tidefell"
    PAPERS = f"{DATA}/folders/papers"
    FOLDER = "${folder}"
    # What must never be on the storage peer's disk: the file's name and its contents.
    NAME = "tax-return-2026.txt"
    SECRET = "tidefell-storage-peer-plaintext-marker"


    def find(pattern: str, text: str) -> str:
        found = re.search(pattern, text)
        assert found is not None, f"{pattern!r} not in {text!r}"
        return found.group(1)


    def as_tidefell(machine, command):
        return machine.succeed(f"runuser -u tidefell -- {command}")


    def cli(machine, args):
        return as_tidefell(machine, f"tidefell --data-dir {DATA} {args}")


    def device_id(machine):
        out = as_tidefell(machine, f"tidefelld id --data-dir {DATA}")
        return find(r"device: ([0-9a-f]{64})", out)


    def ip(machine):
        out = machine.succeed("ip -4 -o addr show dev eth1")
        return find(r"inet ([0-9.]+)/", out)


    def online(machine):
        machine.succeed("systemctl start tidefelld")
        machine.wait_until_succeeds(f"test -S {DATA}/control.sock")
        machine.wait_until_succeeds(f"runuser -u tidefell -- tidefell --data-dir {DATA} status")


    def offline(machine):
        machine.succeed("systemctl stop tidefelld")


    def stored(field):
        folders = json.loads(cli(storage, "--json storage"))
        assert len(folders) == 1, folders
        encryption = folders[0]["encryption"]
        assert encryption["key_generation"] is None, encryption
        return encryption["stored"][field]


    start_all()
    for machine in (storage, laptop, phone):
        machine.wait_for_unit("multi-user.target")
        # Until it is certified, the service keeps restarting.
        offline(machine)

    with subtest("the storage peer is its operator's; the laptop and the phone are the user's"):
        as_tidefell(storage, f"tidefelld init --data-dir {DATA} --name storage")
        storage_id = device_id(storage)
        storage_addr = f"{ip(storage)}:7777"
        laptop.succeed("install -o tidefell -m 600 ${userKey} /tmp/user.key")
        as_tidefell(laptop, f"tidefelld init --data-dir {DATA} --name laptop --user-key /tmp/user.key")
        as_tidefell(
            laptop,
            f"tidefelld certify --user-key /tmp/user.key --device {device_id(phone)}"
            " --name phone --out /tmp/phone.cert",
        )
        cert = laptop.succeed("base64 -w0 /tmp/phone.cert").strip()
        phone.succeed(f"echo {cert} | base64 -d > /tmp/device.cert && chmod a+r /tmp/device.cert")
        as_tidefell(phone, f"tidefelld init --data-dir {DATA} --name phone --certificate /tmp/device.cert")

    with subtest("the laptop stores an encrypted folder on the storage peer"):
        online(storage)
        online(laptop)
        cli(laptop, f"peer add {storage_id} --addr {storage_addr}")
        cli(laptop, f"folder join {FOLDER} {PAPERS} --encrypted --storage-peer {storage_id}")
        as_tidefell(laptop, f"sh -c 'printf %s {SECRET} > {PAPERS}/{NAME}'")
        cli(laptop, f"folder scan {FOLDER}")
        storage.wait_until_succeeds(
            f"runuser -u tidefell -- tidefell --data-dir {DATA} --json storage > /tmp/stored.json"
            " && grep -Eq '\"versions\": ?1\\b' /tmp/stored.json"
            " && grep -Eq '\"missing_chunks\": ?0\\b' /tmp/stored.json",
            timeout=120,
        )
        assert stored("bytes") > 0

    with subtest("the phone, which knows only the storage peer, gets the folder through it"):
        online(phone)
        cli(phone, f"peer add {storage_id} --addr {storage_addr}")
        cli(phone, f"folder join {FOLDER} {PAPERS} --encrypted --storage-peer {storage_id}")
        phone.wait_until_succeeds(f"grep -q {SECRET} {PAPERS}/{NAME}", timeout=120)
        # Its key was granted by the laptop and relayed: the same generation on both.
        status = json.loads(cli(phone, "--json status"))
        papers = [f for f in status["folders"] if f["id"] == FOLDER][0]
        assert papers["encryption"]["key_generation"] == 1, papers

    with subtest("nothing of the folder is on the storage peer's disk in the clear"):
        offline(storage)
        for plain in (NAME, SECRET):
            storage.fail(f"grep -rqa {plain} /var/lib/tidefell /var/log /tmp")
  '';
}
