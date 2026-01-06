import docker
import pytest

# Initialize Docker client with compatibility mode for Colima
# Check the path of docker.sock in your host machine. If you are using colima use colima status to get
client = docker.DockerClient(base_url="unix:///var/run/docker.sock")

# Define container names
CONTAINERS = ["mockxconf", "native-platform"]

# Define expected open ports for mockxconf only (since you want IPv6 check for mockxconf)
MOCKXCONF_EXPECTED_PORTS = [50050, 50051, 50052, 50053, 50054, 50056]  # Example IPv6 ports for mockxconf

# Define expected files in each container
EXPECTED_FILES = {
    "mockxconf": ["/etc/xconf/certs/mock-xconf-server-cert.pem", "/etc/xconf/certs/mock-xconf-server-key.pem"],
    "native-platform": ["/usr/share/ca-certificates/mock-xconf-root-ca.pem", "/usr/share/ca-certificates/mock-xconf-intermediate-ca.pem"]
}

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

def test_node_processes_running_mockxconf(container):
    """Ensure exactly 8 Node.js processes are running inside mockxconf."""
    if container.name != "mockxconf":
        pytest.skip(f"Skipping Node.js process check for {container.name}")

    print(f"Checking Node.js processes in container: {container.name}")

    # Run `pgrep -c node` to count Node.js processes
    exit_code, output = container.exec_run("pgrep -c node")

    assert exit_code == 0, f"Failed to check Node.js processes in {container.name}!"
 
    node_process_count = int(output.strip())  # Convert output to integer
    print(f"Found {node_process_count} Node.js processes running in {container.name}")

    assert node_process_count == 8, f"Expected 6 Node.js processes, but found {node_process_count}!"
    print(f"✅ All 8 Node.js processes are running in {container.name}")

def test_files_exist(container):
    """Verify that expected files exist in the respective container."""
    container_name = container.name
    if container_name not in EXPECTED_FILES:
        pytest.skip(f"Skipping file check for unknown container {container_name}")

    expected_files = EXPECTED_FILES[container_name]
    print(f"Checking files in container: {container_name}")

    for file in expected_files:
        cmd = f"python3 -c 'import os; print(\"EXISTS\" if os.path.isfile(\"{file}\") else \"MISSING\")'"
        exit_code, output = container.exec_run(cmd)
        file_status = output.strip().decode()

        print(f"Checking file: {file} -> {file_status}")

        assert exit_code == 0, f"Error checking file {file} in {container_name}!"
        assert file_status == "EXISTS", f"File {file} is MISSING in {container_name}!"

    print(f"✅ All expected files are present in {container_name}")
