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

const path = require('node:path');
const fs = require('node:fs');
const url = require('node:url');


let saveUploadedLogs = true;
let uploadedLogs = {};
let uploadCount = 0;
let failureMode = null; // null, 'direct', or 'both'
let httpStatusCode = 200; // Can be changed to test different HTTP responses

// Helper function to safely load certificates
function loadCertificates() {
  const keyPath = '/etc/xconf/certs/mock-xconf-server-key.pem';
  const certPath = '/etc/xconf/certs/mock-xconf-server-cert.pem';

  try {
    if (fs.existsSync(keyPath) && fs.existsSync(certPath)) {
      return {
        key: fs.readFileSync(keyPath),
        cert: fs.readFileSync(certPath)
      };
    }
  } catch (err) {
    console.warn('Failed to load certificates:', err.message);
  }
  return null;
}

const certs = loadCertificates();

// HTTPS options for Direct upload endpoint (port 50058)
const directOptions = {
  ...(certs || {}),
  port: 50058
};

// HTTPS options for S3 presigned URL endpoint (port 50057)
const s3Options = {
  ...(certs || {}),
  port: 50057
};

/**
 * Handles admin endpoints for testing control
 */
function handleAdminEndpoint(req, res) {
  const queryObject = url.parse(req.url, true).query;

  // Enable/disable saving uploaded logs
  if (queryObject.saveUploads === 'true') {
    saveUploadedLogs = true;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Save uploads enabled' }));
    return;
  } else if (queryObject.saveUploads === 'false') {
    saveUploadedLogs = false;
    uploadedLogs = {};
    uploadCount = 0;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Save uploads disabled and cleared' }));
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
    failureMode = queryObject.failureMode; // 'direct', 'both', or 'none'
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: `Failure mode set to: ${failureMode}` }));
    return;
  }

  // Set HTTP status code for responses
  if (queryObject.statusCode) {
    const parsedStatusCode = parseInt(queryObject.statusCode, 10);
    if (Number.isNaN(parsedStatusCode) || parsedStatusCode < 100 || parsedStatusCode > 599) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: `Invalid status code: ${queryObject.statusCode}` }));
      return;
    }
    httpStatusCode = parsedStatusCode;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: `Status code set to: ${httpStatusCode}` }));
    return;
  }

  // Reset to defaults
  if (queryObject.reset === 'true') {
    saveUploadedLogs = true;
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
 * Handles metadata POST requests (Direct mTLS endpoint)
 * This receives a filename POST and returns a presigned URL
 */
function handleDirectLogUpload(req, res) {
  const queryObject = url.parse(req.url, true).query;

  // Check if this endpoint should fail
  if (failureMode === 'direct' || failureMode === 'both') {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end('Direct upload endpoint simulated failure');
    return;
  }

  let body = [];

  req.on('data', chunk => {
    body.push(chunk);
  });

  req.on('end', () => {
    body = Buffer.concat(body).toString();

    // Extract filename from POST body (e.g., "filename=logs.tar.gz")
    let filename = 'unknown.tar.gz';
    const urlPath = req.url.split('?')[0];
    const pathFilename = path.basename(urlPath);

    if (pathFilename && pathFilename !== 'cgi-bin' && pathFilename !== '/') {
      filename = pathFilename;
    } else if (body) {
      // Try to extract from form data
      const match = body.match(/filename[=:]([^\s&]+)/);
      if (match) filename = match[1];
    }

    uploadCount++;
    const uploadId = `upload_${uploadCount}_${Date.now()}`;

    console.log(`[Direct Metadata POST] Filename: ${filename}, Upload ID: ${uploadId}`);

    if (saveUploadedLogs) {
      uploadedLogs[uploadId] = {
        timestamp: new Date().toISOString(),
        endpoint: 'direct-metadata',
        filename: filename,
        uploadId: uploadId,
        body: body,
        headers: req.headers,
        query: queryObject
      };
    }

    // Generate mock S3 presigned URL pointing back to mockxconf:50057
    const s3Bucket = 'mock-s3-bucket';
    const s3Key = `logs/${uploadId}/${filename}`;
    const mockS3Url = `https://mockxconf:50057/${s3Bucket}/${s3Key}?uploadId=${uploadId}&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MOCKKEY&X-Amz-Date=20251220T000000Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=mocksignature`;

    // Return presigned URL in response body
    // The upload library expects HTTP 202 (Accepted) with URL in body
    if (httpStatusCode === 200) {
      res.writeHead(200, {
        'Content-Type': 'text/plain'
      });
      res.end(mockS3Url);
    } else {
      // For non-200 status codes, return error response
      res.writeHead(httpStatusCode, { 'Content-Type': 'text/plain' });
      res.end(`Upload failed with status ${httpStatusCode}`);
    }
  });
}



/**
 * Handles S3 presigned URL PUT requests
 */
function handleS3Put(req, res) {
  const queryObject = url.parse(req.url, true).query;
  const uploadId = queryObject.uploadId || 'unknown';

  console.log(`[S3 PUT] ${req.method} ${req.url}`);
  console.log(`[S3 PUT] Upload ID: ${uploadId}`);

  // Only accept PUT requests
  if (req.method !== 'PUT') {
    res.writeHead(405, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Method not allowed. Use PUT.' }));
    return;
  }

  let body = [];
  let totalBytes = 0;

  req.on('data', chunk => {
    body.push(chunk);
    totalBytes += chunk.length;
  });

  req.on('end', () => {
    body = Buffer.concat(body);

    console.log(`[S3 PUT] Received file: ${totalBytes} bytes`);

    // Save uploaded file to disk
    const uploadDir = '/mnt/L2_CONTAINER_SHARED_VOLUME/uploaded_logs';
    try {
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }

      // Extract filename from URL path
      const urlPath = req.url.split('?')[0];
      const filename = path.basename(urlPath) || `upload_${uploadId}.tar.gz`;
      const filepath = path.join(uploadDir, filename);

      fs.writeFileSync(filepath, body);
      console.log(`[S3 PUT] File saved to: ${filepath}`);

      if (saveUploadedLogs) {
        uploadedLogs[`s3_${uploadId}`] = {
          timestamp: new Date().toISOString(),
          endpoint: 's3-presigned',
          uploadId: uploadId,
          size: body.length,
          filepath: filepath,
          contentType: req.headers['content-type'] || 'application/octet-stream',
          headers: req.headers,
          query: queryObject
        };
      }

      // Return 200 OK (S3 presigned URL success response) only if save succeeded
      res.writeHead(200, {
        'Content-Type': 'text/plain',
        'ETag': `"${uploadId}"`,
        'x-amz-request-id': uploadId
      });
      res.end('OK');
      return;
    } catch (err) {
      console.error(`[S3 PUT] Error saving file: ${err.message}`);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Failed to save uploaded file' }));
      return;
    }
  });

  req.on('error', (err) => {
    console.error(`[S3 PUT] Error receiving data: ${err.message}`);
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Upload failed' }));
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



// Create HTTPS server for Direct uploads (port 50058)
const directServer = https.createServer(directOptions, directRequestHandler);

directServer.listen(directOptions.port, () => {
  console.log(`STB Log Upload Mock Server (Direct) running on https://localhost:${directOptions.port}`);
  console.log('Admin endpoints:');
  console.log(`  - Enable logging: https://mockxconf:${directOptions.port}/admin/stbLogUpload?saveUploads=true`);
  console.log(`  - Get upload data: https://mockxconf:${directOptions.port}/admin/stbLogUpload?returnData=true`);
  console.log(`  - Set failure mode: https://mockxconf:${directOptions.port}/admin/stbLogUpload?failureMode=direct`);
  console.log(`  - Set status code: https://mockxconf:${directOptions.port}/admin/stbLogUpload?statusCode=503`);
  console.log(`  - Reset: https://mockxconf:${directOptions.port}/admin/stbLogUpload?reset=true`);
});



// Create HTTPS server for S3 presigned URL uploads (port 50057)
const s3Server = https.createServer(s3Options, handleS3Put);

s3Server.listen(s3Options.port, () => {
  console.log(`STB Log Upload Mock Server (S3 Presigned) running on https://localhost:${s3Options.port}`);
  console.log('  - Accepts PUT requests with presigned URL query parameters');
  console.log('  - Uploaded files saved to: /mnt/L2_CONTAINER_SHARED_VOLUME/uploaded_logs/');
});

module.exports = { directServer, s3Server };
