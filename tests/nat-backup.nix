# A phone behind NAT backs up to a home server (ADR 0039). Looking into a slow backup on the
# Android emulator, the phone's messages to the server waited in the connection for minutes; the
# same topology on real networking does not, and this keeps it so.
#
# Three VMs: a router that masquerades the phone's network and runs a relay, a server on the
# router's outside network, and a phone on its inside network that the server cannot reach. The
# phone is send-only and dials the server. Photos backed up must arrive within a minute
# directly, and within three once the router stops forwarding the phone's direct traffic, so
# everything goes through the relay, as on many mobile networks.
{
  pkgs,
  tidefelld,
  # The infra relay module.
  relay,
}:
let
  # Both use the router's relay, at its outside address.
  network =
    nodes:
    let
      router = (pkgs.lib.head nodes.router.networking.interfaces.eth1.ipv4.addresses).address;
    in
    {
      relay = {
        mode = "custom";
        urls = [ "http://${router}:3340" ];
      };
      address_lookup = false;
      local_discovery = false;
    };
in
pkgs.testers.runNixOSTest {
  name = "nat-backup";

  nodes = {
    router =
      { pkgs, ... }:
      {
        imports = [ relay ];
        virtualisation.vlans = [
          1
          2
        ];
        networking = {
          nat = {
            enable = true;
            internalInterfaces = [ "eth2" ];
            externalInterface = "eth1";
          };
          firewall.allowedTCPPorts = [ 3340 ];
          nftables.enable = true;
        };
        environment.systemPackages = [ pkgs.nftables ];
        # The infra relay module, as on an always-on peer: plain HTTP, which a proxy would
        # wrap in TLS.
        services.tidefell-relay = {
          enable = true;
          hostname = "router";
          tls.enable = false;
          openFirewall = false;
          settings = {
            http_bind_addr = "0.0.0.0:3340";
            enable_metrics = false;
          };
        };
      };
    server =
      { nodes, ... }:
      {
        imports = [ tidefelld ];
        virtualisation.vlans = [ 1 ];
        networking.firewall.allowedUDPPorts = [ 7777 ];
        services.tidefelld = {
          enable = true;
          settings.network = network nodes // {
            bind = "0.0.0.0:7777";
          };
        };
      };
    phone =
      { nodes, lib, ... }:
      {
        imports = [ tidefelld ];
        virtualisation.vlans = [ 2 ];
        networking = {
          defaultGateway = {
            inherit (lib.head nodes.router.networking.interfaces.eth2.ipv4.addresses) address;
            interface = "eth1";
          };
          # Only the router's networks: no route to the server but through the router.
          useDHCP = false;
        };
        services.tidefelld = {
          enable = true;
          settings.network = network nodes;
        };
      };
  };

  testScript =
    { nodes, ... }:
    let
      routerOutside = (pkgs.lib.head nodes.router.networking.interfaces.eth1.ipv4.addresses).address;
    in
    ''
      import json
      import re
      import time

      DATA = "/var/lib/tidefell"
      CAMERA = f"{DATA}/folders/camera"
      RELAY = "http://${routerOutside}:3340"
      PHOTO_BYTES = 5 * 1024 * 1024
      PHOTOS = 40


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


      def online(machine):
          machine.succeed("systemctl start tidefelld")
          machine.wait_until_succeeds(f"test -S {DATA}/control.sock")
          machine.wait_until_succeeds(f"runuser -u tidefell -- tidefell --data-dir {DATA} status")


      def backup(batch, limit):
          """Adds a batch of photos on the phone and returns how long the server took to have them."""
          stage = f"{DATA}/stage-{batch}"
          as_tidefell(phone, f"mkdir -p {stage}")
          for i in range(PHOTOS):
              as_tidefell(phone, f"sh -c 'head -c {PHOTO_BYTES} /dev/urandom > {stage}/IMG_{batch}_{i}.jpg'")
          want = PHOTOS * PHOTO_BYTES
          started = time.monotonic()
          # Moved in at once, as a camera adds a finished photo; the phone's scan finds them.
          as_tidefell(phone, f"sh -c 'mv {stage}/* {CAMERA}/'")
          server.wait_until_succeeds(
              f"test $(find {CAMERA} -name 'IMG_{batch}_*' -type f -printf '%s\\n' | "
              f"awk '{{ s += $1 }} END {{ print s + 0 }}') -ge {want}",
              timeout=limit,
          )
          took = time.monotonic() - started
          print(f"backup {batch}: {PHOTOS} photos, {want >> 20} MiB, in {took:.1f} s")
          return took


      start_all()
      router.wait_for_unit("tidefell-relay.service")
      # Hardened: systemd rates the relay's exposure low (0 to 10, lower is better).
      exposure = router.succeed("systemd-analyze security tidefell-relay.service | tail -n 1")
      print(exposure)
      assert float(find(r"exposure level for \S+: ([0-9.]+)", exposure)) <= 2.0, exposure
      for machine in (server, phone):
          machine.wait_for_unit("multi-user.target")
          machine.succeed("systemctl stop tidefelld")

      with subtest("the server certifies the phone, which cannot be reached from outside"):
          as_tidefell(server, f"tidefelld init --data-dir {DATA} --name server")
          server_id = device_id(server)
          as_tidefell(
              server,
              f"tidefelld certify --user-key {DATA}/user.key --device {device_id(phone)}"
              " --name phone --out /tmp/phone.cert",
          )
          cert = server.succeed("base64 -w0 /tmp/phone.cert").strip()
          phone.succeed(f"echo {cert} | base64 -d > /tmp/device.cert && chmod a+r /tmp/device.cert")
          as_tidefell(phone, f"tidefelld init --data-dir {DATA} --name phone --certificate /tmp/device.cert")
          phone_ip = find(r"inet ([0-9.]+)/", phone.succeed("ip -4 -o addr show dev eth1"))
          server.fail(f"ping -c 1 -W 2 {phone_ip}")

      with subtest("the phone joins the server's folder, send-only, through the NAT"):
          online(server)
          folder = json.loads(cli(server, f"--json folder create {CAMERA}"))["id"]
          server_ip = find(r"inet ([0-9.]+)/", server.succeed("ip -4 -o addr show dev eth1"))
          online(phone)
          cli(phone, f"peer add {server_id} --addr {server_ip}:7777 --relay {RELAY}")
          cli(phone, f"folder join {folder} {CAMERA} --direction send-only")
          server.wait_until_succeeds(
              f"runuser -u tidefell -- tidefell --data-dir {DATA} status | grep -q 'connected'"
          )

      with subtest("photos taken on the phone reach the server within a minute"):
          backup("direct", 60)

      with subtest("with no direct path, they still arrive, through the relay, within three minutes"):
          router.succeed(
              "nft add table inet block && "
              "nft add chain inet block forward '{ type filter hook forward priority -10 ; }' && "
              "nft add rule inet block forward iifname eth2 oifname eth1 meta l4proto udp drop"
          )
          backup("relay", 180)
    '';
}
