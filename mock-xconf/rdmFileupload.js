const https = require('node:https');
const path = require('node:path');
const fs = require('node:fs');
const url = require('node:url');

const pathupdated = require('path');
const FILE_ROOT = '/tmp/RDM';

let saveXconfJson = false;
let saved_XconfJson = {};

let saveReportJson = false;
let saved_ReportJson = {};

const options = {
  key: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-key.pem')),
  cert: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-cert.pem')),
  port: 50056
};

function handleAdminSupportReport(req, res) {
  const queryObject = url.parse(req.url, true).query;
  if (queryObject.saveRequest === 'true') {
    saveReportJson = true;
  } else if (queryObject.saveRequest === 'false') {
    saveReportJson = false;
    saved_ReportJson = {};
  }
  if (queryObject.returnData === 'true') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(saved_ReportJson));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end('Message received at RDM Data Upload Mock Server\n');
}

function handleAdminSupportXconf(req, res) {
  const queryObject = url.parse(req.url, true).query;
  if (queryObject.saveRequest === 'true') {
    saveXconfJson = true;
  } else if (queryObject.saveRequest === 'false') {
    saveXconfJson = false;
    saved_XconfJson = {};
  }
  if (queryObject.returnData === 'true') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(saved_XconfJson));
    return;
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end('Message received at RDM Data Upload Mock Server\n');
}

function parseMultipartFormData(req, callback) {
  const boundary = req.headers['content-type'].split('; ')[1].replace('boundary=', '');
  let rawData = '';

  req.on('data', chunk => {
    rawData += chunk;
  });

  req.on('end', () => {
    const parts = rawData.split(`--${boundary}`);
    const files = [];

    parts.forEach(part => {
      if (part.includes('Content-Disposition: form-data;')) {
        const [header, body] = part.split('\r\n\r\n');
        const filenameMatch = header.match(/filename="(.+?)"/);
        if (filenameMatch) {
          const filename = filenameMatch[1];
          const filePath = path.join('/tmp/', filename);
          fs.writeFileSync(filePath, body.trim());
          files.push(filePath);
        }
      }
    });

    callback(files);
  });
}

function getFilePathFromUrl(url) {
  const filename = decodeURIComponent(url.split('/rdmUploadFile/')[1]);
  const absPath = pathupdated.resolve(FILE_ROOT, filename);
  
  if (!absPath.startsWith(FILE_ROOT)) {
    return null;
  }
  return absPath;	
}

function requestHandler(req, res) {
  if (req.url.startsWith('/rdmDebugReport')) {
    let data = '';
    req.on('data', chunk => {
      data += chunk;
    });
    req.on('end', () => {
      console.log('Data received: ' + data);
      if (saveReportJson) {
        const postData = JSON.parse(data);
        saved_ReportJson[new Date().toISOString()] = { ...postData };
      }
    });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end('Message received at RDM Data Upload Mock Server\n');
  } else if (req.url.startsWith('/adminSupportXconf')) {
    handleAdminSupportXconf(req, res);
  } else if (req.url.startsWith('/adminSupportReport')) {
    handleAdminSupportReport(req, res);
   } else if (req.url.startsWith('/rdmUploadFile')) {
    if (req.method === 'POST') {
      parseMultipartFormData(req, files => {
        console.log('Files uploaded:', files);
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('File uploaded successfully\n');
      });

    } else if (req.method === 'GET') {
      console.log('GET request URL:', req.url);
      const filePath = getFilePathFromUrl(req.url);
      console.log('Resolved file path:', filePath);

      if (!filePath) {
        console.log('Invalid file path (possible traversal attempt):', req.url);
        res.writeHead(403, { 'Content-Type': 'text/plain' });
        res.end('Access denied\n');
      } else {
        fs.access(filePath, fs.constants.F_OK, (err) => {
          if (err) {
            console.log('File not found:', filePath);
            res.writeHead(404, { 'Content-Type': 'text/plain' });
            res.end('File not found\n');
          } else {
            res.writeHead(200, {
              'Content-Type': 'application/octet-stream',
              'Content-Disposition': `attachment; filename="${path.basename(filePath)}"`
            });
            fs.createReadStream(filePath).pipe(res);
          }
        });
      }
    }

  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found\n');
  }
}
 
const serverinstance = https.createServer(options, requestHandler);
serverinstance.listen(options.port, () => {
  console.log('RDM Data Upload Mock Server running at https://localhost:50056/');
});

serverinstance.on('error', (err) => {
  console.error('Server error:', err);
});
