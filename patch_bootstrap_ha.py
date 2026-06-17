import re

with open('scripts/bootstrap.sh', 'r') as f:
    content = f.read()

# Add CONTROL_PLANE_COUNT to env vars
content = content.replace(
    'GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-}"',
    'GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-}"\nCONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-3}"'
)

# Insert the python generator before Step 4 (Build Ansible controller)
generator = """# Generate Ansible files dynamically based on CONTROL_PLANE_COUNT
log_info "Generating dynamic Ansible configuration for ${CONTROL_PLANE_COUNT} Control Plane nodes..."
cat << 'PYEOF' > "${WORKSPACE_DIR}/infra/ansible/generate.py"
import os

count = int(os.environ.get("CONTROL_PLANE_COUNT", "3"))

# Generate Inventory
inv = "[control_plane]\\n"
for i in range(1, count + 1):
    inv += f"k8s-control-plane-{i} ansible_connection=docker\\n"

inv += "\\n[workers]\\n"
inv += "k8s-worker-1 ansible_connection=docker\\nk8s-worker-2 ansible_connection=docker\\n"
inv += "\\n[k8s_cluster:children]\\ncontrol_plane\\nworkers\\n"

with open("infra/ansible/inventory.ini", "w") as f:
    f.write(inv)

# Read playbook and patch the target hosts
with open("infra/ansible/playbook.yml", "r") as f:
    playbook = f.read()

import re
if count == 1:
    # If 1 node, remove the Additional Control Plane section
    playbook = re.sub(r"- name: Bootstrap Additional Control Plane Nodes.*?- name: Bootstrap Worker Nodes", "- name: Bootstrap Worker Nodes", playbook, flags=re.DOTALL)
else:
    # If 3 nodes, ensure the additional nodes match count
    hosts = ", ".join([f"k8s-control-plane-{i}" for i in range(2, count + 1)])
    playbook = re.sub(r"- name: Bootstrap Additional Control Plane Nodes\\n  hosts:.*?\\n", f"- name: Bootstrap Additional Control Plane Nodes\\n  hosts: {hosts}\\n", playbook)

with open("infra/ansible/playbook.yml", "w") as f:
    f.write(playbook)
PYEOF
python3 "${WORKSPACE_DIR}/infra/ansible/generate.py"

# 4. Build Ansible controller container"""

content = content.replace('# 4. Build Ansible controller container', generator)

# Fix the image import loop
import_loop = """for node in k8s-control-plane-1 k8s-worker-1 k8s-worker-2; do
    if [ "${CONTROL_PLANE_COUNT}" -eq 3 ]; then
        node_list="k8s-control-plane-1 k8s-control-plane-2 k8s-control-plane-3 k8s-worker-1 k8s-worker-2"
    else
        node_list="k8s-control-plane-1 k8s-worker-1 k8s-worker-2"
    fi
    for node in $node_list; do"""
content = content.replace('for node in k8s-control-plane-1 k8s-control-plane-2 k8s-control-plane-3 k8s-worker-1 k8s-worker-2; do', import_loop)

with open('scripts/bootstrap.sh', 'w') as f:
    f.write(content)

print("Successfully updated bootstrap.sh for dynamic HA")
