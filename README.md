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

Hosts are NixOS configurations in a Nix flake (see
[ADR 0003](https://github.com/tidefell/tidefell/blob/main/docs/adr/0003-nix-infrastructure.md)).
The monorepo is a flake input pinned to a release tag. Nothing here is deployable yet.

## Secrets

Secrets are never committed. `*.env` files and `secrets/` directories are gitignored; supply
secrets in encrypted form (agenix or sops-nix).

## Conventions

Read [CONVENTIONS.md](CONVENTIONS.md) before making changes.

## License

[GNU Affero General Public License v3.0 only](LICENSE) (`AGPL-3.0-only`).
