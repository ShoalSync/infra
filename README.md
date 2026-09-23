# Tidefell infrastructure

Deployment configuration for the hosted services that support
[Tidefell](https://github.com/tidefell/tidefell). Tidefell itself needs no central server;
these services improve connectivity and offer a hosted option.

| Service | Purpose |
| --- | --- |
| Relay (`iroh-relay`) | Relays traffic between peers when hole punching fails |
| DNS / pkarr lookup (`iroh-dns-server`) | Resolves peer node IDs to current addresses |
| Hosted web peer | Tidefell web interface with user accounts |
| Full-replica storage | Always-on full replicas for users who want hosted backup |

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
| `nixosModules.role-relay`, `role-dns`, `role-replica` | Roles to import into a host |
| `checks.x86_64-linux.*` | Each role evaluated and its units and configuration built |

Pins live in `flake.nix` and `flake.lock`: the monorepo at a release tag (currently `v0.2.0`),
iroh at `v1.2.0`, and nixpkgs following the monorepo's pin. Update the monorepo by changing the
tag in `flake.nix` and running `nix flake update tidefell`.

No concrete hosts are defined yet; each real host adds a `nixosConfigurations.<name>` with its
hardware configuration and one or more roles.

## CI

`nix flake check` runs on every push. The monorepo is private, so CI mints a read-only token
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
