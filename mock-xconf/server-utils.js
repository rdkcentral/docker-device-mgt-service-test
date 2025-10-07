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

const fs = require('node:fs');

// Path to CA chain file
const CA_CHAIN_PATH = '/etc/xconf/trust-store/ca-chain.pem';

/**
 * Checks if mTLS is enabled via environment variable
 * @returns {boolean} True if mTLS is enabled
 */
function isMtlsEnabled() {
  return process.env.ENABLE_MTLS === 'true';
}

/**
 * Applies mTLS configuration to HTTPS options object if enabled
 * @param {object} options - The HTTPS options object to modify
 * @returns {object} The modified options object with mTLS settings if enabled
 */
function applyMtlsConfig(options) {
  const mtlsEnabled = isMtlsEnabled();
  
  // Add mTLS settings if enabled
  if (mtlsEnabled && fs.existsSync(CA_CHAIN_PATH)) {
    options.ca = fs.readFileSync(CA_CHAIN_PATH);
    options.requestCert = true;
    options.rejectUnauthorized = true;
    console.log('mTLS configuration loaded successfully with CA chain');
  } else if (mtlsEnabled) {
    console.warn('mTLS is enabled but CA chain file not found in trust store');
  }
  
  return options;
}

module.exports = {
  isMtlsEnabled,
  applyMtlsConfig
};
