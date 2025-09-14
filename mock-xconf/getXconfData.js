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

// Check if mTLS is enabled
const mtlsEnabled = process.env.ENABLE_MTLS === 'true';

// HTTPS options with base configuration
const httpsOptions = {
  key: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-key.pem')),
  cert: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-cert.pem')),
  port: 50052
};

// Add mTLS settings if enabled
if (mtlsEnabled && fs.existsSync('/etc/xconf/trust-store/root-ca.cert.pem') &&
  fs.existsSync('/etc/xconf/trust-store/intermediate-ca.cert.pem')) {
  httpsOptions.ca = [
    fs.readFileSync('/etc/xconf/trust-store/root-ca.cert.pem'),
    fs.readFileSync('/etc/xconf/trust-store/intermediate-ca.cert.pem')
  ];
  httpsOptions.requestCert = true;
  httpsOptions.rejectUnauthorized = true;
  console.log('mTLS configuration loaded successfully');
}

let save_request = false;
let savedrequest_json={};

/**
 * Function to read JSON file and return the data
 */
function readJsonFile(count) {
  if(count == 0){
    var filePath = path.join('/etc/xconf', 'xconf-cdl-response.json');
  }
  else if(count == 1){
    var filePath = path.join('/etc/xconf', 'xconf-cdl-invalid-response.json');
  }
  else if(count == 2){
    var filePath = path.join('/etc/xconf', 'xconf-cdl-invalidpci-response.json');
  }
  else if(count == 3){
    var filePath = path.join('/etc/xconf', 'xconf-cdl-delaydwnl-response.json');
  }
  else if(count == 4){
    var filePath = path.join('/etc/xconf', 'xconf-cdl-reboottrue-response.json');
  }
  else if(count == 5){
    var filePath = path.join('/etc/xconf', 'xconf-peripheralcdl-response.json');
  }
  else if(count == 6){
    var filePath = path.join('/etc/xconf', 'xconf-peripheralcdl-404response.json');
  }
  else if(count == 7){
    var filePath = path.join('/etc/xconf', 'xconf-certbundle-response.json');
  }
  else{
    var filePath = path.join('/etc/xconf', 'xconf-cdl-response.json');
  }
  try {
    const fileData = fs.readFileSync(filePath, 'utf8');
    console.log('Data received1: ' + fileData);
    return JSON.parse(fileData);
  } catch (error) {
    console.error('Error reading or parsing JSON file:', error);
    return null;
  }
}  

function handleFirmwareData(req, res, queryObject, file) {
  let data = '';
  req.on('data', function(chunk) {
    data += chunk;
  });
  req.on('end', function() {
    console.log('Data received2: ' + data);
  });

  if (save_request) {
    savedrequest_json[new Date().toISOString()] = { ...queryObject };
  }

  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify(readJsonFile(file)));
  //console.log('Data received After stringfy: ' + JSON.stringify(readJsonFile(file)));
  return;
}

function handleFirmwareFileDownload(req, res, queryObject, index) {
  const fileName = req.url.split('/').pop();
  //const filePath = path.join(__dirname, fileName);
  const filePath = path.join('/etc/xconf', fileName);

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end(JSON.stringify(err));
      return;
    }
    res.writeHead(200, {'Content-Type': 'application/octet-stream'});
    res.end(data);
  });
}
/**
 * Handles the incoming request and logs the data received
 * @param {http.IncomingMessage} req - The incoming request object
 * @param {http.ServerResponse} res - The server response object
 */
function requestHandler(req, res) {
  const queryObject = url.parse(req.url, true).query;
  console.log('Query Object: ' + JSON.stringify(queryObject));
  console.log('Request received: ' + req.url);
  console.log('json'+JSON.stringify(savedrequest_json));
  console.log('Request method: ' + req.method);
  if (req.method === 'GET') {
    if (req.url.startsWith('/firmwareupdate/getfirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,0); 
    }
    else if (req.url.startsWith('/getfirmwarefile')) {
      return handleFirmwareFileDownload(req, res, queryObject,0); 
    }
    else if (req.url.startsWith('/firmwareupdate404/getfirmwaredata')) {
      res.writeHead(404);
      res.end("404 No Content");
      return;
    }
  }
  else if (req.method === 'POST') {
    if (req.url.startsWith('/firmwareupdate/getfirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,0); 
    }
    else if (req.url.startsWith('/firmwareupdate/getinvalidfirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,1); 
    }
    else if (req.url.startsWith('/firmwareupdate/getinvalidpcifirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,2); 
    }
    else if (req.url.startsWith('/firmwareupdate/delaydwnlfirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,3); 
    }
    else if (req.url.startsWith('/firmwareupdate/getreboottruefirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,4); 
    }
    else if (req.url.startsWith('/firmwareupdate/getperipheralfirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,5); 
    }
    else if (req.url.startsWith('/firmwareupdate/get404peripheralfirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,6); 
    }
    else if (req.url.startsWith('/firmwareupdate/getcertbundlefirmwaredata')) {
      return handleFirmwareData(req, res, queryObject,7); 
    }
    else if (req.url.startsWith('/firmwareupdate404/getfirmwaredata')) {
      res.writeHead(404);
      res.end("404 No Content");
      return;
    }
  }
  res.writeHead(200);
  res.end("Server is Up Please check the request....");
}

// Add endpoint for mTLS status
function requestHandlerWithMtlsStatus(req, res) {
  const parsedUrl = url.parse(req.url, true);

  if (req.method === 'GET' && parsedUrl.pathname === '/mtls/status') {
    // Endpoint to report mTLS status
    res.writeHead(200, {'Content-Type': 'application/json'});
    const statusData = {
      mtlsEnabled: mtlsEnabled,
      certificatesLoaded: mtlsEnabled && httpsOptions.ca ? true : false
    };
    res.end(JSON.stringify(statusData));
    return;
  }

  // Use existing request handler for other requests
  requestHandler(req, res);
}

// Create HTTPS server
const server = https.createServer(httpsOptions, requestHandlerWithMtlsStatus);

// Start the server
server.listen(httpsOptions.port, () => {
  console.log(`XCONF Mock Server running at https://localhost:${httpsOptions.port}/ with mTLS ${mtlsEnabled ? 'enabled' : 'disabled'}`);
});