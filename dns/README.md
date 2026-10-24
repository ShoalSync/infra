# DNS

Self-hosted [iroh DNS server](https://github.com/n0-computer/iroh/tree/main/iroh-dns-server):
peers publish their current addresses as signed pkarr records over HTTPS, and look each other
up by device ID over DNS.

- Package: `packages.<system>.iroh-dns-server`, built from the iroh release pinned in
  `flake.lock`.
- NixOS module: `nixosModules.dns` (`services.shoal-dns`); role: `nixosModules.role-dns`.
- Ports: UDP and TCP 53 (DNS), TCP 80 and 443 (pkarr publishing, ACME).
- The zone (`services.shoal-dns.origin`) must be delegated to this host with NS records at
  the parent domain.

`shoald` does not yet take a custom address-lookup server; until it does, peers use this
server's records only through clients configured for it.
