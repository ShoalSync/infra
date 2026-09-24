# Conventions

Read this before changing anything in this repository.

## Owns

NixOS host configurations and deployment for the relay, DNS/pkarr address lookup,
the modules and roles for self-run always-on peers (ADR 0018).

## Consumes

- The monorepo flake (packages and NixOS module), pinned as the `tidefell` flake input to a
  release tag; `flake.lock` records the exact revision (from Phase 2).
- Upstream iroh relay and DNS server, pinned the same way.
- The `tidefelld` config JSON Schema from the pinned release; CI validates configs against it.

## Change order

Changes to shared definitions always start in the monorepo: monorepo change → release tag →
pin bump here. This repository never defines a type, message, config key or term that the
monorepo does not. See [repository map](https://github.com/tidefell/tidefell/blob/main/docs/repos.md).

Work that spans repositories is tracked by one issue in `tidefell/tidefell`, labelled
`repo:infra`.

## Local rules

- **Vocabulary:** use the terms in the [glossary](https://github.com/tidefell/tidefell/blob/main/docs/glossary.md).
- **Tooling:** Nix flakes and NixOS modules ([ADR 0003](https://github.com/tidefell/tidefell/blob/main/docs/adr/0003-nix-infrastructure.md)).
- **Secrets are never committed** in plaintext. Use the encrypted-secrets tool chosen in ADR 0003.
- Config keys come from the monorepo schema. Do not invent keys here.
- **Commits:** Conventional Commits; see [CONTRIBUTING.md](https://github.com/tidefell/tidefell/blob/main/CONTRIBUTING.md).

## Read first

1. [Implementation plan](https://github.com/tidefell/tidefell/blob/main/docs/plan.md)
2. [Glossary](https://github.com/tidefell/tidefell/blob/main/docs/glossary.md)
3. [Architecture decision records](https://github.com/tidefell/tidefell/blob/main/docs/adr/)
