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

const https = require('node:https');
const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs');
const url = require('node:url');
const { applyMtlsConfig } = require('./server-utils');

let saveUploadedLogs = false;
let uploadedLogs = {};
let uploadCount = 0;
let failureMode = null; // null, 'direct', 'codebig', or 'both'
let httpStatusCode = 200; // Can be changed to test different HTTP responses

// HTTPS options for Direct upload endpoint (port 50055)
const directOptions = {
  key: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-key.pem')),
  cert: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-cert.pem')),
  port: 50055
};

// HTTP options for CodeBig upload endpoint (port 50056)
const codebigPort = 50056;

// Apply mTLS settings for direct uploads
applyMtlsConfig(directOptions);

/**
 * Handles admin endpoints for testing control
 */
function handleAdminEndpoint(req, res) {
  const queryObject = url.parse(req.url, true).query;
  
  // Enable/disable saving uploaded logs
  if (queryObject.saveUploads === 'true') {
    saveUploadedLogs = true;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Upload logging enabled' }));
    return;
  } else if (queryObject.saveUploads === 'false') {
    saveUploadedLogs = false;
    uploadedLogs = {};
    uploadCount = 0;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Upload logging disabled and cleared' }));
    return;
  }
  
  // Return saved upload data
  if (queryObject.returnData === 'true') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      uploadCount: uploadCount,
      uploads: uploadedLogs
    }));
    return;
  }
  
  // Set failure mode for testing
  if (queryObject.failureMode) {
    failureMode = queryObject.failureMode; // 'direct', 'codebig', 'both', or 'none'
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: `Failure mode set to: ${failureMode}` }));
    return;
  }
  
  // Set HTTP status code for responses
  if (queryObject.statusCode) {
    httpStatusCode = parseInt(queryObject.statusCode);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: `Status code set to: ${httpStatusCode}` }));
    return;
  }
  
  // Reset to defaults
  if (queryObject.reset === 'true') {
    saveUploadedLogs = false;
    uploadedLogs = {};
    uploadCount = 0;
    failureMode = null;
    httpStatusCode = 200;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Mock server reset to defaults' }));
    return;
  }
  
  res.writeHead(400, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Invalid admin request' }));
}

/**
 * Handles log upload requests (Direct endpoint)
 */
function handleDirectLogUpload(req, res) {
  const queryObject = url.parse(req.url, true).query;
  
  // Check if this endpoint should fail
  if (failureMode === 'direct' || failureMode === 'both') {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
      statusCode: 500,
      message: 'Direct upload endpoint simulated failure' 
    }));
    return;
  }
  
  let body = [];
  let filename = '';
  let contentType = req.headers['content-type'] || '';
  
  req.on('data', chunk => {
    body.push(chunk);
  });
  
  req.on('end', () => {
    body = Buffer.concat(body);
    
    // Extract filename from URL or headers
    const urlPath = req.url.split('?')[0];
    filename = path.basename(urlPath);
    
    if (!filename || filename === 'cgi-bin') {
      // Try to extract from Content-Disposition header
      const disposition = req.headers['content-disposition'];
      if (disposition) {
        const match = disposition.match(/filename="?([^"]+)"?/);
        if (match) filename = match[1];
      }
    }
    
    uploadCount++;
    const uploadId = `upload_${uploadCount}_${Date.now()}`;
    
    console.log(`[Direct Upload] Received: ${filename}, Size: ${body.length} bytes`);
    
    if (saveUploadedLogs) {
      uploadedLogs[uploadId] = {
        timestamp: new Date().toISOString(),
        endpoint: 'direct',
        filename: filename,
        size: body.length,
        contentType: contentType,
        headers: req.headers,
        query: queryObject
      };
    }
    
    // Return configured status code
    res.writeHead(httpStatusCode, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      statusCode: httpStatusCode,
      message: 'Upload successful',
      uploadId: uploadId,
      filename: filename,
      size: body.length
    }));
  });
}

/**
 * Handles log upload requests (CodeBig endpoint)
 */
function handleCodeBigLogUpload(req, res) {
  const queryObject = url.parse(req.url, true).query;
  
  // Check if this endpoint should fail
  if (failureMode === 'codebig' || failureMode === 'both') {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
      statusCode: 500,
      message: 'CodeBig upload endpoint simulated failure' 
    }));
    return;
  }
  
  let body = [];
  let filename = '';
  let contentType = req.headers['content-type'] || '';
  
  req.on('data', chunk => {
    body.push(chunk);
  });
  
  req.on('end', () => {
    body = Buffer.concat(body);
    
    // Extract filename from URL or headers
    const urlPath = req.url.split('?')[0];
    filename = path.basename(urlPath);
    
    if (!filename || filename === 'cgi-bin') {
      const disposition = req.headers['content-disposition'];
      if (disposition) {
        const match = disposition.match(/filename="?([^"]+)"?/);
        if (match) filename = match[1];
      }
    }
    
    uploadCount++;
    const uploadId = `upload_${uploadCount}_${Date.now()}`;
    
    console.log(`[CodeBig Upload] Received: ${filename}, Size: ${body.length} bytes`);
    
    if (saveUploadedLogs) {
      uploadedLogs[uploadId] = {
        timestamp: new Date().toISOString(),
        endpoint: 'codebig',
        filename: filename,
        size: body.length,
        contentType: contentType,
        headers: req.headers,
        query: queryObject
      };
    }
    
    // Return configured status code
    res.writeHead(httpStatusCode, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      statusCode: httpStatusCode,
      message: 'Upload successful via CodeBig',
      uploadId: uploadId,
      filename: filename,
      size: body.length
    }));
  });
}

/**
 * Main request handler for Direct endpoint
 */
function directRequestHandler(req, res) {
  console.log(`[Direct] ${req.method} ${req.url}`);
  
  if (req.url.startsWith('/admin/stbLogUpload')) {
    handleAdminEndpoint(req, res);
  } else {
    // All other requests are treated as log uploads
    handleDirectLogUpload(req, res);
  }
}

/**
 * Main request handler for CodeBig endpoint
 */
function codebigRequestHandler(req, res) {
  console.log(`[CodeBig] ${req.method} ${req.url}`);
  
  if (req.url.startsWith('/admin/stbLogUpload')) {
    handleAdminEndpoint(req, res);
  } else {
    // All other requests are treated as log uploads
    handleCodeBigLogUpload(req, res);
  }
}

// Create HTTPS server for Direct uploads (port 50055)
const directServer = https.createServer(directOptions, directRequestHandler);

directServer.listen(directOptions.port, () => {
  console.log(`STB Log Upload Mock Server (Direct) running on https://localhost:${directOptions.port}`);
  console.log('Admin endpoints:');
  console.log(`  - Enable logging: https://localhost:${directOptions.port}/admin/stbLogUpload?saveUploads=true`);
  console.log(`  - Get upload data: https://localhost:${directOptions.port}/admin/stbLogUpload?returnData=true`);
  console.log(`  - Set failure mode: https://localhost:${directOptions.port}/admin/stbLogUpload?failureMode=direct`);
  console.log(`  - Set status code: https://localhost:${directOptions.port}/admin/stbLogUpload?statusCode=503`);
  console.log(`  - Reset: https://localhost:${directOptions.port}/admin/stbLogUpload?reset=true`);
});

// Create HTTP server for CodeBig uploads (port 50056)
const codebigServer = http.createServer(codebigRequestHandler);

codebigServer.listen(codebigPort, () => {
  console.log(`STB Log Upload Mock Server (CodeBig) running on http://localhost:${codebigPort}`);
  console.log('Admin endpoints:');
  console.log(`  - Enable logging: http://localhost:${codebigPort}/admin/stbLogUpload?saveUploads=true`);
  console.log(`  - Get upload data: http://localhost:${codebigPort}/admin/stbLogUpload?returnData=true`);
  console.log(`  - Set failure mode: http://localhost:${codebigPort}/admin/stbLogUpload?failureMode=codebig`);
  console.log(`  - Set status code: http://localhost:${codebigPort}/admin/stbLogUpload?statusCode=503`);
  console.log(`  - Reset: http://localhost:${codebigPort}/admin/stbLogUpload?reset=true`);
});

module.exports = { directServer, codebigServer };
