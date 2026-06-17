import os
import re

# 1. Update .env and example.env
def update_env(filepath):
    if not os.path.exists(filepath):
        return
    with open(filepath, 'r') as f:
        content = f.read()
    if 'CONTROL_PLANE_COUNT' not in content:
        content += "\n# Set to 1 for lightweight laptops, or 3 for High Availability Quorum\nCONTROL_PLANE_COUNT=3\n"
        with open(filepath, 'w') as f:
            f.write(content)

update_env('example.env')
update_env('secrets/.env')

# 2. Update vms-up.sh
vms_up_patch = """
CONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-3}"

# 2. Define nodes and their IPs
declare -A NODES
NODES=( ["k8s-control-plane-1"]="172.20.0.10" )

if [ "$CONTROL_PLANE_COUNT" -eq 3 ]; then
    NODES+=([k8s-control-plane-2]="172.20.0.11" [k8s-control-plane-3]="172.20.0.12")
fi

NODES+=([k8s-worker-1]="172.20.0.13" [k8s-worker-2]="172.20.0.14")
"""

with open('infra/vms-up.sh', 'r') as f:
    vms_up_content = f.read()

vms_up_content = re.sub(
    r'# 2\. Define nodes and their IPs.*?# 3\. Create host directories',
    vms_up_patch.strip() + '\n\n# 3. Create host directories',
    vms_up_content,
    flags=re.DOTALL
)

with open('infra/vms-up.sh', 'w') as f:
    f.write(vms_up_content)

# 3. Update destroy.sh
destroy_patch = """
NETWORK_NAME="k8s-net"

# 1. Skip slow kubectl graceful deletions since we are destroying the VMs anyway
log_info "Bypassing graceful Kubernetes teardown to force-kill VM containers..."

# 2. Stop and remove node containers simulating VMs
log_info "Stopping and removing node containers..."
docker rm -f $(docker ps -a --format '{{.Names}}' | grep '^k8s-') >> "${LOG_FILE}" 2>&1 || true
"""

with open('scripts/destroy.sh', 'r') as f:
    destroy_content = f.read()

destroy_content = re.sub(
    r'NETWORK_NAME="k8s-net".*?# 3\. Delete custom docker bridge network',
    destroy_patch.strip() + '\n\n# 3. Delete custom docker bridge network',
    destroy_content,
    flags=re.DOTALL
)

with open('scripts/destroy.sh', 'w') as f:
    f.write(destroy_content)

print("Successfully updated vms-up.sh and destroy.sh")
