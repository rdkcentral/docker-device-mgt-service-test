# Compose, Ports & Environment Toggles

## Overview

This page documents how the two containers are wired together under Docker
Compose for the baseline cert infrastructure: the environment toggles that
control cert behavior and the ports the `mock-xconf` mocks listen on.

## Services

`compose.yaml` defines the two cert-relevant services (plus an `nmap-container`
used for scanning):

| Service | Container name | Role |
|---------|----------------|------|
| `mock-xconf` | `mockxconf` | Producer / CA / TLS server |
| `l2-container` | `native-platform` | Consumer / device client |

Both mount the repo parent as the shared volume:

```yaml
volumes:
  - ../:/mnt/L2_CONTAINER_SHARED_VOLUME
```

## Environment Toggles

| Variable | Applies to | Default | Effect |
|----------|-----------|---------|--------|
| `ENABLE_MTLS` | both | `false` | Turns on the mutual-TLS trust exchange: native-platform generates and exports its client CA chain; mock-xconf imports it. |
| `ENABLE_PKCS11` | native-platform | `false` | Adds a PKCS#11 hardware-token-backed client cert path (patched OpenSSL, reference P12, token provisioning). |
| `MOCKXCONF_HOST` | native-platform | `mockxconf` | Hostname used to decide whether to import the server CA (DNS guard). |

## Ports (mock-xconf)

The `mockxconf` service publishes the mock xconf endpoints to the host. Each is
served by a Node.js script started from `mock-xconf/entrypoint.sh`:

| Port | Service | Script |
|------|---------|--------|
| 50050 | XCONF DCM settings | `getT2DCMSettings.js` |
| 50051 | Data Lake mock | `data-lake-mock.js` |
| 50052 | XConf data | `getXconfData.js` |
| 50053 | RFC config | `rfcData.js` |
| 50054 | RRD file upload | `rrdFileupload.js` |
| 50055 | xPKI Certifier (RDK-61060) | `xpki-certifier.js` |
| 50056 | RDM data upload | `rdmFileupload.js` |
| 50057 | STB log upload — S3 presigned URL | `stbLogUpload.js` |
| 50058 | STB log upload — direct | `stbLogUpload.js` |
| 50059 | Crash metadata endpoint | `crashUpload.js` |
| 50060 | Crash S3 presigned URL | `crashUpload.js` |

All of these present the `mockxconf` server certificate (see
[Mutual TLS](../certs/mtls.md)); the client trusts them via the server CA chain
imported by `native-platform/certs.sh`.

## Running Locally

From the repo root (`docker-device-mgt-service-test/`):

```sh
# Baseline (one-way TLS only)
docker compose up -d

# With mutual TLS
ENABLE_MTLS=true docker compose up -d
```

Bring it down and clean the exchanged PKI:

```sh
docker compose down
rm -rf ../shared_certs/*
```

## Startup Order

Startup order is enforced inside the containers via readiness sentinels, not by
Compose `depends_on`:

1. `mock-xconf` runs `certs.sh`, writes `server/root_ca.pem`, then starts its
   mock servers.
2. `native-platform` waits for `server/root_ca.pem`, imports it, and (with mTLS)
   exports `client/ca-chain.pem`.
3. `mock-xconf` waits for `client/ca-chain.pem` before finishing its trust store.

See [Architecture Overview](../architecture/overview.md#startup--synchronization).

## See Also

- [Architecture Overview](../architecture/overview.md)
- [mock-xconf/certs.sh](../certs/mock-xconf-certs.md)
- [native-platform/certs.sh](../certs/native-platform-certs.md)
- [Mutual TLS](../certs/mtls.md)
