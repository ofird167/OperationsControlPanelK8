#!/usr/bin/env bash
# scripts/bootstrap.sh: Master bootstrap orchestrator for the Kubernetes DevOps Assessment.

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${WORKSPACE_DIR}/logs"
LOG_FILE="${LOG_DIR}/bootstrap.log"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"
echo "=== Bootstrap Log Started at $(date) ===" > "${LOG_FILE}"

# Helper function to print messages to stdout and log
log_info() {
    echo "[INFO] $1"
    echo "[INFO] $(date): $1" >> "${LOG_FILE}"
}

log_error() {
    echo "[ERROR] $1" >&2
    echo "[ERROR] $(date): $1" >> "${LOG_FILE}"
}

# 1. Run secret retrieval
log_info "Synchronizing secrets and generating environment configuration..."
./scripts/get-secrets.sh >> "${LOG_FILE}" 2>&1

# Load environment variables
if [ -f "${ENV_FILE}" ]; then
    set -a
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
            eval "$line"
        fi
    done < "${ENV_FILE}"
    set +a
else
    log_error "Failed to locate secrets/.env file!"
    exit 1
fi

INGRESS_DOMAIN="${INGRESS_DOMAIN:-app.local}"
DB_USER="${DB_USER:-dbadmin}"
DB_NAME="${DB_NAME:-app_db}"
DB_PASSWORD="${DB_PASSWORD}"
GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-}"
CONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-3}"

# 2. Render templates
log_info "Interpolating configuration into manifest templates..."
./scripts/render-templates.sh >> "${LOG_FILE}" 2>&1

# 3. Spin up node containers
log_info "Launching 3 Ubuntu containers simulating cluster nodes..."
./infra/vms-up.sh >> "${LOG_FILE}" 2>&1

# Generate Ansible files dynamically based on CONTROL_PLANE_COUNT
log_info "Generating dynamic Ansible configuration for ${CONTROL_PLANE_COUNT} Control Plane nodes..."
cat << 'PYEOF' > "${WORKSPACE_DIR}/infra/ansible/generate.py"
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
PYEOF
python3 "${WORKSPACE_DIR}/infra/ansible/generate.py"

# 4. Build Ansible controller container
log_info "Compiling operations controller Docker image (k8s-ops-controller)..."
docker build -t k8s-ops-controller -f "${WORKSPACE_DIR}/infra/control/Dockerfile" "${WORKSPACE_DIR}/infra/control" >> "${LOG_FILE}" 2>&1

# 5. Run Ansible playbook inside controller container to bootstrap k3s
log_info "Running Ansible playbook inside controller to install and join k3s nodes..."
docker run --rm \
    --network k8s-net \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${WORKSPACE_DIR}":/workspace \
    -w /workspace/infra/ansible \
    k8s-ops-controller \
    ansible-playbook -i inventory.ini playbook.yml >> "${LOG_FILE}" 2>&1

# 6. Correct kubeconfig endpoint for host access
log_info "Configuring host kubeconfig routing endpoint..."
if [ -f "${WORKSPACE_DIR}/secrets/k3s.kubeconfig" ]; then
    log_info "Kubeconfig successfully written and configured in secrets/k3s.kubeconfig"
else
    log_error "secrets/k3s.kubeconfig not found! Bootstrap aborted."
    exit 1
fi

# 7. Build Application container images locally
log_info "Building frontend and API backend application Docker images..."
docker build -t backend:latest "${WORKSPACE_DIR}/app/backend" >> "${WORKSPACE_DIR}/logs/build-backend.log" 2>&1
docker build -t frontend:latest "${WORKSPACE_DIR}/app/frontend" >> "${WORKSPACE_DIR}/logs/build-frontend.log" 2>&1

log_info "Running Trivy Security Scanner on local images..."
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL backend:latest >> "${WORKSPACE_DIR}/logs/trivy-backend.log" 2>&1 || log_info "Trivy found vulnerabilities in backend, see logs/trivy-backend.log"
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL frontend:latest >> "${WORKSPACE_DIR}/logs/trivy-frontend.log" 2>&1 || log_info "Trivy found vulnerabilities in frontend, see logs/trivy-frontend.log"

# 8. Load images directly into k3s container registries
log_info "Importing application images into all node registries..."
if [ "${CONTROL_PLANE_COUNT}" -eq 3 ]; then
    node_list="k8s-control-plane-1 k8s-control-plane-2 k8s-control-plane-3 k8s-worker-1 k8s-worker-2"
else
    node_list="k8s-control-plane-1 k8s-worker-1 k8s-worker-2"
fi
for node in $node_list; do
    log_info "  Waiting for containerd socket on node: ${node}..."
    docker exec "${node}" bash -c '
        RETRIES=30
        while ! k3s ctr version >/dev/null 2>&1 && [ $RETRIES -gt 0 ]; do
            sleep 1
            RETRIES=$((RETRIES - 1))
        done
        k3s ctr version >/dev/null 2>&1
    ' >> "${LOG_FILE}" 2>&1 || {
        log_error "containerd socket not ready on ${node} within 30 seconds!"
        exit 1
    }
    
    log_info "  Importing images to node: ${node}"
    docker save backend:latest | docker exec -i "${node}" k3s ctr images import - >> "${LOG_FILE}" 2>&1
    docker save frontend:latest | docker exec -i "${node}" k3s ctr images import - >> "${LOG_FILE}" 2>&1
done

# 9. Launch Kubernetes installations via Controller
log_info "Deploying cluster addons, services, apps, and monitoring stacks..."
# We pass sensitive credentials via secure environment variables to the controller run command
docker run --rm \
    --network k8s-net \
    --dns 8.8.8.8 \
    -v "${WORKSPACE_DIR}":/workspace \
    -e KUBECONFIG=/workspace/secrets/k3s.kubeconfig \
    -e INGRESS_DOMAIN="${INGRESS_DOMAIN}" \
    -e DB_USER="${DB_USER}" \
    -e DB_NAME="${DB_NAME}" \
    -e DB_PASSWORD="${DB_PASSWORD}" \
    -e GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET}" \
    k8s-ops-controller \
    bash -c '
        set -euo pipefail
        echo "=== Deploying local-path StorageClass ==="
        kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
        kubectl patch storageclass local-path -p "{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}"
        
        echo "=== Installing MetalLB Layer 2 LoadBalancer ==="
        helm repo add metallb https://metallb.github.io/metallb
        helm repo update
        helm upgrade --install metallb metallb/metallb -n metallb-system --create-namespace --wait
        kubectl apply -f /workspace/manifests/02-metallb.yaml
        
        echo "=== Installing NGINX Ingress Controller ==="
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            -n ingress-nginx --create-namespace \
            --set controller.service.type=LoadBalancer \
            --wait
            
        echo "=== Generating Self-Signed TLS Certificates for Ingress ==="
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /tmp/tls.key -out /tmp/tls.crt \
            -subj "/CN=${INGRESS_DOMAIN}"
        kubectl create secret tls app-tls-secret --cert=/tmp/tls.crt --key=/tmp/tls.key -n default --dry-run=client -o yaml | kubectl apply -f -
        
        echo "=== Applying Ingress and Routing configuration ==="
        kubectl apply -f /workspace/manifests/03-ingress.yaml
        
        echo "=== Bootstrapping Argo Rollouts ==="
        kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
        
        echo "=== Deploying Application Stack ==="
        kubectl apply -f /workspace/manifests/05-app-stack.yaml
        
        echo "=== Deploying Network Policies ==="
        kubectl apply -f /workspace/manifests/08-network-policies.yaml
        
        echo "=== Bootstrapping ArgoCD ==="
        kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
        kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        # Apply GitOps Application configuration
        kubectl apply -f /workspace/manifests/06-gitops.yaml
        
        echo "=== Installing Velero for GCS Backups ==="
        helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
        helm repo update
        helm upgrade --install velero vmware-tanzu/velero \
            -n velero --create-namespace \
            --set configuration.provider=gcp \
            --set configuration.backupStorageLocation[0].provider=gcp \
            --set configuration.backupStorageLocation[0].name=default \
            --set configuration.backupStorageLocation[0].bucket=${GCS_BACKUP_BUCKET} \
            --set initContainers[0].name=velero-plugin-for-gcp \
            --set initContainers[0].image=velero/velero-plugin-for-gcp:v1.9.0 \
            --set initContainers[0].volumeMounts[0].mountPath=/target \
            --set initContainers[0].volumeMounts[0].name=plugins
        
        echo "=== Installing Linkerd Service Mesh ==="
        linkerd install --crds | kubectl apply -f -
        linkerd install | kubectl apply -f -
        kubectl annotate namespace default linkerd.io/inject=enabled --overwrite
        
        echo "=== Bootstrapping Observability (kube-prometheus-stack) ==="
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
        helm repo update
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            -n monitoring --create-namespace \
            --set grafana.enabled=true \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelix=false || \
        (echo "Retrying helm install..." && sleep 5 && helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            -n monitoring --create-namespace \
            --set grafana.enabled=true \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelix=false)
        kubectl apply -f /workspace/manifests/07-monitoring.yaml
    ' >> "${LOG_FILE}" 2>&1

log_info "Cluster bootstrap and deployment complete!"
log_info "Retrieve Ingress IP using: kubectl get svc -n ingress-nginx ingress-nginx-controller"

# Output instructions
INGRESS_IP=$(docker exec k8s-control-plane-1 kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "PENDING")

echo "------------------------------------------------------------"
echo " BOOTSTRAP COMPLETE"
echo "------------------------------------------------------------"
echo " Kubeconfig written to: secrets/k3s.kubeconfig"
echo " Ingress Domain:        ${INGRESS_DOMAIN}"
echo " MetalLB Ingress IP:    ${INGRESS_IP}"
echo ""
echo " To map the domain locally, add the following to hosts file:"
echo " ${INGRESS_IP}  ${INGRESS_DOMAIN}"
echo "------------------------------------------------------------"
