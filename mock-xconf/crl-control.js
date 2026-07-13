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
const fs             = require('node:fs');
const { execFileSync } = require('node:child_process');

// openssl invocations are bounded so a stuck process cannot wedge the server.
const OPENSSL_TIMEOUT_MS = 15000;
const OPENSSL_MAXBUFFER  = 1024 * 1024;
// Cap the request body; this endpoint only receives a tiny JSON payload.
const MAX_BODY_BYTES     = 64 * 1024;

const PORT     = 50062;
const ICA_CNF  = '/etc/pki/test-crl/Test-CRL-Root/Test-CRL-ICA/openssl.cnf';
const CRL_FILE = '/etc/xconf/certs/crl/Test-CRL-ICA.crl.pem';

// Allowed base directory for certFile path validation
const CERT_BASE = '/etc/pki/test-crl/';

// The HTTPS mTLS server module that loaded this file. This is a circular
// require (crl-mtls-server -> crl-control -> crl-mtls-server), but it is safe
// because crl-mtls-server assigns its exports before requiring crl-control.
const crlMtlsServer = require('./crl-mtls-server');

// ─── Busy flag ────────────────────────────────────────────────────────────────
// Node.js is single-threaded; this flag serialises CRL operations so a fast
// retry from the test driver cannot race a still-running openssl invocation.
let busy = false;

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Validate that certFile is a real, regular file within CERT_BASE.
 * Rejects symlinks and any path whose resolved real path escapes CERT_BASE,
 * so a symlink planted under the PKI dir cannot redirect openssl elsewhere.
 * Returns true if safe, false otherwise.
 */
function isAllowedCertPath(certFile) {
  if (typeof certFile !== 'string' || certFile.length === 0 || certFile.includes('\0')) return false;
  if (!path.isAbsolute(certFile)) return false;
  try {
    if (fs.lstatSync(certFile).isSymbolicLink()) return false;
    const real = fs.realpathSync(certFile);
    const base = fs.realpathSync(CERT_BASE);
    const basePrefix = base.endsWith(path.sep) ? base : base + path.sep;
    return real.startsWith(basePrefix) && fs.statSync(real).isFile();
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
  ], { stdio: 'pipe', timeout: OPENSSL_TIMEOUT_MS, maxBuffer: OPENSSL_MAXBUFFER });
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
    let size = 0;
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      size += Buffer.byteLength(chunk);
      if (size > MAX_BODY_BYTES) {
        const err = new Error('request body too large');
        err.code = 'PAYLOAD_TOO_LARGE';
        req.destroy();
        reject(err);
        return;
      }
      body += chunk;
    });
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
      ], { stdio: 'pipe', timeout: OPENSSL_TIMEOUT_MS, maxBuffer: OPENSSL_MAXBUFFER });

      // Regenerate CRL to include the newly revoked entry
      generateCrl();
      reloadServerContext();

      console.log('[crl-control] /crl/revoke: certificate revoked and CRL reloaded');
      jsonOk(res, { status: 'revoked' });
    } catch (err) {
      console.error('[crl-control] /crl/revoke error:', err.message);
      if (err && err.code === 'PAYLOAD_TOO_LARGE') {
        jsonErr(res, 413, 'payload too large');
      } else {
        jsonErr(res, 500, 'revoke failed');
      }
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
