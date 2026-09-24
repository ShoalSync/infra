# Phase 5 exit criterion (ADR 0018): a self-run always-on peer, deployed from the pinned
# release, keeps a laptop and a phone in sync while the two are never online together.
#
# Three VMs on one network, with no relays or address lookup. One user: its key stays on the
# always-on peer, which certifies the laptop and the phone. The phone is a partial replica.
{
  pkgs,
  alwaysOn,
  tidefelld,
}:
let
  network = {
    relay.mode = "disabled";
    address_lookup = false;
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
  name = "always-on";

  nodes = {
    server = {
      imports = [ alwaysOn ];
      environment.systemPackages = [ pkgs.curl ];
      tidefell.domain = "server.test";
      # No certificates in the test network: the web peer answers on localhost.
      tidefell.alwaysOn.web.tls = false;
      services.tidefelld.settings.network = network;
    };
    laptop = device;
    phone = device;
  };

  testScript = ''
    import json
    import re

    DATA = "/var/lib/tidefell"
    PHOTOS = f"{DATA}/folders/photos"


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


    def write(machine, name, contents):
        as_tidefell(machine, f"sh -c 'printf %s \"{contents}\" > {PHOTOS}/{name}'")


    start_all()
    for machine in (server, laptop, phone):
        machine.wait_for_unit("multi-user.target")
        # Until it is certified, the service keeps restarting.
        offline(machine)

    with subtest("one user: the always-on peer certifies the laptop and the phone"):
        as_tidefell(server, f"tidefelld init --data-dir {DATA} --name server")
        server_id = device_id(server)
        for machine, name in ((laptop, "laptop"), (phone, "phone")):
            as_tidefell(
                server,
                f"tidefelld certify --user-key {DATA}/user.key --device {device_id(machine)}"
                f" --name {name} --out /tmp/{name}.cert",
            )
            cert = server.succeed(f"base64 -w0 /tmp/{name}.cert").strip()
            machine.succeed(f"echo {cert} | base64 -d > /tmp/device.cert && chmod a+r /tmp/device.cert")
            as_tidefell(machine, f"tidefelld init --data-dir {DATA} --name {name} --certificate /tmp/device.cert")
        server_addr = f"{ip(server)}:7777"

    with subtest("the always-on peer holds the folder"):
        online(server)
        folder = json.loads(cli(server, f"--json folder create {PHOTOS}"))["id"]
        server.succeed("curl -sf http://127.0.0.1:8080/login | grep -q 'Sign in'")

    with subtest("the laptop adds a photo, then goes offline"):
        online(laptop)
        cli(laptop, f"peer add {server_id} --addr {server_addr}")
        cli(laptop, f"folder join {folder} {PHOTOS}")
        write(laptop, "beach.jpg", "sand and sea")
        cli(laptop, f"folder scan {folder}")
        server.wait_until_succeeds(f"grep -qx 'sand and sea' {PHOTOS}/beach.jpg")
        offline(laptop)

    with subtest("the phone, a partial replica, gets the photo from the always-on peer"):
        online(phone)
        cli(phone, f"peer add {server_id} --addr {server_addr}")
        cli(phone, f"folder join {folder} {PHOTOS} --partial 1000000")
        phone.wait_until_succeeds(
            f"runuser -u tidefell -- tidefell --data-dir {DATA} files {folder} | grep -q beach.jpg"
        )
        local = cli(phone, f"fetch {folder} beach.jpg").strip()
        phone.succeed(f"grep -qx 'sand and sea' {local}")

    with subtest("the phone adds a note, goes offline, and the laptop gets it later"):
        write(phone, "note.txt", "back soon")
        cli(phone, f"folder scan {folder}")
        server.wait_until_succeeds(f"grep -qx 'back soon' {PHOTOS}/note.txt")
        offline(phone)
        online(laptop)
        laptop.wait_until_succeeds(f"grep -qx 'back soon' {PHOTOS}/note.txt")
  '';
}
