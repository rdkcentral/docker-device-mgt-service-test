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

var saveXconfJson = false;
var saved_XconfJson = {};

var saveReportJson = false;
var saved_ReportJson = {};

// HTTPS options with base configuration
const options = {
  key: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-key.pem')),
  cert: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-cert.pem')),
  port : 50051
};

// Apply mTLS settings if enabled using the centralized utility
applyMtlsConfig(options);

function handleAdminSupportReport(req, res){
  const queryObject = url.parse(req.url, true).query;
  if (queryObject.saveRequest === 'true') {
    saveReportJson = true;
  }else if (queryObject.saveRequest === 'false'){
    saveReportJson = false;
    saved_ReportJson = {};
  }
  if ( queryObject.returnData === 'true'){
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify(saved_ReportJson));
    return;
  }
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end('Message received at Data Lake Mock Server\n');
  return;
}

function handleAdminSupportXconf(req, res){
  const queryObject = url.parse(req.url, true).query;
  if (queryObject.saveRequest === 'true') {
    saveXconfJson = true;
  }else if (queryObject.saveRequest === 'false'){
    saveXconfJson = false;
    saved_XconfJson = {};
  }
  if ( queryObject.returnData === 'true'){
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify(saved_XconfJson));
    return;
  }
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end('Message received at Data Lake Mock Server\n');
  return;
}

/**
 * Handles the incoming request and logs the data received
 * @param {http.IncomingMessage} req
 * @param {http.ServerResponse} res
 */
function requestHandler(req, res) {
  
  if (req.url.startsWith('/dataLakeMockXconf')) {
    var data = '';
    req.on('data', function(chunk) {
      data += chunk;
    });
    req.on('end', function() {
      console.log('Data received: ' + data);
      if (saveXconfJson == true){
        const postData = JSON.parse(body);
        
        saved_XconfJson[new Date().toISOString()] = { ...postData };
      }
    });
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end('Message received at Data Lake Mock Server\n');

  } 
  else if (req.url.startsWith('/dataLakeMockReportProfile')){
    var data = '';
    req.on('data', function(chunk) {
      data += chunk;
    });
    req.on('end', function() {
      console.log('Data received: ' + data);
      if (saveReportJson == true){
        const postData = JSON.parse(body);
        saved_ReportJson[new Date().toISOString()] = { ...postData };
      }
    });
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end('Message received at Data Lake Mock Server\n');

  } else if (req.url.startsWith('/adminSupportXconf')){

    return handleAdminSupportXconf(req, res);

  } else if(req.url.startsWith('/adminSupportReport')){

    return handleAdminSupportReport(req, res);

  }else {
    res.writeHead(404, {'Content-Type': 'text/plain'});
    res.end('Not Found\n');
  }
}



const serverinstance = https.createServer(options, requestHandler);

serverinstance.on('error', (err) => {
  console.error('[DataLake:50051] Server error:', err.message);
});
serverinstance.on('tlsClientError', (err, tlsSocket) => {
  console.error('[DataLake:50051] TLS error:', err.message, 'code:', err.code);
});
serverinstance.on('clientError', (err, socket) => {
  console.error('[DataLake:50051] Client error:', err.message);
  if (!socket.destroyed) socket.end('HTTP/1.1 400\r\n\r\n');
});
serverinstance.on('secureConnection', (tlsSocket) => {
  const cert = tlsSocket.getPeerCertificate();
  console.log('[DataLake:50051] ✓ TLS from', cert.subject ? cert.subject.CN : 'no-cert');
});
serverinstance.on('request', (req) => {
  console.log(`[DataLake:50051] → ${req.method} ${req.url}`);
});

serverinstance.listen(options.port, () => {
  console.log('[DataLake:50051] Server started on https://localhost:50051/');
  console.log(`[DataLake:50051] mTLS: ${process.env.ENABLE_MTLS === 'true' ? 'ENABLED' : 'DISABLED'}`);
});

