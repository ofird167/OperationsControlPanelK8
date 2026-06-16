#!/usr/bin/env bash
# scripts/destroy.sh: Master teardown and cleanup orchestrator.

set -euo pipefail

WORKSPACE_DIR="/home/devops-user/projects/interview10"
LOG_DIR="${WORKSPACE_DIR}/logs"
LOG_FILE="${LOG_DIR}/destroy.log"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"
echo "=== Teardown Log Started at $(date) ===" > "${LOG_FILE}"

# Helper function to print messages to stdout and log
log_info() {
    echo "[INFO] $1"
    echo "[INFO] $(date): $1" >> "${LOG_FILE}"
}

# Load environment variables
if [ -f "${ENV_FILE}" ]; then
    set -a
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
            eval "$line"
        fi
    done < "${ENV_FILE}"
    set +a
fi

NETWORK_NAME="k8s-net"
NODE_CONTAINERS=("k8s-control-plane" "k8s-worker-1" "k8s-worker-2")

# 1. Gracefully destroy Kubernetes LoadBalancer and Application resources first
if [ -f "${WORKSPACE_DIR}/secrets/k3s.kubeconfig" ]; then
    log_info "Destroying Kubernetes LoadBalancers and Application resources..."
    export KUBECONFIG="${WORKSPACE_DIR}/secrets/k3s.kubeconfig"
    
    # Delete Ingress and services first to free port maps
    kubectl delete -f "${WORKSPACE_DIR}/manifests/03-ingress.yaml" --ignore-not-found=true >> "${LOG_FILE}" 2>&1 || true
    kubectl delete -f "${WORKSPACE_DIR}/manifests/05-app-stack.yaml" --ignore-not-found=true >> "${LOG_FILE}" 2>&1 || true
    
    # Uninstall Helm charts
    helm uninstall prometheus -n monitoring >> "${LOG_FILE}" 2>&1 || true
    helm uninstall ingress-nginx -n ingress-nginx >> "${LOG_FILE}" 2>&1 || true
    helm uninstall metallb -n metallb-system >> "${LOG_FILE}" 2>&1 || true
    
    log_info "Kubernetes resources deleted successfully."
fi

# 2. Stop and remove node containers simulating VMs
log_info "Stopping and removing node containers..."
for container in "${NODE_CONTAINERS[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
        docker rm -f "${container}" >> "${LOG_FILE}" 2>&1 || true
        log_info "  Removed container: ${container}"
    fi
done

# 3. Delete custom docker bridge network
if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    docker network rm "${NETWORK_NAME}" >> "${LOG_FILE}" 2>&1 || true
    log_info "Removed docker network: ${NETWORK_NAME}"
fi

# 4. Clean up temporary rendered YAML manifests (leaving templates intact)
log_info "Cleaning up temporary rendered manifests..."
rm -f "${WORKSPACE_DIR}/manifests/02-metallb.yaml"
rm -f "${WORKSPACE_DIR}/manifests/03-ingress.yaml"
rm -f "${WORKSPACE_DIR}/manifests/05-app-stack.yaml"
rm -f "${WORKSPACE_DIR}/manifests/06-gitops.yaml"
rm -f "${WORKSPACE_DIR}/manifests/07-monitoring.yaml"
rm -f "${WORKSPACE_DIR}/secrets/k3s.kubeconfig"

log_info "Teardown complete. Environment is clean."
echo "------------------------------------------------------------"
echo " TEARDOWN COMPLETE"
echo "------------------------------------------------------------"
