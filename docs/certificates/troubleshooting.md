# Troubleshooting

Common failure modes in the certificate subsystem, with symptoms, causes, and
fixes. Log lines from the cert scripts are prefixed `[certs]`; the xPKI service
uses `[xpki-certifier]`.

## A container hangs on startup

**Symptom:** repeated `[certs] Waiting for server root CA...` (native-platform)
or `[certs] Waiting for client certificates...` (mock-xconf), and the container
never finishes starting.

**Cause:** The file-based handshake wait-loops have **no timeout**. One side is
waiting for a shared-volume file the other side never produced — usually because
the peer container was not started, or crashed before writing its file.

**Fix:**
- Always bring both up together: `docker compose up -d`.
- Check the peer's logs for an earlier fatal error (a non-empty artifact check
  failing → exit 1 → no file written).
- Confirm the shared volume is mounted in both (`../:/mnt/L2_CONTAINER_SHARED_VOLUME`).

## "Expected certificate artifact missing or empty"

**Symptom:** `[certs] ERROR: Expected ... artifact missing or empty: <path>` and
the container exits non-zero.

**Cause:** An rdk-cert-config generation step (`generate_test_rdk_certs.sh` /
`create_leaf_cert.sh`) did not produce the expected file.

**Fix:**
- Verify the rdk-cert-config install in the image (scripts present under
  `/etc/pki/scripts` / `/usr/local`).
- Confirm the rdk-cert-config ref cloned by the image is correct (see
  [configuration.md](configuration.md#rdk-cert-config-dependency)).
- Rebuild the image `--no-cache` if the clone layer is stale.

## native-platform skips CA import

**Symptom:** `[certs] mock-xconf not resolvable (mockxconf); skipping server CA import`.

**Cause:** The DNS gate `getent ahosts mockxconf` failed — the mock-xconf
service name did not resolve on the Docker network.

**Fix:**
- Ensure both services are on the same compose network and mock-xconf is up.
- If you renamed the service/host, set `MOCKXCONF_HOST` accordingly.

## update-ca-certificates not found

**Symptom:** `[certs] ERROR: /usr/sbin/update-ca-certificates not found or not executable`.

**Cause:** The `ca-certificates` package is missing/broken in the image.

**Fix:** Rebuild the native-platform image; ensure `ca-certificates` is installed.

## PKCS#11 setup fails

**Symptom:** `[certs] ERROR: PKCS#11 OpenSSL setup failed...` or
`[certs] ERROR: PKCS#11 setup failed with exit code N`.

**Cause:** `setup-pkcs11-openssl.sh` or `setup-pkcs11.sh` returned non-zero.

**Fix:**
- Confirm the scripts and `softhsm2.conf` were installed from rdk-cert-config
  (see [pkcs11.md](pkcs11.md)).
- Delete the sentinel `/usr/local/openssl-pkcs11-ready` to force a clean re-run.
- Only enable PKCS#11 with `ENABLE_MTLS=true`.

## xPKI: "Certificate not found for renewal" (404)

**Symptom:** A renewal POST to `/v1/certifier/renew` returns 404.

**Cause:** The `certificateId` is not in the service cache — either the cert was
never issued by this instance, the cache was `reset`, or the id hash algorithm
does not match.

**Fix:**
- Issue the certificate first, then renew using the returned `certificateId`.
- The id must be the **SHA-1** hash of the DER cert (matches libcertifier). Do
  not switch to SHA-256 unilaterally — see the note in
  [xpki-certifier.md](xpki-certifier.md#renewal-request).

## xPKI: "Invalid CSR signature" (400)

**Symptom:** Issuance returns 400 with an "Invalid CSR signature" hint.

**Cause:** `openssl req -verify` failed on the submitted CSR — commonly a
PKCS#11 key-access problem, wrong signing key, or a corrupted CSR.

**Fix:**
- Verify the CSR was signed with the matching private key.
- If using PKCS#11, confirm the token is initialized and the key is accessible.

## xPKI: port 50055 already in use

**Symptom:** `[xpki-certifier] Port 50055 is already in use!` then exit 1.

**Cause:** A previous mock-xconf container still holds the port (common on
Windows hosts after `down`).

**Fix:** `docker rm -f mockxconf`, wait a few seconds, then re-`up`.

## Re-running the handshake

Because consumers **delete** the exchanged CA files from the shared volume after
import, a partial re-run can leave the volume without the expected files. The
clean path is to recreate the containers so producers regenerate everything:

```powershell
docker compose down
docker rm -f mockxconf 2>$null
docker compose up -d
```

## See Also

- [Certificate Lifecycle](certificate-lifecycle.md)
- [Shared-Volume Contract](shared-volume-contract.md)
- [Configuration Reference](configuration.md)
- [PKCS#11 / SoftHSM](pkcs11.md)
