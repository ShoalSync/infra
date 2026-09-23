# Relay

Self-hosted [iroh relay](https://github.com/n0-computer/iroh/tree/main/iroh-relay), used by
Tidefell peers when a direct connection is not possible. Relays only see encrypted traffic.

- Package: `packages.<system>.iroh-relay`, built from the iroh release pinned in `flake.lock`.
- NixOS module: `nixosModules.relay` (`services.tidefell-relay`); role: `nixosModules.role-relay`.
- Ports: TCP 80 (HTTP, ACME), TCP 443 (HTTPS relay), UDP 7842 (QUIC address discovery).
- TLS: LetsEncrypt for `services.tidefell-relay.hostname`, certificates in
  `/var/lib/tidefell-relay/certs`.

Peers use it with `network.relay = { mode = "custom", urls = ["https://relay.<domain>"] }` in
their `tidefelld` configuration.
