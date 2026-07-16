# OCSP Stapling

> Applies when `ENABLE_CRL_L3=true`.

OCSP stapling lets the **server** attach ("staple") a signed, time-stamped OCSP
response to its TLS handshake, so the client learns the certificate's revocation
status without contacting the OCSP responder itself. This scenario proves the
server staples a valid `good` response, and that a client requiring a staple is
rejected when connecting to a server that does not staple.

Two processes cooperate, both started by `mock-xconf/entrypoint.sh`:

| Process | Port | Role |
|---------|------|------|
| `openssl ocsp` responder | 50063 | Answers OCSP queries from the CRL-ICA index (internal, IPv4-only) |
| `ocsp-stapling-server.js` | 50064 | One-way TLS server that fetches, caches, and staples the OCSP response |

Source: [../../mock-xconf/ocsp-stapling-server.js](../../mock-xconf/ocsp-stapling-server.js).

## How it works

```mermaid
sequenceDiagram
    participant Client as native-platform (curl --cert-status)
    participant Staple as ocsp-stapling-server.js (50064)
    participant Resp as openssl ocsp (127.0.0.1:50063)

    Note over Staple: on startup, pre-warm cache
    Staple->>Resp: openssl ocsp -issuer ICA -cert server -url .../50063
    Resp-->>Staple: DER OCSP response (status: good)
    Client->>Staple: ClientHello + status_request
    Staple-->>Client: ServerHello + cert + stapled OCSP response
    Client->>Client: verify staple -> "SSL certificate status: good"
```

- **One-way TLS.** The stapling server sets `requestCert: false` — it tests the
  server→client direction (stapling), not mTLS.
- **Internal responder address.** The stapling server queries the responder at
  `http://127.0.0.1:50063`, because the container hostname `mockxconf` only
  resolves from *other* containers, not from within `mock-xconf` itself.
- **Cache and refresh.** The DER response is cached and refreshed every
  **30 minutes** (`REFRESH_INTERVAL_MS`), per the architecture owner's spec. The
  cache is warmed synchronously at `listen()` so the first client does not pay a
  cold-fetch delay; the `OCSPRequest` handler serves the cached value.
- **Staple regardless of status.** `openssl ocsp -respout` emits a valid DER
  response for `good`/`revoked`/`unknown` alike; the server staples whatever it
  gets and logs the parsed status, so negative cases still receive a staple.

## Startup ordering

The responder (50063) must be listening before the stapling server warms its
cache, so `entrypoint.sh` starts `openssl ocsp` first, pauses briefly, then
launches `ocsp-stapling-server.js`. If the OCSP PKI files are missing, both
OCSP servers are skipped with a warning (the rest of L3 still runs).

## Why ports 50063 / 50064 are internal-only

- **50063** (`openssl ocsp`) binds IPv4-only and is queried from `127.0.0.1`
  inside the container — it is never published and never appears in
  `/proc/net/tcp6`.
- **50064** is reached container-to-container over the Docker network by the
  test client, so it does not need a host publish either.

Both remain `EXPOSE`d in the Dockerfile for documentation only.

## Verification

Asserted by two tests in
`rdk-cert-config`'s `test/functional-tests/tests/test_l3_crl_xsign.py`:

| Test | l3testapp scenario | Connects to | Expected |
|------|--------------------|-------------|----------|
| `test_l3_ocsp_staple_present` | 5 | 50064 (stapling) with `SSL_VERIFYSTATUS=1` | `CURLE_OK` — a valid `good` staple was returned |
| `test_l3_ocsp_staple_absent_rejected` | 6 | 50061 (CRL mTLS, no stapling) with `SSL_VERIFYSTATUS=1` | `CURLE_SSL_INVALIDCERTSTATUS` — no staple |

Scenario 6 is the negative control that proves scenario 5 is meaningful and not
a false positive.

Manual check from inside `native-platform`:

```sh
curl --cert-status -sv https://mockxconf:50064/health
# TLS trace contains: SSL certificate status: good
```

## Failure modes

| Symptom | Likely cause |
|---------|--------------|
| Cache not warmed at startup | Responder (50063) not up yet — the server retries on first request |
| `openssl ocsp error` in logs | Responder unreachable, or OCSP PKI files missing under `/etc/xconf/certs/ocsp/` |
| Scenario 5 fails with invalid status | Staple missing/stale; check the responder and the AIA URL |

## See Also

- [CRL mTLS Server](crl-mtls.md) — the non-stapling server used as the negative control
- [L3 Integration](integration.md) — startup order and port wiring
