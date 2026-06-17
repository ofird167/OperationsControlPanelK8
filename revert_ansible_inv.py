with open('scripts/bootstrap.sh', 'r') as f:
    content = f.read()

bad_inv = """inv = "[control_plane]\\n"
for i in range(1, count + 1):
    # Map node index to IP
    ip = f"172.20.0.1{i-1}"
    inv += f"k8s-control-plane-{i} ansible_host={ip} ansible_connection=docker\\n"

inv += "\\n[workers]\\n"
inv += "k8s-worker-1 ansible_host=172.20.0.13 ansible_connection=docker\\nk8s-worker-2 ansible_host=172.20.0.14 ansible_connection=docker\\n\""""

good_inv = """inv = "[control_plane]\\n"
for i in range(1, count + 1):
    inv += f"k8s-control-plane-{i} ansible_connection=docker\\n"

inv += "\\n[workers]\\n"
inv += "k8s-worker-1 ansible_connection=docker\\nk8s-worker-2 ansible_connection=docker\\n\""""

content = content.replace(bad_inv, good_inv)

with open('scripts/bootstrap.sh', 'w') as f:
    f.write(content)
