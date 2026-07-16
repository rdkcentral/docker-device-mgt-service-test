# docker-device-mgt-service-test — Certificate Infrastructure Documentation

This directory documents the **certificate / TLS test infrastructure** used by
the `docker-device-mgt-service-test` environment: how the `mock-xconf` and
`native-platform` containers generate, exchange, and install PKI material to
exercise TLS and mutual-TLS (mTLS) code paths on RDK devices.

> Scope: This documents the **existing (baseline) certificate infrastructure**
> — server PKI, client PKI, the seed certificate, mutual TLS, the optional
> PKCS#11 path, and the shared-volume handoff between the two containers.

## Contents

| Page | What it covers |
|------|----------------|
| [architecture/overview.md](architecture/overview.md) | The two-container test harness and the end-to-end cert-exchange flow |
| [architecture/pki-hierarchy.md](architecture/pki-hierarchy.md) | The CA hierarchies (server ICA, client ICA) and the seed certificate |
| [certs/mock-xconf-certs.md](certs/mock-xconf-certs.md) | Walkthrough of `mock-xconf/certs.sh` (the producer) |
| [certs/native-platform-certs.md](certs/native-platform-certs.md) | Walkthrough of `native-platform/certs.sh` (the consumer) |
| [certs/mtls.md](certs/mtls.md) | The mutual-TLS setup, trust flow, and verification |
| [integration/compose-and-ports.md](integration/compose-and-ports.md) | Environment toggles, published ports, and how to run locally |

## Key Concepts

- **Producer / Consumer.** `mock-xconf` acts as the certificate authority and
  server; `native-platform` acts as the RDK client. They never call each other's
  cert scripts — they exchange files over a bind-mounted shared volume.
- **Shared volume.** The parent directory is mounted into both containers at
  `/mnt/L2_CONTAINER_SHARED_VOLUME`. PKI is exchanged under
  `.../shared_certs/`.
- **Readiness sentinels.** Because both containers start concurrently, each side
  waits (`while [ ! -f ... ]`) for a specific file to appear before proceeding.
- **Environment toggles.** `ENABLE_MTLS` turns on the mutual-TLS trust exchange;
  `ENABLE_PKCS11` adds a hardware-token-backed client cert path.

See [architecture/overview.md](architecture/overview.md) to start.
