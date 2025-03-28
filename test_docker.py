import docker
import pytest

# Initialize Docker client with compatibility mode for Colima
# Check the path of docker.sock in your host machine. If you are using colima use colima status to get
client = docker.DockerClient(base_url="unix:///var/run/docker.sock")

# Define container names
CONTAINERS = ["mockxconf", "native-platform"]

# Define expected open ports for mockxconf only (since you want IPv6 check for mockxconf)
MOCKXCONF_EXPECTED_PORTS = [50050, 50051, 50052, 50053, 50054, 50055, 600]  # Example IPv6 ports for mockxconf

@pytest.fixture(scope="module", params=CONTAINERS)
def container(request):
    """Use existing running containers for testing in Colima."""
    container = client.containers.get(request.param)  # Fetch running container
    yield container  # Provide container for tests

def test_container_running(container):
    """Check if the container is running."""
    container.reload()  # Ensure we have the latest status
    assert container.status == "running"

def test_ports_are_open_ipv6_mockxconf(container):
    """Verify that expected IPv6 ports are open inside the container (only for mockxconf)."""
    if container.name != "mockxconf":
        pytest.skip(f"Skipping IPv6 port test for {container.name}")

    print(f"Checking IPv6 ports for container: {container.name}")

    for port in MOCKXCONF_EXPECTED_PORTS:
        hex_port = format(port, '04x').upper()  # Convert port number to uppercase hex (e.g., 50050 -> 'C382')
        exit_code, output = container.exec_run("cat /proc/net/tcp6")

        print(f"Checking port {port} (Hex: {hex_port}) inside mockxconf...")

        assert exit_code == 0, f"Failed to check open ports in {container.name}!"
        assert f":{hex_port}" in output.decode(), f"Port {port} is NOT open in {container.name}!"
        print(f"✅ Port {port} is open in {container.name}")
