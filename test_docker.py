import docker
import pytest

# Initialize Docker client with compatibility mode for Colima
# Check the path of docker.sock in your host machine. If you are using colima use colima status to get
client = docker.DockerClient(base_url="unix:///var/run/docker.sock")

# Define container names
CONTAINERS = ["mockxconf", "native-platform"]

@pytest.fixture(scope="module", params=CONTAINERS)
def container(request):
    """Use existing running containers for testing in Colima."""
    container = client.containers.get(request.param)  # Fetch running container
    yield container  # Provide container for tests

def test_container_running(container):
    """Check if the container is running."""
    container.reload()  # Ensure we have the latest status
    assert container.status == "running"


