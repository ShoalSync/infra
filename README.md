# Tidefell infrastructure

NixOS modules and roles for servers that support [Tidefell](https://github.com/tidefell/tidefell).
Tidefell needs no central server: these improve connectivity, and let anyone run an always-on
peer on a machine they control. The project runs no storage or web service for users
([ADR 0018](https://github.com/tidefell/tidefell/blob/main/docs/adr/0018-always-on-peers.md)).

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
[ADR 0003](https://github.com/tidefell/tidefell/blob/main/docs/adr/0003-nix-infrastructure.md)).

| Flake output | What it is |
| --- | --- |
| `packages.<system>.iroh-relay`, `iroh-dns-server` | Upstream servers, from the iroh release in `flake.lock` |
| `nixosModules.relay`, `dns` | `services.tidefell-relay`, `services.tidefell-dns` |
| `nixosModules.tidefelld` | The monorepo's `tidefelld` module, from the pinned release |
| `nixosModules.role-relay`, `role-dns`, `role-replica`, `role-always-on` | Roles to import into a host |
| `checks.x86_64-linux.*` | Each role evaluated and its units and configuration built |
| `checks.x86_64-linux.always-on` | Three VMs: a laptop and a phone, never online together, sync through an always-on peer (needs KVM) |

Pins live in `flake.nix` and `flake.lock`: the monorepo at a release tag (currently `v0.11.0`),
iroh at `v1.2.0`, and nixpkgs following the monorepo's pin. Update the monorepo by changing the
tag in `flake.nix` and running `nix flake update tidefell`.

No concrete hosts are defined yet; each real host adds a `nixosConfigurations.<name>` with its
hardware configuration and one or more roles.

### Always-on peer

```nix
{
  imports = [ infra.nixosModules.role-always-on ];
  tidefell.domain = "tidefell.example.org";   # the web peer's HTTPS name; point DNS at the host
  tidefell.alwaysOn = {
    acmeEmail = "me@example.org";
    relay.enable = true;                       # optional: relay.tidefell.example.org
  };
}
```

It opens UDP 7777 for sync and TCP 80 and 443 for Caddy, which obtains the certificates.
Set up its identity, folders and web accounts on the host with `tidefelld` and `tidefell`, as
the monorepo's always-on guide describes.

## CI

`nix flake check` runs on every push. It includes the always-on VM test, so the runner needs
KVM. The monorepo is private, so CI mints a read-only token
for it with the organisation's GitHub App (secrets `CROSS_REPO_CI_APP`, the App ID, and
`CROSS_REPO_CI_KEY`, its private key). The app must be installed on `tidefell/tidefell` with
read access to contents.

## Secrets

Secrets are never committed. `*.env` files and `secrets/` directories are gitignored; supply
secrets in encrypted form (agenix or sops-nix).

## Conventions

Read [CONVENTIONS.md](CONVENTIONS.md) before making changes.

## License

[GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`).
