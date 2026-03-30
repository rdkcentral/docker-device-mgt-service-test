/*
 * xPKI Actual Key Test
 * 
 * Direct libcertifier test with actual EC keys (bypasses PKCS#11 complexity).
 * Tests the core xPKI workflow:
 *   1. Generate actual EC key pair in memory (prime256v1)
 *   2. Authenticate to xPKI server using seed certificate (mTLS)
 *   3. Generate CSR with the actual key
 *   4. Obtain operational certificate from xPKI server
 *   5. Save operational cert + actual key to P12 file
 * 
 * This validates xPKI server functionality before testing PKCS#11 P12 patches.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <openssl/ec.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/x509.h>
#include <certifier/xpki_client.h>

int main(int argc, char *argv[]) {
    int rc = 1;
    EC_KEY *keypair = NULL;
    
    fprintf(stderr, "\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "xPKI Actual Key Test\n");
    fprintf(stderr, "Direct libcertifier API with real EC keys\n");
    fprintf(stderr, "========================================\n\n");
    
    // Check seed P12 exists
    const char *seed_p12 = "/opt/certs/pkcs11seedref.pk12";
    if (access(seed_p12, F_OK) != 0) {
        fprintf(stderr, "ERROR: Seed P12 not found: %s\n", seed_p12);
        fprintf(stderr, "       Run setup-pkcs11.sh first\n");
        return 1;
    }
    fprintf(stderr, "✓ Seed P12 found: %s\n\n", seed_p12);
    
    // Step 1: Generate actual EC key pair
    fprintf(stderr, "Step 1: Generating EC key pair (prime256v1)...\n");
    keypair = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!keypair) {
        fprintf(stderr, "ERROR: Failed to create EC_KEY\n");
        return 1;
    }
    
    if (EC_KEY_generate_key(keypair) != 1) {
        fprintf(stderr, "ERROR: Failed to generate EC key\n");
        EC_KEY_free(keypair);
        return 1;
    }
    
    fprintf(stderr, "✓ EC key generated (ACTUAL key bytes, not PKCS#11 reference)\n");
    fprintf(stderr, "  Curve: prime256v1 (secp256r1)\n");
    fprintf(stderr, "  Key type: In-memory OpenSSL EC_KEY\n\n");
    
    // Step 2: Setup xPKI parameters
    fprintf(stderr, "Step 2: Configuring xPKI parameters...\n");
    get_cert_param_t params;
    memset(&params, 0, sizeof(params));
    
    params.auth_type = XPKI_AUTH_X509;
    params.input_p12_path = "/opt/certs/pkcs11seedref.pk12";
    params.input_p12_password = "changeit";
    params.output_p12_path = "/opt/certs/operational-actual-key.p12";
    params.output_p12_password = "changeit";
    params.validity_days = 365;
    params.lite = 0;
    params.use_scopes = 0;
    params.profile_name = "Sky_RDK_Device_Issuing_ECC_ICA";
    params.common_name = "rdkv.cpe-clnt";
    params.mac_address = "74:06:35:06:DF:6A";
    params.serial_number = "ES13SCU2416000C1";
    params.domain = NULL;
    params.node_id = 0xCCCCCCCCCCCCCCCC;
    params.product_id = 0x1101;
    params.fabric_id = 0xDDDDDDDDDDDDDDDD;
    params.case_auth_tag = 0;
    params.keypair = keypair;  // ← ACTUAL KEY (not PKCS#11 reference!)
    params.static_certifier = 0;
    params.overwrite_p12 = 1;
    
    fprintf(stderr, "✓ Parameters configured\n");
    fprintf(stderr, "  Auth type: X.509 (seed certificate for mTLS)\n");
    fprintf(stderr, "  Seed P12: %s\n", params.input_p12_path);
    fprintf(stderr, "  Output P12: %s\n", params.output_p12_path);
    fprintf(stderr, "  Profile: %s\n", params.profile_name);
    fprintf(stderr, "  Common Name: %s\n", params.common_name);
    fprintf(stderr, "  MAC: %s\n", params.mac_address);
    fprintf(stderr, "  Serial: %s\n", params.serial_number);
    fprintf(stderr, "  Keypair: ACTUAL EC key (memory)\n\n");
    
    // Step 3: Call xPKI server
    fprintf(stderr, "Step 3: Calling xPKI server...\n");
    fprintf(stderr, "  • Authenticating with seed cert (mTLS)\n");
    fprintf(stderr, "  • Generating CSR with actual key\n");
    fprintf(stderr, "  • Requesting operational certificate\n");
    fprintf(stderr, "  • Saving to P12 format\n\n");
    
    XPKI_CLIENT_ERROR_CODE err = xc_get_cert(&params);
    
    if (err == XPKI_CLIENT_SUCCESS) {
        fprintf(stderr, "✓ SUCCESS: Certificate obtained from xPKI server\n");
        fprintf(stderr, "  Output P12: %s\n", params.output_p12_path);
        
        // Verify P12 was created
        if (access(params.output_p12_path, F_OK) == 0) {
            fprintf(stderr, "  ✓ P12 file created successfully\n");
            
            // Get file size
            FILE *fp = fopen(params.output_p12_path, "rb");
            if (fp) {
                fseek(fp, 0, SEEK_END);
                long size = ftell(fp);
                fclose(fp);
                fprintf(stderr, "    Size: %ld bytes\n", size);
            }
            
            fprintf(stderr, "\n");
            fprintf(stderr, "Verification:\n");
            fprintf(stderr, "  You can verify the P12 with:\n");
            fprintf(stderr, "    openssl pkcs12 -in %s -passin pass:%s -noout -info\n",
                    params.output_p12_path, params.output_p12_password);
            
            rc = 0;  // Success
        } else {
            fprintf(stderr, "✗ ERROR: P12 file not created\n");
            rc = 1;
        }
    } else if (err == XPKI_CLIENT_CERT_ALREADY_VALID) {
        fprintf(stderr, "ℹ Certificate already valid (not expired)\n");
        fprintf(stderr, "  Output P12: %s\n", params.output_p12_path);
        
        // Still verify the file exists
        if (access(params.output_p12_path, F_OK) == 0) {
            fprintf(stderr, "  ✓ P12 file exists\n");
            rc = 0;  // Success
        } else {
            fprintf(stderr, "  ⚠ P12 file not found\n");
            rc = 1;
        }
    } else {
        fprintf(stderr, "✗ FAILED: xc_get_cert() returned error\n");
        fprintf(stderr, "  Error code: %d (0x%x)\n", err, err);
        
        // Provide helpful error messages
        switch (err) {
            case XPKI_CLIENT_INVALID_ARGUMENT:
                fprintf(stderr, "  Reason: Invalid argument\n");
                break;
            case XPKI_CLIENT_ERROR_INTERNAL:
                fprintf(stderr, "  Reason: Internal error (check libcertifier logs)\n");
                break;
            default:
                fprintf(stderr, "  Reason: Unknown error (check logs)\n");
                break;
        }
        
        fprintf(stderr, "\nTroubleshooting:\n");
        fprintf(stderr, "  1. Check seed P12 is valid:\n");
        fprintf(stderr, "       openssl pkcs12 -in %s -passin pass:changeit -noout\n", seed_p12);
        fprintf(stderr, "  2. Check xPKI server is running:\n");
        fprintf(stderr, "       curl -k https://mockxconf:50055/v1/certifier\n");
        fprintf(stderr, "  3. Check libcertifier logs:\n");
        fprintf(stderr, "       tail -50 /opt/logs/libcertifier.log\n");
        
        rc = 1;
    }
    
    // Cleanup
    EC_KEY_free(keypair);
    
    fprintf(stderr, "\n");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "Test Result: %s\n", rc == 0 ? "PASSED ✓" : "FAILED ✗");
    fprintf(stderr, "========================================\n");
    fprintf(stderr, "\n");
    
    return rc;
}
