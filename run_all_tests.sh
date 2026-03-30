#!/bin/bash
##########################################################################
# Run All Integration Tests
# 
# Runs Docker container tests and xPKI PKCS#11 integration tests
##########################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Running Integration Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "✗ ERROR: Docker is not running"
    exit 1
fi
echo "✓ Docker is running"

# Check containers are up
REQUIRED_CONTAINERS=("mockxconf" "native-platform")
for container in "${REQUIRED_CONTAINERS[@]}"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "✗ ERROR: Container '${container}' is not running"
        echo "  Start containers: docker-compose up -d"
        exit 1
    fi
done
echo "✓ All required containers are running"

# Check pytest is available
if ! command -v pytest &> /dev/null; then
    echo "✗ ERROR: pytest is not installed"
    echo "  Install: pip install pytest docker"
    exit 1
fi
echo "✓ pytest is available"

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "Test Suite 1: Docker Container Validation"
echo "───────────────────────────────────────────────────────────────"
echo ""

# Run Docker container tests
cd "$SCRIPT_DIR"
pytest test_docker.py -v

TEST1_RESULT=$?

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "Test Suite 2: xPKI PKCS#11 Integration Tests"
echo "───────────────────────────────────────────────────────────────"
echo ""

# Run xPKI integration tests
pytest test/test_xpki_pkcs11_integration.py -v

TEST2_RESULT=$?

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Test Results Summary"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ $TEST1_RESULT -eq 0 ]; then
    echo "✓ Docker Container Tests: PASSED"
else
    echo "✗ Docker Container Tests: FAILED"
fi

if [ $TEST2_RESULT -eq 0 ]; then
    echo "✓ xPKI Integration Tests: PASSED"
else
    echo "✗ xPKI Integration Tests: FAILED"
fi

echo ""

# Overall result
if [ $TEST1_RESULT -eq 0 ] && [ $TEST2_RESULT -eq 0 ]; then
    echo "═══════════════════════════════════════════════════════════════"
    echo "All Tests PASSED ✓"
    echo "═══════════════════════════════════════════════════════════════"
    exit 0
else
    echo "═══════════════════════════════════════════════════════════════"
    echo "Some Tests FAILED ✗"
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi
