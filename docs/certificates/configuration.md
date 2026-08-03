# Configuration Reference

This reference lists the environment variables, ports, on-disk paths, and config
files that govern the certificate subsystem. Values are drawn from
[compose.yaml](../../compose.yaml),
[mock-xconf/certs.sh](../../mock-xconf/certs.sh),
[native-platform/certs.sh](../../native-platform/certs.sh), and
[mock-xconf/xpki-certifier.js](../../mock-xconf/xpki-certifier.js).

## Environment variables

| Variable | Default | Applies to | Effect |
| -------- | ------- | ---------- | ------ |
| `ENABLE_MTLS` | `false` | both containers | Enable client-cert generation and the bidirectional mTLS handshake. Set to `true` in `compose.yaml`. |
| `ENABLE_PKCS11` | `false` | native-platform | Route the client key through SoftHSM / PKCS#11. Only meaningful when `ENABLE_MTLS=true`. |
| `ENABLE_CRL_L3` | `false` | both containers | Generate the CRL / cross-signed / OCSP PKI, start the [CRL mTLS](crl-mtls.md), [cross-signed](cross-signed-pki.md), and [OCSP stapling](ocsp-stapling.md) servers, and make `native-platform` pick up and trust those client assets. Set to `true` in `compose.yaml`. |
| `CRL_L3_WAIT_TIMEOUT_SEC` | `120` | native-platform | Bounded wait for the `ENABLE_CRL_L3` shared-volume assets; a missing export fails fast instead of hanging. |
| `MOCKXCONF_HOST` | `mockxconf` | native-platform | Server hostname used for the DNS gate before importing the server CA. |
| `XPKI_ENABLE_REQUEST_LOG` | `true` | xpki-certifier | Capture request log (ring buffer). |
| `XPKI_MAX_LOG_ENTRIES` | `1000` | xpki-certifier | Cap on retained request-log entries. |
| `XPKI_DEBUG_CSR` | `false` | xpki-certifier | Log a CSR preview (may leak subject/SAN). |
| `XPKI_MAX_CACHE_SIZE` | `10000` | xpki-certifier | Renewal cache size (LRU eviction). |

## Ports (compose.yaml)

The mock-xconf service publishes several mock endpoints. The certificate-related
one is the xPKI certifier:

| Port | Service | mTLS | Notes |
| ---- | ------- | ---- | ----- |
| 50055 | xPKI certifier | **no** (by design) | CSR signing / renewal |
| 50050–50054, 50056–50060 | other mock-xconf endpoints | per service | non-cert mock services |
| 9090 | native-platform | — | device-side endpoint |

When `ENABLE_CRL_L3=true`, `mock-xconf` also runs:

| Port | Service | Published to host? | mTLS |
| ---- | ------- | ------------------ | ---- |
| 50061 | [CRL mTLS server](crl-mtls.md) (`crl-mtls-server.js`) | Yes | **yes** |
| 50062 | [CRL control endpoint](crl-mtls.md) (`crl-control.js`) | Yes — `127.0.0.1` only | no (HTTP) |
| 50063 | [OCSP responder](ocsp-stapling.md) (`openssl ocsp`) | No — internal, IPv4-only | — |
| 50064 | [OCSP stapling server](ocsp-stapling.md) (`ocsp-stapling-server.js`) | No — container-to-container | one-way |

## Certificate paths

### mock-xconf (server)

| Path | Contents |
| ---- | -------- |
| `/etc/pki/Test-RDK-root/certs/Test-RDK-root.pem` | Test root CA |
| `/etc/pki/Test-RDK-root/Test-RDK-server-ICA/certs/Test-RDK-server-ICA.pem` | Server ICA cert |
| `/etc/pki/Test-RDK-root/Test-RDK-server-ICA/private/Test-RDK-server-ICA.key` | Server ICA key (also used by xPKI certifier) |
| `/etc/xconf/certs/mock-xconf-server-cert.pem` | Server TLS cert |
| `/etc/xconf/certs/mock-xconf-server-key.pem` | Server TLS key (`chmod 600`) |
| `/etc/xconf/trust-store/ca-chain.pem` | Imported client chain + appended server ICA/root |

### native-platform (device)

| Path | Contents |
| ---- | -------- |
| `/etc/pki/Test-RDK-root/Test-RDK-client-ICA/certs/rdkclient.pem` | Client leaf cert |
| `/etc/pki/Test-RDK-root/Test-RDK-client-ICA/private/rdkclient.key` | Client leaf key |
| `/opt/certs/client.p12` | Runtime client P12 |
| `/opt/certs/client.pem` | Runtime client cert+key (concatenated) |
| `/opt/certs/reference.p12` | PKCS#11 reference P12 (only if `ENABLE_PKCS11=true`) |
| `/usr/share/ca-certificates/mock-xconf-root-ca.pem` | Imported server root CA |
| `/etc/ssl/certsel/certsel.cfg` | CertSelector configuration |

### Shared volume

`/mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/` — see the
[Shared-Volume Contract](shared-volume-contract.md) for the full file table.

## CertSelector configuration

`native-platform/certs.sh` writes `/etc/ssl/certsel/certsel.cfg`. Each line maps
a usage to a credential source. The order matters — earlier entries take
precedence.

**With PKCS#11 (`ENABLE_PKCS11=true`)** — hardware-backed reference cert first:

```
MTLS|SRVR_TLS,REFERENCE_P12,P12,file:///opt/certs/reference.p12,cfgOpsCert
MTLS|SRVR_TLS,CLIENT_P12,P12,file:///opt/certs/client.p12,cfgOpsCert
MTLS_PEM,CLIENT_PEM,PEM,file:///opt/certs/client.pem,cfgOpsCert
```

**Without PKCS#11** — file-based P12 is primary:

```
MTLS|SRVR_TLS,CLIENT_P12,P12,file:///opt/certs/client.p12,cfgOpsCert
MTLS_PEM,CLIENT_PEM,PEM,file:///opt/certs/client.pem,cfgOpsCert
```

Field order per line: `usage|scope,label,format,uri,keyId`.

## rdk-cert-config dependency

The certificate scripts (`generate_test_rdk_certs.sh`, `create_leaf_cert.sh`,
PKCS#11 setup scripts) come from
[rdk-cert-config](https://github.com/rdkcentral/rdk-cert-config), cloned and
installed by both Dockerfiles. The two images currently reference the dependency
independently — see the `git clone` step in `mock-xconf/Dockerfile` and
`native-platform/Dockerfile` for the exact ref each uses.

## See Also

- [Shared-Volume Contract](shared-volume-contract.md)
- [PKCS#11 / SoftHSM](pkcs11.md)
- [xPKI Certifier Service](xpki-certifier.md)
- [Troubleshooting](troubleshooting.md)
