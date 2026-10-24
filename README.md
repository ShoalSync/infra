# Shoal infrastructure

Shoal Sync, formerly Tidefell.

NixOS modules and roles for servers that support [Shoal](https://github.com/ShoalSync/shoal).
Shoal needs no central server: these improve connectivity, and let anyone run an always-on
peer on a machine they control. The project runs no storage or web service for users
([ADR 0018](https://github.com/ShoalSync/shoal/blob/main/docs/adr/0018-always-on-peers.md)).

| Service | Purpose |
| --- | --- |
| Relay (`iroh-relay`) | Relays traffic between peers when hole punching fails |
| DNS / pkarr lookup (`iroh-dns-server`) | Resolves peer node IDs to current addresses |
| Always-on peer | A full replica you run yourself, e.g. on a small VPS, with the web peer over HTTPS and an optional relay, so devices that are rarely online together still sync |

## Layout

- [`relay/`](relay/): self-hosted iroh-relay.
- [`dns/`](dns/): self-hosted iroh-dns-server.

## Deployment

Hosts are NixOS configurations built from this flake (see
[ADR 0003](https://github.com/ShoalSync/shoal/blob/main/docs/adr/0003-nix-infrastructure.md)).

| Flake output | What it is |
| --- | --- |
| `packages.<system>.iroh-relay`, `iroh-dns-server` | Upstream servers, from the iroh release in `flake.lock` |
| `nixosModules.relay`, `dns` | `services.shoal-relay`, `services.shoal-dns` |
| `nixosModules.shoald` | The monorepo's `shoald` module, from the pinned release |
| `nixosModules.role-relay`, `role-dns`, `role-replica`, `role-always-on`, `role-storage-peer` | Roles to import into a host |
| `checks.x86_64-linux.*` | Each role evaluated and its units and configuration built |
| `checks.x86_64-linux.always-on` | Three VMs: a laptop and a phone, never online together, sync through an always-on peer (needs KVM) |

Pins live in `flake.nix` and `flake.lock`: the monorepo at a release tag (currently `v0.13.0`),
iroh at `v1.2.0`, and nixpkgs following the monorepo's pin. Update the monorepo by changing the
tag in `flake.nix` and running `nix flake update shoal`.

No concrete hosts are defined yet; each real host adds a `nixosConfigurations.<name>` with its
hardware configuration and one or more roles.

### Always-on peer

```nix
{
  imports = [ infra.nixosModules.role-always-on ];
  shoal.domain = "shoal.example.org";   # the web peer's HTTPS name; point DNS at the host
  shoal.alwaysOn = {
    acmeEmail = "me@example.org";
    relay.enable = true;                       # optional: relay.shoal.example.org
  };
}
```

It opens UDP 7777 for sync and TCP 80 and 443 for Caddy, which obtains the certificates.
Set up its identity, folders and web accounts on the host with `shoald` and `shoal`, as
the monorepo's always-on guide describes.

### Storage peer

A storage peer keeps encrypted folders for other users without being able to read them (ADR
0023): it holds no key, only sealed versions and chunks. List the folders it stores, each with
its members and a quota:

```nix
{
  imports = [ infra.nixosModules.role-storage-peer ];
  services.shoald.settings.storage.folders = [
    {
      id = "<folder id>";
      members = [ "<user id>" ];
      quota_bytes = 100000000000;
    }
  ];
}
```

Set up its identity with `shoald init`; the members add its device ID as a storage peer of
the folder (`shoal folder store-with <folder id> <device id>`). `shoal storage` shows what
it holds. The `storage-peer` VM test checks that two devices sync through one and that its disk
holds none of the folder's names or contents.

## CI

`nix flake check` runs on GitHub's hosted runners for every pull request and push to `main`
(`.github/workflows/`). It includes the NixOS VM tests, so the runner needs KVM, which the hosted
Linux runners have. Nix fetches the pinned monorepo release from GitHub.

## Secrets

Secrets are never committed. `*.env` files and `secrets/` directories are gitignored; supply
secrets in encrypted form (agenix or sops-nix).

## Conventions

Read [CONVENTIONS.md](CONVENTIONS.md) before making changes.

## License

Licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <https://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or <https://opensource.org/licenses/MIT>)

at your option.

All earlier versions of this code, including commits made under the name Tidefell, are also
available under MIT OR Apache-2.0.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
the work by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without
any additional terms or conditions.
