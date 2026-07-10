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
 * CRL Control Server (L3)
 *
 * Plain HTTP server on port 50062 — no TLS is used because this endpoint only
 * carries test-control traffic (revoke/reset). Note: compose.yaml publishes
 * 50062 to the host for local debugging, so do not rely on network isolation
 * as a security boundary; the path-validation checks below are what protect it.
 *
 * Endpoints:
 *   POST /crl/revoke  body: {"certFile":"<absolute-path-inside-container>"}
 *       Revokes the named certificate against Test-CRL-ICA using openssl ca,
 *       regenerates the CRL, and hot-reloads the mTLS server context so new
 *       connections immediately see the updated CRL.
 *
 *       Revocation is permanent for the lifetime of the container (matching
 *       real-world CRL semantics); there is no reset endpoint.
 *
 * Security notes:
 *   - certFile paths are validated to lie within the expected PKI directory
 *     (/etc/pki/test-crl/) to prevent path-traversal abuse.
 *   - openssl is invoked via execFileSync with an array (no shell expansion).
 *   - Private key paths and pass-phrases never appear in response bodies or
 *     console.log output.
 */

'use strict';

const http           = require('node:http');
const path           = require('node:path');
const { execFileSync } = require('node:child_process');

const PORT     = 50062;
const ICA_CNF  = '/etc/pki/test-crl/Test-CRL-Root/Test-CRL-ICA/openssl.cnf';
const CRL_FILE = '/etc/xconf/certs/crl/Test-CRL-ICA.crl.pem';

// Allowed base directory for certFile path validation
const CERT_BASE = '/etc/pki/test-crl/';

// The HTTPS mTLS server; loaded after this module so require() returns the
// already-created export (no circular-dependency issue at runtime).
const crlMtlsServer = require('./crl-mtls-server');

// ─── Busy flag ────────────────────────────────────────────────────────────────
// Node.js is single-threaded; this flag serialises CRL operations so a fast
// retry from the test driver cannot race a still-running openssl invocation.
let busy = false;

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Validate that certFile is a normalised path within CERT_BASE.
 * Returns true if safe, false if the path escapes the allowed directory.
 */
function isAllowedCertPath(certFile) {
  if (typeof certFile !== 'string' || certFile.length === 0 || certFile.includes('\0')) return false;
  try {
    const resolved = path.resolve(certFile);
    return resolved.startsWith(CERT_BASE);
  } catch {
    return false;
  }
}

/**
 * Regenerate the CRL into CRL_FILE using openssl ca -gencrl.
 * Throws on openssl error.
 */
function generateCrl() {
  execFileSync('openssl', [
    'ca',
    '-config', ICA_CNF,
    '-gencrl',
    '-out',    CRL_FILE,
    '-crldays', '365',
    '-batch',
  ], { stdio: 'pipe' });
}

/**
 * Reload the mTLS server TLS context with the freshly written CRL.
 */
function reloadServerContext() {
  const opts = crlMtlsServer.buildTlsOptions();
  crlMtlsServer.server.setSecureContext(opts);
  console.log('[crl-control] mTLS server context reloaded');
}

// ─── Request handler helpers ─────────────────────────────────────────────────

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end',  ()    => resolve(body));
    req.on('error', reject);
  });
}

function jsonOk(res, payload) {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(payload));
}

function jsonErr(res, status, message) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: message }));
}

// ─── HTTP server ─────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {

  // ── POST /crl/revoke ────────────────────────────────────────────────────────
  if (req.method === 'POST' && req.url === '/crl/revoke') {
    if (busy) {
      return jsonErr(res, 503, 'busy');
    }
    busy = true;
    try {
      const body   = await readBody(req);
      let parsed;
      try {
        parsed = JSON.parse(body);
      } catch (_) {
        return jsonErr(res, 400, 'invalid JSON body');
      }
      const { certFile } = parsed;

      if (!isAllowedCertPath(certFile)) {
        return jsonErr(res, 400, 'certFile path not allowed');
      }

      // Revoke the certificate in the CA database
      execFileSync('openssl', [
        'ca',
        '-config',  ICA_CNF,
        '-revoke',  certFile,
        '-crl_reason', 'keyCompromise',
        '-batch',
      ], { stdio: 'pipe' });

      // Regenerate CRL to include the newly revoked entry
      generateCrl();
      reloadServerContext();

      console.log('[crl-control] /crl/revoke: certificate revoked and CRL reloaded');
      jsonOk(res, { status: 'revoked' });
    } catch (err) {
      console.error('[crl-control] /crl/revoke error:', err.message);
      jsonErr(res, 500, 'revoke failed');
    } finally {
      busy = false;
    }
    return;
  }

  // ── POST /crl/revoke handled above; revocation is permanent (no reset). ──

  res.writeHead(404);
  res.end();
});

server.listen(PORT, () => {
  console.log(`[crl-control] CRL control server listening on port ${PORT}`);
});
