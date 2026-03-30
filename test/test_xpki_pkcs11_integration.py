"""
xPKI PKCS#11 Integration Tests

Tests xPKI certificate procurement with actual keys using direct libcertifier API.
Validates xPKI server functionality before testing complex PKCS#11 P12 patches.

Test Flow:
  1. Compile C test harness (xpki_actual_key_test)
  2. Run test with actual EC keys (in-memory, not PKCS#11)
  3. Verify operational certificate P12 creation
  4. Verify P12 contents
"""

import docker
import pytest
import os
import subprocess
import time

# Initialize Docker client
client = docker.DockerClient(base_url="unix:///var/run/docker.sock")

# Container name
NATIVE_PLATFORM = "native-platform"

# Test artifacts
TEST_C_SOURCE = "/mnt/L2_CONTAINER_SHARED_VOLUME/test/xpki_actual_key_test.c"
TEST_BINARY = "/tmp/xpki_actual_key_test"
SEED_P12 = "/opt/certs/pkcs11seedref.pk12"
OUTPUT_P12 = "/opt/certs/operational-actual-key.p12"


@pytest.fixture(scope="module")
def container():
    """Get the native-platform container."""
    try:
        container = client.containers.get(NATIVE_PLATFORM)
        container.reload()
        assert container.status == "running", f"{NATIVE_PLATFORM} is not running"
        return container
    except docker.errors.NotFound:
        pytest.fail(f"Container {NATIVE_PLATFORM} not found. Run: docker-compose up -d")


@pytest.fixture(scope="module")
def compiled_test(container):
    """
    Compile the C test program inside native-platform container.
    Uses libcertifier and OpenSSL libraries.
    """
    print(f"\n{'='*60}")
    print("Compiling xPKI Actual Key Test")
    print(f"{'='*60}")
    
    # Check if source file exists
    exit_code, output = container.exec_run(f"test -f {TEST_C_SOURCE}")
    if exit_code != 0:
        pytest.fail(f"Source file not found: {TEST_C_SOURCE}")
    
    print(f"✓ Source file found: {TEST_C_SOURCE}")
    
    # Compile the test
    compile_cmd = [
        "gcc",
        "-o", TEST_BINARY,
        TEST_C_SOURCE,
        "-I/usr/local/include/certifier",
        "-I/usr/local/include",
        "-L/usr/local/lib",
        "-L/usr/local/lib64",
        "-lcertifier",
        "-lssl",
        "-lcrypto",
        "-Wl,-rpath,/usr/local/lib:/usr/local/lib64",
        "-Wall"
    ]
    
    print(f"Compiling: {' '.join(compile_cmd)}")
    
    exit_code, output = container.exec_run(compile_cmd)
    
    if exit_code != 0:
        print(f"\n✗ Compilation FAILED:")
        print(output.decode())
        pytest.fail("Failed to compile xpki_actual_key_test")
    
    print("✓ Compilation successful")
    
    # Verify binary exists
    exit_code, output = container.exec_run(f"test -f {TEST_BINARY}")
    if exit_code != 0:
        pytest.fail(f"Binary not created: {TEST_BINARY}")
    
    # Get binary info
    exit_code, output = container.exec_run(f"ls -lh {TEST_BINARY}")
    if exit_code == 0:
        print(f"✓ Binary created: {output.decode().strip()}")
    
    # Verify binary is executable
    exit_code, output = container.exec_run(f"test -x {TEST_BINARY}")
    if exit_code != 0:
        # Make it executable
        container.exec_run(f"chmod +x {TEST_BINARY}")
    
    print(f"{'='*60}\n")
    
    return TEST_BINARY


class TestXPKIActualKeys:
    """Test xPKI certificate procurement with actual EC keys."""
    
    def test_seed_p12_exists(self, container):
        """Verify seed P12 file exists (prerequisite)."""
        print(f"\nChecking prerequisite: {SEED_P12}")
        
        exit_code, output = container.exec_run(f"test -f {SEED_P12}")
        
        if exit_code != 0:
            pytest.fail(
                f"Seed P12 not found: {SEED_P12}\n"
                "Run setup-pkcs11.sh first to create seed certificate"
            )
        
        # Get file details
        exit_code, output = container.exec_run(f"ls -lh {SEED_P12}")
        if exit_code == 0:
            print(f"✓ {output.decode().strip()}")
        
        # Verify P12 is valid
        verify_cmd = f"openssl pkcs12 -in {SEED_P12} -passin pass:changeit -noout -info"
        exit_code, output = container.exec_run(verify_cmd)
        
        if exit_code == 0:
            print("✓ Seed P12 is valid (OpenSSL can read it)")
        else:
            pytest.fail(f"Seed P12 is invalid:\n{output.decode()}")
    
    def test_xpki_server_reachable(self, container):
        """Verify xPKI server (mockxconf) is reachable."""
        print("\nChecking xPKI server connectivity...")
        
        # Try to connect to xPKI endpoint
        curl_cmd = "curl -k -s -o /dev/null -w '%{http_code}' https://mockxconf:50055/v1/certifier --max-time 5"
        exit_code, output = container.exec_run(curl_cmd, environment={"PATH": "/usr/local/bin:/usr/bin:/bin"})
        
        http_code = output.decode().strip()
        
        if http_code in ["200", "404", "405"]:
            print(f"✓ xPKI server reachable (HTTP {http_code})")
        else:
            pytest.skip(f"xPKI server not reachable (HTTP {http_code})")
    
    def test_xpki_actual_key_procurement(self, container, compiled_test):
        """
        Run xPKI actual key test.
        
        This test:
        1. Generates actual EC key pair (prime256v1) in memory
        2. Authenticates to xPKI using seed certificate (mTLS)
        3. Generates CSR with the actual key
        4. Obtains operational certificate from xPKI server
        5. Saves operational cert + actual key to P12 file
        """
        print(f"\n{'='*60}")
        print("Running xPKI Actual Key Test")
        print(f"{'='*60}\n")
        
        # Remove old output P12 if exists
        container.exec_run(f"rm -f {OUTPUT_P12}")
        
        # Set environment for libcertifier
        env = {
            "LD_LIBRARY_PATH": "/usr/local/lib:/usr/local/lib64",
            "PATH": "/usr/local/bin:/usr/bin:/bin"
        }
        
        # Run the test
        print(f"Executing: {compiled_test}")
        exit_code, output = container.exec_run(
            compiled_test,
            environment=env,
            stream=True
        )
        
        # Stream output in real-time
        full_output = []
        for chunk in output:
            decoded = chunk.decode('utf-8', errors='replace')
            print(decoded, end='')
            full_output.append(decoded)
        
        full_output_str = ''.join(full_output)
        
        print(f"\n{'='*60}")
        print(f"Test Exit Code: {exit_code}")
        print(f"{'='*60}\n")
        
        # Check exit code
        if exit_code != 0:
            # Check for specific error patterns
            if "ERROR: Seed P12 not found" in full_output_str:
                pytest.fail("Seed P12 missing - run setup-pkcs11.sh")
            elif "ERROR: Failed to generate EC key" in full_output_str:
                pytest.fail("OpenSSL EC key generation failed")
            elif "xc_get_cert() returned error" in full_output_str:
                # Extract error code if present
                import re
                match = re.search(r'Error code: (\d+)', full_output_str)
                if match:
                    error_code = match.group(1)
                    pytest.fail(f"xPKI server returned error {error_code}")
                else:
                    pytest.fail("xPKI certificate procurement failed")
            else:
                pytest.fail(f"Test failed with exit code {exit_code}")
        
        # Verify success message
        assert "SUCCESS: Certificate obtained from xPKI server" in full_output_str or \
               "Certificate already valid" in full_output_str, \
               "Test did not report success"
        
        print("✓ xPKI actual key test PASSED")
    
    def test_operational_p12_created(self, container):
        """Verify operational P12 file was created."""
        print(f"\nVerifying output P12: {OUTPUT_P12}")
        
        # Check file exists
        exit_code, output = container.exec_run(f"test -f {OUTPUT_P12}")
        
        if exit_code != 0:
            pytest.fail(f"Output P12 not created: {OUTPUT_P12}")
        
        # Get file details
        exit_code, output = container.exec_run(f"ls -lh {OUTPUT_P12}")
        if exit_code == 0:
            print(f"✓ {output.decode().strip()}")
        
        # Check file size is reasonable (should be > 1KB)
        exit_code, output = container.exec_run(f"stat -c %s {OUTPUT_P12}")
        if exit_code == 0:
            size = int(output.decode().strip())
            assert size > 1000, f"P12 file too small: {size} bytes"
            print(f"✓ File size: {size} bytes (valid)")
    
    def test_operational_p12_valid(self, container):
        """Verify operational P12 file is valid and contains expected data."""
        print(f"\nValidating P12 contents: {OUTPUT_P12}")
        
        # Verify P12 can be parsed
        verify_cmd = f"openssl pkcs12 -in {OUTPUT_P12} -passin pass:changeit -noout -info"
        exit_code, output = container.exec_run(verify_cmd)
        
        if exit_code != 0:
            pytest.fail(f"P12 file is invalid:\n{output.decode()}")
        
        print("✓ P12 file is valid (OpenSSL can parse it)")
        
        # Extract certificate
        cert_cmd = f"openssl pkcs12 -in {OUTPUT_P12} -passin pass:changeit -nokeys -clcerts"
        exit_code, output = container.exec_run(cert_cmd)
        
        if exit_code != 0:
            pytest.fail(f"Failed to extract certificate:\n{output.decode()}")
        
        cert_pem = output.decode()
        
        # Verify certificate exists
        assert "BEGIN CERTIFICATE" in cert_pem, "No certificate found in P12"
        print("✓ Certificate present in P12")
        
        # Verify certificate subject contains expected CN
        if "rdkv.cpe-clnt" in cert_pem or "Subject:" in cert_pem:
            print("✓ Certificate subject looks valid")
        
        # Extract private key (verify it exists)
        key_cmd = f"openssl pkcs12 -in {OUTPUT_P12} -passin pass:changeit -nocerts -nodes"
        exit_code, output = container.exec_run(key_cmd)
        
        if exit_code != 0:
            pytest.fail(f"Failed to extract private key:\n{output.decode()}")
        
        key_pem = output.decode()
        
        # Verify private key exists
        assert "BEGIN PRIVATE KEY" in key_pem or "BEGIN EC PRIVATE KEY" in key_pem, \
               "No private key found in P12"
        print("✓ Private key present in P12")
        
        # Verify it's an EC key
        if "EC PRIVATE KEY" in key_pem or "prime256v1" in key_pem:
            print("✓ Key is EC prime256v1")
    
    def test_cleanup(self, container):
        """Clean up test artifacts."""
        print("\nCleaning up test artifacts...")
        
        # Keep the P12 for manual inspection but remove the binary
        container.exec_run(f"rm -f {TEST_BINARY}")
        print(f"✓ Removed test binary: {TEST_BINARY}")
        print(f"ℹ Keeping P12 for inspection: {OUTPUT_P12}")


if __name__ == "__main__":
    # Allow running pytest directly
    pytest.main([__file__, "-v", "-s"])
