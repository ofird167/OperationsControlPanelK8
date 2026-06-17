import re

with open('infra/vms-up.sh', 'r') as f:
    content = f.read()

patch = """# Inject dynamic control plane scaling
CONTROL_PLANE_COUNT=${CONTROL_PLANE_COUNT:-1}

# Pre-flight Memory Check for HA
if [ "$CONTROL_PLANE_COUNT" -eq 3 ]; then
    # Get total docker memory in bytes
    DOCKER_MEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    # 12GB = 12884901888 bytes
    if [ "$DOCKER_MEM" -gt 0 ] && [ "$DOCKER_MEM" -lt 12884901888 ]; then
        echo -e "\e[33m[WARNING] Insufficient RAM for 3-Node HA Cluster (Less than 12GB available to Docker).\e[0m"
        echo -e "\e[33m[WARNING] Automatically downgrading to 1-Node Control Plane to prevent etcd quorum failure.\e[0m"
        CONTROL_PLANE_COUNT=1
    fi
fi

if [ "$CONTROL_PLANE_COUNT" -eq 3 ]; then"""

content = content.replace('CONTROL_PLANE_COUNT=${CONTROL_PLANE_COUNT:-1}\n\nif [ "$CONTROL_PLANE_COUNT" -eq 3 ]; then', patch)

with open('infra/vms-up.sh', 'w') as f:
    f.write(content)
