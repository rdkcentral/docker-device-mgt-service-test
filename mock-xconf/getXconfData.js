/*
 * If not stated otherwise in this file or this component's LICENSE file the
 * following copyright and licenses apply:
 *
 * Copyright 2024 RDK Management
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

const https = require('node:https');
const path = require('node:path');
const fs = require('node:fs');
const url = require('node:url'); 
const { applyMtlsConfig } = require('./server-utils');

const TLS_KEY = fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-key.pem'));
const TLS_CERT = fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-cert.pem'));

const MTLS_PORT = 50052;   // existing secure endpoint (unchanged)
const DCDN_PORT = 50065;   // new DirectCDN endpoint

// mTLS-enabled HTTPS options (legacy + secure paths)
const mtlsOptions = {
  key: TLS_KEY,
  cert: TLS_CERT
};
applyMtlsConfig(mtlsOptions);

// DCDN should also be HTTPS + mTLS (same trust behavior)
const dcdnOptions = {
  key: TLS_KEY,
  cert: TLS_CERT
};
applyMtlsConfig(dcdnOptions);

let save_request = false;
let savedrequest_json = {};

function getResponseFileName(count, prefix = '') {
  if (count === 0) return `${prefix}xconf-cdl-response.json`;
  if (count === 1) return `${prefix}xconf-cdl-invalid-response.json`;
  if (count === 2) return `${prefix}xconf-cdl-invalidpci-response.json`;
  if (count === 3) return `${prefix}xconf-cdl-delaydwnl-response.json`;
  if (count === 4) return `${prefix}xconf-cdl-reboottrue-response.json`;
  if (count === 5) return `${prefix}xconf-peripheralcdl-response.json`;
  if (count === 6) return `${prefix}xconf-peripheralcdl-404response.json`;
  if (count === 7) return `${prefix}xconf-certbundle-response.json`;
  return `${prefix}xconf-cdl-response.json`;
}

function readJsonFile(count, prefix = '') {
  const basePath = prefix === 'DCDN_' ? '/etc/xconf/DCDN' : '/etc/xconf';
  const fileName = getResponseFileName(count, prefix);
  const filePath = path.join(basePath, fileName);

  console.log(`Reading XConf response file: ${filePath}`);

  try {
    const fileData = fs.readFileSync(filePath, 'utf8');
    console.log('Data received1: ' + fileData);
    return JSON.parse(fileData);
  } catch (error) {
    console.error(`Error reading/parsing JSON file ${filePath}:`, error);
    return null;
  }
}

function handleFirmwareData(req, res, queryObject, file, prefix = '') {
  let data = '';
  req.on('data', (chunk) => { data += chunk; });
  req.on('end', () => { console.log('Data received2: ' + data); });

  if (save_request) {
    savedrequest_json[new Date().toISOString()] = { ...queryObject };
  }

  const payload = readJsonFile(file, prefix);
  if (!payload) {
    res.writeHead(500, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ error: 'Failed to read response payload' }));
    return;
  }

  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify(payload));
}

function handleFirmwareFileDownload(req, res) {
  const routePrefix = '/getfirmwarefile/';
  if (!req.url.startsWith(routePrefix)) {
    res.writeHead(400, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ error: 'Invalid firmware file request path' }));
    return;
	}

  const relativePath = decodeURIComponent(req.url.slice(routePrefix.length));
  if (!relativePath || relativePath.includes('..')) {
    res.writeHead(400, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({ error: 'Invalid file path' }));
    return;
  }

  const filePath = path.join('/etc/xconf', relativePath);
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(err));
      return;
    }
    res.writeHead(200, {'Content-Type': 'application/octet-stream'});
    res.end(data);
  });
}

/** mTLS server: legacy/non-DCDN routes */
function secureRequestHandler(req, res) {
  const queryObject = url.parse(req.url, true).query;
  console.log('[mTLS] Request received:', req.method, req.url);

  if (req.method === 'GET') {
    if (req.url.startsWith('/firmwareupdate/getfirmwaredata')) return handleFirmwareData(req, res, queryObject, 0);
    if (req.url.startsWith('/getfirmwarefile')) return handleFirmwareFileDownload(req, res);
    if (req.url.startsWith('/firmwareupdate404/getfirmwaredata')) {
      res.writeHead(404); res.end('404 No Content'); return;
    }
  } else if (req.method === 'POST') {
    if (req.url.startsWith('/firmwareupdate/getfirmwaredata')) return handleFirmwareData(req, res, queryObject, 0);
    if (req.url.startsWith('/firmwareupdate/getinvalidfirmwaredata')) return handleFirmwareData(req, res, queryObject, 1);
    if (req.url.startsWith('/firmwareupdate/getinvalidpcifirmwaredata')) return handleFirmwareData(req, res, queryObject, 2);
    if (req.url.startsWith('/firmwareupdate/delaydwnlfirmwaredata')) return handleFirmwareData(req, res, queryObject, 3);
    if (req.url.startsWith('/firmwareupdate/getreboottruefirmwaredata')) return handleFirmwareData(req, res, queryObject, 4);
    if (req.url.startsWith('/firmwareupdate/getperipheralfirmwaredata')) return handleFirmwareData(req, res, queryObject, 5);
    if (req.url.startsWith('/firmwareupdate/get404peripheralfirmwaredata')) return handleFirmwareData(req, res, queryObject, 6);
    if (req.url.startsWith('/firmwareupdate/getcertbundlefirmwaredata')) return handleFirmwareData(req, res, queryObject, 7);

    if (req.url.startsWith('/firmwareupdate404/getfirmwaredata')) {
      res.writeHead(404); res.end('404 No Content'); return;
    }
  }

  res.writeHead(404);
  res.end('Not Found');
}

/** DCDN server: DCDN routes */
function dcdnRequestHandler(req, res) {
   const queryObject = url.parse(req.url, true).query;
  console.log('[DCDN] Request received:', req.method, req.url);

  if (req.method === 'GET') {
    if (req.url.startsWith('/getfirmwarefile/DCDN/')) return handleFirmwareFileDownload(req, res);
  } else if (req.method === 'POST') {
    if (req.url.startsWith('/firmwareupdate/DCDN/getfirmwaredata')) return handleFirmwareData(req, res, queryObject, 0, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/getinvalidfirmwaredata')) return handleFirmwareData(req, res, queryObject, 1, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/getinvalidpcifirmwaredata')) return handleFirmwareData(req, res, queryObject, 2, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/delaydwnlfirmwaredata')) return handleFirmwareData(req, res, queryObject, 3, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/getreboottruefirmwaredata')) return handleFirmwareData(req, res, queryObject, 4, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/getperipheralfirmwaredata')) return handleFirmwareData(req, res, queryObject, 5, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/get404peripheralfirmwaredata')) return handleFirmwareData(req, res, queryObject, 6, 'DCDN_');
    if (req.url.startsWith('/firmwareupdate/DCDN/getcertbundlefirmwaredata')) return handleFirmwareData(req, res, queryObject, 7, 'DCDN_');
  }

  res.writeHead(404);
  res.end('Not Found');
}

const mtlsServer = https.createServer(mtlsOptions, secureRequestHandler);
const dcdnServer = https.createServer(dcdnOptions, dcdnRequestHandler);

mtlsServer.listen(MTLS_PORT, () => {
  console.log(`XCONF Mock mTLS server running at https://localhost:${MTLS_PORT}/`);
});

dcdnServer.listen(DCDN_PORT, () => {
  console.log(`XCONF Mock DirectCDN mTLS server running at https://localhost:${DCDN_PORT}/`);
});
