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

const options = {
  key: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-key.pem')),
  cert: fs.readFileSync(path.join('/etc/xconf/certs/mock-xconf-server-cert.pem')),
  port: 50052
};

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
    else if (req.url.startsWith('/firmwareupdate404/getfirmwaredata')) {
      res.writeHead(404);
      res.end("404 No Content");
      return;
    }
  }
  res.writeHead(200);
  res.end("Server is Up Please check the request....");
}

const serverInstance = https.createServer(options, requestHandler);
serverInstance.listen(
  options.port,
  () => {
    console.log('XCONF Mock Server running at https://localhost:50052/');
  }
);
