/*
 * If not stated otherwise in this file or this component's LICENSE file the
 * following copyright and licenses apply:
 *
 * Copyright 2025 RDK Management
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/

/**
 * OCSP Stapling Server (L3)
 *
 * Listens on port 50064 with one-way TLS (server presents cert; no client
 * cert required).  The server cert is signed by Test-CRL-ICA and carries an
 * AIA extension pointing to the OCSP responder at http://mockxconf:50063.
 *
 * On each new TLS connection that requests OCSP stapling (RFC 6066
 * status_request), the server:
 *   1. Queries the openssl ocsp daemon at http://mockxconf:50063
 *   2. Returns the DER-encoded OCSP response, stapling it into the handshake
 *
 * The OCSP response is cached for REFRESH_INTERVAL_MS and refreshed
 * periodically so the staple does not grow stale.  On first request the
 * cache is populated synchronously; subsequent requests return the cached
 * value.
 *
 * Test flow:
 *   curl --cert-status -vv https://mockxconf:50064/health
 *   → TLS trace contains "SSL certificate status: good"
 *
 * Architecture owner spec:
 *   "Server should request the ICA to sign OCSP for every 30 mins."
 *   → REFRESH_INTERVAL_MS = 30 * 60 * 1000
 */

'use strict';

const https       = require('node:https');
const http        = require('node:http');
const fs          = require('node:fs');
const { execFile } = require('node:child_process');

// ─── Configuration ────────────────────────────────────────────────────────────

const PORT = 50064;

// OCSP responder address (openssl ocsp daemon started by entrypoint.sh).
// Use 127.0.0.1 (not the container name) because this fetch originates from
// WITHIN the mockxconf container — the container hostname 'mockxconf' only
// resolves from OTHER containers via Docker DNS / --link, not from itself.
const OCSP_RESPONDER_URL = 'http://127.0.0.1:50063';

// How often (ms) to pro-actively refresh the stapled OCSP response
// 30 minutes as specified by the architecture owner
const REFRESH_INTERVAL_MS = 30 * 60 * 1000;

// TLS material for the stapling server (created by certs.sh OCSP block)
const SERVER_KEY  = '/etc/xconf/certs/ocsp/ocsp-server.key';
const SERVER_CERT = '/etc/xconf/certs/ocsp/ocsp-server.pem';
const ICA_CERT    = '/etc/xconf/certs/ocsp/Test-CRL-ICA.pem';
const ROOT_CERT   = '/etc/xconf/certs/ocsp/Test-CRL-Root.pem';
// Responder cert — needed for `openssl ocsp -issuer ... -VAfile`
const OCSP_RESPONDER_CERT = '/etc/xconf/certs/ocsp/ocsp-responder.pem';
// CA chain file used by openssl ocsp -CAfile
const CA_CHAIN    = '/etc/xconf/certs/ocsp/ocsp-ca-chain.pem';

// ─── Startup diagnostics ──────────────────────────────────────────────────────

console.log('[ocsp-stapling-server] ==========================================');
console.log('[ocsp-stapling-server] OCSP Stapling Server starting');
console.log('[ocsp-stapling-server] ==========================================');
console.log(`[ocsp-stapling-server] Node.js ${process.version}  PID ${process.pid}`);
console.log(`[ocsp-stapling-server] Target port: ${PORT}`);
console.log(`[ocsp-stapling-server] OCSP responder: ${OCSP_RESPONDER_URL}`);

for (const f of [SERVER_KEY, SERVER_CERT, ICA_CERT, ROOT_CERT, OCSP_RESPONDER_CERT, CA_CHAIN]) {
  const ok = fs.existsSync(f);
  console.log(`[ocsp-stapling-server]   ${ok ? '✓' : '✗'} ${f}`);
  if (!ok) {
    console.error(`[ocsp-stapling-server] FATAL: required file missing: ${f}`);
    process.exit(1);
  }
}

// ─── OCSP response cache ──────────────────────────────────────────────────────

let cachedOcspResponse = null;   // Buffer (DER-encoded) or null
let lastRefreshTime    = 0;

/**
 * Fetch a fresh OCSP response from the openssl ocsp daemon.
 *
 * Uses `openssl ocsp` CLI to query the responder.  The response is returned
 * as a Buffer in DER format suitable for the TLS staple callback.
 *
 * @returns {Promise<Buffer|null>}  DER-encoded OCSP response, or null on error.
 */
function fetchOcspResponse() {
  return new Promise((resolve) => {
    const derFile = `/tmp/ocsp-staple-${Date.now()}.der`;
    // openssl ocsp arguments:
    //   -issuer      the issuer cert that signed the server cert
    //   -cert        the server cert whose status we want
    //   -url         the OCSP responder URL
    //   -CAfile      trusted CA chain to verify the responder response
    //   -VAfile      cert used to verify the OCSP response signature
    //   -respout     write DER-encoded response to this file
    //   -noverify    skip response signature check in test env (self-signed responder)
    const args = [
      'ocsp',
      '-issuer',    ICA_CERT,
      '-cert',      SERVER_CERT,
      '-url',       OCSP_RESPONDER_URL,
      '-CAfile',    CA_CHAIN,
      '-VAfile',    OCSP_RESPONDER_CERT,
      '-respout',   derFile,
      '-noverify',
      '-timeout',   '5',
    ];

    execFile('openssl', args, { timeout: 8000 }, (err, stdout, stderr) => {
      if (err) {
        console.error(`[ocsp-stapling-server] openssl ocsp error: ${err.message}`);
        console.error(`[ocsp-stapling-server] stderr: ${stderr}`);
        resolve(null);
        return;
      }
      // stdout contains "Response verify OK" and "ocsp-server.pem: good" on success
      if (stdout.includes(': good') || stdout.includes('Response verify OK')) {
        try {
          const der = fs.readFileSync(derFile);
          fs.unlinkSync(derFile);
          console.log(`[ocsp-stapling-server] OCSP response fetched (${der.length} bytes, status: good)`);
          resolve(der);
        } catch (e) {
          console.error(`[ocsp-stapling-server] Failed to read OCSP DER file: ${e.message}`);
          resolve(null);
        }
      } else {
        console.error(`[ocsp-stapling-server] Unexpected OCSP output: ${stdout}`);
        // Clean up temp file if it exists
        try { fs.unlinkSync(derFile); } catch (_) {}
        resolve(null);
      }
    });
  });
}

/**
 * Refresh the cached OCSP response.  Idempotent — safe to call at any time.
 */
async function refreshCache() {
  const response = await fetchOcspResponse();
  if (response) {
    cachedOcspResponse = response;
    lastRefreshTime    = Date.now();
  }
}

// ─── HTTPS server ─────────────────────────────────────────────────────────────

const tlsOptions = {
  key:  fs.readFileSync(SERVER_KEY),
  cert: fs.readFileSync(SERVER_CERT),
  ca:   [fs.readFileSync(ICA_CERT), fs.readFileSync(ROOT_CERT)],
  // One-way TLS: do NOT request a client cert on this server.
  // The purpose is to test OCSP stapling (server → client direction), not mTLS.
  requestCert:        false,
  rejectUnauthorized: false,
};

const server = https.createServer(tlsOptions, (req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', ocsp: 'stapling-enabled' }));
    return;
  }
  res.writeHead(404);
  res.end();
});

// ─── OCSPRequest handler ──────────────────────────────────────────────────────
//
// This event fires for every TLS client that sends a `status_request`
// extension in its ClientHello (i.e. `curl --cert-status`).
//
// The handler returns the cached DER OCSP response.  If the cache is empty
// (first request after startup) it fetches synchronously first.
//
server.on('OCSPRequest', (cert, issuer, callback) => {
  if (cachedOcspResponse) {
    callback(null, cachedOcspResponse);
    return;
  }
  // Cache is cold — fetch synchronously before the handshake times out
  fetchOcspResponse().then((response) => {
    if (response) {
      cachedOcspResponse = response;
      lastRefreshTime    = Date.now();
    }
    // Pass null if we could not fetch — the handshake proceeds without a staple
    callback(null, response || null);
  });
});

server.on('tlsClientError', (err) => {
  console.error(`[ocsp-stapling-server] tlsClientError: ${err.code} ${err.message}`);
});

// ─── Periodic OCSP refresh (every 30 minutes) ─────────────────────────────────
//
// Architecture owner spec: "Server should request the ICA to sign OCSP for
// every 30 mins."  We use setInterval with unref() so the timer does not
// prevent the process from exiting cleanly in tests.
//
const refreshTimer = setInterval(() => {
  console.log('[ocsp-stapling-server] Periodic OCSP cache refresh...');
  refreshCache();
}, REFRESH_INTERVAL_MS);
refreshTimer.unref();

// ─── Start ────────────────────────────────────────────────────────────────────

server.listen(PORT, async () => {
  console.log(`[ocsp-stapling-server] Listening on port ${PORT}  (OCSP stapling enabled)`);
  // Pre-warm the cache so the first client request does not cause a cold-fetch
  // delay inside the OCSPRequest handler.
  await refreshCache();
  if (cachedOcspResponse) {
    console.log('[ocsp-stapling-server] OCSP response cache warmed successfully');
  } else {
    console.warn('[ocsp-stapling-server] WARNING: Could not pre-warm OCSP cache — ' +
                 'OCSP responder may not be ready yet; will retry on first request');
  }
});
