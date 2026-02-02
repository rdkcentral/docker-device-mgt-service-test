const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');

// Server state
let saveUploadedDumps = true;
let uploadedDumps = {};
let uploadCount = 0;
let failureMode = null;
let httpStatusCode = 200;

// HTTPS options for metadata endpoint (port 50059)
const metadataOptions = {
  key: fs.readFileSync('/etc/xconf/certs/mock-xconf-server-key.pem'),
  cert: fs.readFileSync('/etc/xconf/certs/mock-xconf-server-cert.pem'),
  port: 50059
};

// HTTPS options for S3 presigned URL endpoint (port 50060)
const s3Options = {
  key: fs.readFileSync('/etc/xconf/certs/mock-xconf-server-key.pem'),
  cert: fs.readFileSync('/etc/xconf/certs/mock-xconf-server-cert.pem'),
  port: 50060
};

/**
 * Admin endpoint for test control
 */
function handleAdminEndpoint(req, res) {
  const queryObject = url.parse(req.url, true).query;

  if (queryObject.saveUploads === 'true') {
    saveUploadedDumps = true;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Save uploads enabled' }));
    return;
  } else if (queryObject.saveUploads === 'false') {
    saveUploadedDumps = false;
    uploadedDumps = {};
    uploadCount = 0;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Save uploads disabled and cleared' }));
    return;
  }

  if (queryObject.returnData === 'true') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      uploadCount: uploadCount,
      uploads: uploadedDumps
    }));
    return;
  }

  if (queryObject.failureMode) {
    failureMode = queryObject.failureMode;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: `Failure mode set to: ${failureMode}` }));
    return;
  }

  if (queryObject.statusCode) {
    httpStatusCode = parseInt(queryObject.statusCode, 10);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: `Status code set to: ${httpStatusCode}` }));
    return;
  }

  if (queryObject.reset === 'true') {
    saveUploadedDumps = true;
    uploadedDumps = {};
    uploadCount = 0;
    failureMode = null;
    httpStatusCode = 200;
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ message: 'Reset to defaults' }));
    return;
  }

  res.writeHead(400, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Invalid admin request' }));
}

/**
 * Handle crash dump metadata POST (returns S3 presigned URL)
 */
function handleCrashMetadataPost(req, res) {
  if (failureMode === 'metadata' || failureMode === 'both') {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end('Simulated metadata endpoint failure');
    return;
  }

  let body = [];
  req.on('data', chunk => body.push(chunk));
  req.on('end', () => {
    body = Buffer.concat(body).toString();
    
    // Parse metadata from POST body (form data)
    const metadata = {};
    body.split('&').forEach(param => {
      const [key, value] = param.split('=');
      metadata[key] = decodeURIComponent(value || '');
    });

    uploadCount++;
    const uploadId = `crash_${uploadCount}_${Date.now()}`;
    
    console.log(`[Crash Metadata POST] Upload ID: ${uploadId}`);
    console.log(`[Crash Metadata] Filename: ${metadata.filename}`);
    console.log(`[Crash Metadata] Type: ${metadata.type}`);
    console.log(`[Crash Metadata] Model: ${metadata.model}`);
    console.log(`[Crash Metadata] FW Version: ${metadata.firmwareVersion}`);
    console.log(`[Crash Metadata] MD5: ${metadata.md5}`);

    if (saveUploadedDumps) {
      uploadedDumps[uploadId] = {
        timestamp: new Date().toISOString(),
        endpoint: 'crash-metadata',
        uploadId: uploadId,
        metadata: metadata,
        headers: req.headers
      };
    }

    // Generate S3 presigned URL pointing to port 50060
    const s3Bucket = 'crash-dump-bucket';
    const s3Key = `crashdumps/${uploadId}/${metadata.filename || 'dump.tgz'}`;
    const presignedUrl = `https://mockxconf:50060/${s3Bucket}/${s3Key}?uploadId=${uploadId}&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=MOCKKEY&X-Amz-Date=${new Date().toISOString()}&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=mocksignature`;

    if (httpStatusCode === 200) {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(presignedUrl);
    } else {
      res.writeHead(httpStatusCode, { 'Content-Type': 'text/plain' });
      res.end(`Upload failed with status ${httpStatusCode}`);
    }
  });
}

/**
 * Handle S3 presigned URL PUT (actual file upload)
 */
function handleS3Put(req, res) {
  const queryObject = url.parse(req.url, true).query;
  const uploadId = queryObject.uploadId || 'unknown';

  console.log(`[S3 PUT] Upload ID: ${uploadId}`);

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
    console.log(`[S3 PUT] Received: ${totalBytes} bytes`);

    // Save file to shared volume
    const uploadDir = '/mnt/L2_CONTAINER_SHARED_VOLUME/uploaded_crashes';
    try {
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }

      const urlPath = req.url.split('?')[0];
      const filename = path.basename(urlPath) || `crash_${uploadId}.tgz`;
      const filepath = path.join(uploadDir, filename);

      fs.writeFileSync(filepath, body);
      console.log(`[S3 PUT] Saved to: ${filepath}`);

      if (saveUploadedDumps) {
        uploadedDumps[`s3_${uploadId}`] = {
          timestamp: new Date().toISOString(),
          endpoint: 's3-presigned',
          uploadId: uploadId,
          size: body.length,
          filepath: filepath,
          headers: req.headers
        };
      }

      res.writeHead(200, {
        'Content-Type': 'text/plain',
        'ETag': `"${uploadId}"`,
        'x-amz-request-id': uploadId
      });
      res.end('OK');
    } catch (err) {
      console.error(`[S3 PUT] Error: ${err.message}`);
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Failed to save file' }));
    }
  });
}

/**
 * Metadata endpoint request handler
 */
function metadataRequestHandler(req, res) {
  console.log(`[Metadata] ${req.method} ${req.url}`);

  if (req.url.startsWith('/admin/crashUpload')) {
    handleAdminEndpoint(req, res);
  } else {
    handleCrashMetadataPost(req, res);
  }
}

// Create servers
const metadataServer = https.createServer(metadataOptions, metadataRequestHandler);
const s3Server = https.createServer(s3Options, handleS3Put);

metadataServer.listen(metadataOptions.port, () => {
  console.log(`Crash Upload Metadata Server running on https://localhost:${metadataOptions.port}`);
  console.log('Admin endpoints:');
  console.log(`  - Enable saving: https://mockxconf:${metadataOptions.port}/admin/crashUpload?saveUploads=true`);
  console.log(`  - Get data: https://mockxconf:${metadataOptions.port}/admin/crashUpload?returnData=true`);
  console.log(`  - Set failure: https://mockxconf:${metadataOptions.port}/admin/crashUpload?failureMode=metadata`);
  console.log(`  - Reset: https://mockxconf:${metadataOptions.port}/admin/crashUpload?reset=true`);
});

s3Server.listen(s3Options.port, () => {
  console.log(`Crash Upload S3 Server running on https://localhost:${s3Options.port}`);
  console.log('  - Accepts PUT requests with presigned URL parameters');
  console.log('  - Files saved to: /mnt/L2_CONTAINER_SHARED_VOLUME/uploaded_crashes/');
});

module.exports = { metadataServer, s3Server };