# xPKI Certifier Service

## Overview

`xpki-certifier.js` is a mock certificate-procurement service (RDK-61060) that
simulates the xPKI certificate-signing authority. It runs inside the
**mock-xconf** container, listens on **port 50055** over HTTPS, and signs
Certificate Signing Requests (CSRs) using the test server ICA. It lets the
harness exercise the device-side certificate-enrollment flow (obtain, then
renew, a device certificate) without a real xPKI backend.

Source: [mock-xconf/xpki-certifier.js](../../mock-xconf/xpki-certifier.js).

## Startup and dependencies

The service is started by `mock-xconf/entrypoint.sh` **after** `certs.sh` has
generated the PKI:

```sh
if [ -f /usr/local/bin/xpki-certifier.js ]; then
    node /usr/local/bin/xpki-certifier.js &
fi
```

On startup it:

1. Verifies its TLS server key/cert exist (reuses the mock-xconf server cert):
   - `/etc/xconf/certs/mock-xconf-server-key.pem`
   - `/etc/xconf/certs/mock-xconf-server-cert.pem`
2. Waits (up to 15 retries × 2 s) for the signing CA material produced by
   `certs.sh`:
   - `Test-RDK-server-ICA.key` / `Test-RDK-server-ICA.pem`
   - `Test-RDK-root.pem`
3. Creates the HTTPS server and listens on 50055.

> **Naming note.** Comments in the source refer to a `Test-RDK-xpki-ICA`
> hierarchy, but the constants actually point at `Test-RDK-server-ICA`. The
> service signs with the **server ICA** — there is no separate xPKI root in the
> current implementation.

## mTLS: intentionally disabled

This service **does not enforce mTLS**, by design:

> A client must obtain a certificate *before* it can present one for mTLS.
> Requiring client-cert auth on the procurement endpoint would deadlock
> enrollment. Other mock services still enforce mTLS.

This is a deliberate, documented exception to the harness's mTLS posture.

## Endpoints

| Method | Path | Purpose |
| ------ | ---- | ------- |
| POST | `/v1/certifier/certificate` | Sign a CSR (primary issuance endpoint) |
| POST | `/api/v1/device-cert` | Sign a CSR (seed-scope alias) |
| POST | `/v1/certifier/renew` | Renew a previously issued cert (by `certificateId`) |
| GET | `/health` | Health check → `{ status: "ok", ... }` |
| GET | `/admin/xpkiCertifier?action=...` | Test-control (unauthenticated) |

### Issuance request

Request body (JSON):

```json
{
  "csr": "-----BEGIN CERTIFICATE REQUEST-----\n...",
  "profile_name": "optional",
  "common_name": "optional",
  "serial_number": "optional",
  "validity_days": 1
}
```

Processing:

1. The CSR is accepted as PEM, or as bare base64 (headers are added
   automatically).
2. The CSR **signature is verified** (`openssl req -verify`) before signing;
   verification failure returns `400`.
3. `validity_days` is clamped to `[1, 3650]` (default 90 if unparseable; callers
   typically send 1).
4. The CSR is signed with the server ICA (`openssl x509 -req ... -sha256`) with a
   random 8-byte serial, `keyUsage=digitalSignature,keyEncipherment`,
   `extendedKeyUsage=clientAuth,serverAuth`.

Response:

```json
{
  "certificate": "-----BEGIN CERTIFICATE-----\n...",
  "certificateChain": "<leaf>\n<ICA>\n<root>",
  "status": "success"
}
```

### Renewal request

Send `certificateId` (and no `csr`). The service looks up the cached CSR for
that id and re-signs it, preserving the original public key.

```json
{ "certificateId": "<sha1-hex>", "validity_days": 1 }
```

- `certificateId` is the **SHA-1** hash of the DER-encoded issued cert. SHA-1 is
  used deliberately to match libcertifier's `certificateId`; it is a cache
  lookup key only, not a security control. Changing it would break renewal.
- If the id is not in cache, the service returns `404`.

### Admin / test-control endpoint

`GET /admin/xpkiCertifier?action=<action>`:

| action | effect |
| ------ | ------ |
| `reset` | Clear request log, error mode, request count, and cert cache |
| `setError&mode=<m>` | Inject an error: `csr_invalid` (400), `rate_limit` (429), `server_error` (500) |
| `getLog` | Return the captured request log and count |

> **Security.** Admin endpoints are unauthenticated and exist only for test
> orchestration. This is acceptable for a mock service, never for production.

## Runtime configuration

| Variable | Default | Effect |
| -------- | ------- | ------ |
| `XPKI_ENABLE_REQUEST_LOG` | `true` | Capture request log (ring buffer) |
| `XPKI_MAX_LOG_ENTRIES` | `1000` | Request-log cap |
| `XPKI_DEBUG_CSR` | `false` | Log CSR preview (may leak subject/SAN) |
| `XPKI_MAX_CACHE_SIZE` | `10000` | Renewal cache size (LRU eviction) |

## Error handling

- Invalid JSON body → `400`.
- Missing `csr` (on issuance) → `400`.
- CSR signature verification failure → `400` with a PKCS#11 troubleshooting hint.
- Body larger than 10 MB → `413` (guards against memory exhaustion).
- Missing signing CA after retries → process exits `1` (fatal).
- `EADDRINUSE` on 50055 → process exits `1`.

## Health check example

```bash
docker exec mockxconf curl -sk https://mockxconf:50055/health
# {"status":"ok","service":"xpki-certifier","port":50055}
```

## See Also

- [Architecture](architecture.md)
- [Certificate Lifecycle](certificate-lifecycle.md) — where the seed cert is produced
- [Configuration Reference](configuration.md)
