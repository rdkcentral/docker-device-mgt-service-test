# Certificate Subsystem

## Overview

The harness establishes a mutual-TLS (mTLS) trust relationship between two
containers using a test PKI generated at runtime. Certificates are **not baked
into the images** — they are generated on container start and exchanged through
a **shared Docker volume**. This lets the same images run with or without mTLS,
and with or without hardware-backed keys (PKCS#11 / SoftHSM).

Two containers participate:

| Container         | Role              | Cert responsibilities |
| ----------------- | ----------------- | --------------------- |
| **mock-xconf**    | Server / cloud    | Generates the server PKI (root + server ICA + server leaf), a short-lived **seed certificate** for xPKI (RDK-61060), runs the **xPKI certifier** service, and (under mTLS) trusts the client CA chain. |
| **native-platform** | Device / client | Imports the server root CA into its system trust store, generates the **client PKI** (client ICA + client leaf), optionally routes the client key through **PKCS#11/SoftHSM**, writes a **CertSelector** config, and exports its CA chain to the server. |

All certificate generation is delegated to the
[rdk-cert-config](https://github.com/rdkcentral/rdk-cert-config) helper scripts
(`generate_test_rdk_certs.sh`, `create_leaf_cert.sh`) installed into the images.

## Key components

| File | Container | Role |
| ---- | --------- | ---- |
| `mock-xconf/certs.sh` | mock-xconf | Generates server PKI + seed cert; exports CAs; waits for and imports the client chain under mTLS. |
| `mock-xconf/xpki-certifier.js` | mock-xconf | HTTPS service on port 50055 that signs CSRs with the server ICA. |
| `mock-xconf/entrypoint.sh` | mock-xconf | Runs `certs.sh`, then starts the mock services (including xPKI certifier). |
| `native-platform/certs.sh` | native-platform | Imports server CA; generates client PKI; optional PKCS#11; writes CertSelector cfg; exports client chain. |
| `native-platform/entrypoint.sh` | native-platform | Runs `certs.sh` (aborts on failure), then starts RFC provider / tr69hostif. |
| `compose.yaml` | — | Wires services, ports, the shared volume, and `ENABLE_MTLS`. |

## The shared volume

Every container mounts the workspace root at
`/mnt/L2_CONTAINER_SHARED_VOLUME`. The PKI exchange happens under:

```
/mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/
├── server/     # written by mock-xconf, consumed by native-platform
└── client/     # client chain written by native-platform; seed cert written by mock-xconf
```

See the [Shared-Volume Contract](shared-volume-contract.md) for the exact
producer/consumer/cleanup rules.

## Enabling mTLS

mTLS is controlled by the `ENABLE_MTLS` environment variable (default `false`).
In [compose.yaml](../../compose.yaml) both services set `ENABLE_MTLS=true`.
Optionally, `ENABLE_PKCS11=true` routes the client key through a SoftHSM token.

See the [Configuration Reference](configuration.md) for all toggles.

## See Also

- [Architecture](architecture.md)
- [Certificate Lifecycle](certificate-lifecycle.md)
- [Shared-Volume Contract](shared-volume-contract.md)
- [Configuration Reference](configuration.md)
- [PKCS#11 / SoftHSM](pkcs11.md)
- [xPKI Certifier Service](xpki-certifier.md)
- [Troubleshooting](troubleshooting.md)
