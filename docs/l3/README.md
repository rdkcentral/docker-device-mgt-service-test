# RDK-61158 — L3 CRL / Cross-Signed / OCSP Test Infrastructure

This directory documents the **L3 certificate test infrastructure** added by
RDK-61158 (PR #153). It builds on the baseline TLS/mTLS harness and adds three
new PKI verification scenarios to the `mock-xconf` container:

1. **CRL enforcement over mTLS** — live certificate revocation.
2. **Cross-signed (bridge) PKI** — trust-anchor migration via a bridge cert.
3. **OCSP stapling** — server-stapled revocation status (RFC 6066).

> Scope: This documents **the changes introduced by RDK-61158** on top of the
> existing certificate infrastructure. For the baseline (server PKI, client PKI,
> the seed cert, mutual TLS, PKCS#11, and the shared-volume handoff), see the
> baseline certificate docs under [../architecture/overview.md](../architecture/overview.md).
> All L3 behavior is gated on the `ENABLE_CRL_L3=true` environment variable and
> is otherwise inert.

## Contents

| Page | What it covers |
|------|----------------|
| [crl-mtls.md](crl-mtls.md) | The CRL mTLS server (50061), the CRL control endpoint (50062), and live revocation |
| [cross-signed-pki.md](cross-signed-pki.md) | The cross-signed bridge PKI and the valid / no-bridge / expired-bridge scenarios |
| [ocsp-stapling.md](ocsp-stapling.md) | The OCSP responder (50063) and the OCSP stapling server (50064) |
| [integration.md](integration.md) | Compose ports, entrypoint startup order, the producer/consumer `certs.sh` L3 blocks, and the test wiring |

## What changed in PR #153

| Area | Change |
|------|--------|
| `rdk-cert-config` version | Both Dockerfiles pinned to tag **1.0.6** (adds `generate_crl_test_certs.sh` and `generate_cross_signed_test_certs.sh`) |
| New mock servers | `crl-mtls-server.js`, `crl-control.js`, `ocsp-stapling-server.js` |
| Producer PKI | `mock-xconf/certs.sh` generates CRL, OCSP, and cross-signed PKI when `ENABLE_CRL_L3=true` |
| Consumer pickup | `native-platform/certs.sh` waits for, copies, and trusts the L3 client assets |
| Startup | `mock-xconf/entrypoint.sh` launches the CRL mTLS, CRL control, OCSP responder, and OCSP stapling servers |
| Ports | 50061 / 50062 published; 50063 / 50064 internal-only |
| Tests | `test_docker.py` asserts the extra ports and Node process count when `ENABLE_CRL_L3=true` |

## Key Concepts

- **`ENABLE_CRL_L3` toggle.** Every L3 code path — PKI generation, server startup,
  client pickup, and test assertions — is gated on this single environment
  variable, so the baseline behavior is unaffected when it is unset.
- **Single-process CRL reload.** `crl-mtls-server.js` and `crl-control.js` run in
  one Node.js process so a revocation can hot-reload the TLS context via
  `setSecureContext()` with no restart and no IPC.
- **Readiness sentinels.** `native-platform` waits on `crl-client/crl-client.p12`
  and on `xs-client/NewRoot.pem` (written last) before copying the L3 assets.
- **Positive + negative pairs.** Each capability ships with a passing and a
  failing scenario (e.g. valid vs. revoked, bridge vs. no-bridge, staple present
  vs. absent) so a green result cannot be a false positive.

See [crl-mtls.md](crl-mtls.md) to start.
