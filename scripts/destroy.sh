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

# 1. Skip slow kubectl graceful deletions since we are destroying the VMs anyway
log_info "Bypassing graceful Kubernetes teardown to force-kill VM containers..."

# 2. Stop and remove node containers simulating VMs
log_info "Stopping and removing node containers..."
docker rm -f $(docker ps -a --format '{{.Names}}' | grep '^k8s-') >> "${LOG_FILE}" 2>&1 || true

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
