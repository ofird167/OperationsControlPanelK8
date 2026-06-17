import os

count = int(os.environ.get("CONTROL_PLANE_COUNT", "3"))

# Generate Inventory
inv = "[control_plane]\n"
for i in range(1, count + 1):
    inv += f"k8s-control-plane-{i} ansible_connection=docker\n"

inv += "\n[workers]\n"
inv += "k8s-worker-1 ansible_connection=docker\nk8s-worker-2 ansible_connection=docker\n"
inv += "\n[k8s_cluster:children]\ncontrol_plane\nworkers\n"

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
    playbook = re.sub(r"- name: Bootstrap Additional Control Plane Nodes\n  hosts:.*?\n", f"- name: Bootstrap Additional Control Plane Nodes\n  hosts: {hosts}\n", playbook)

with open("infra/ansible/playbook.yml", "w") as f:
    f.write(playbook)
