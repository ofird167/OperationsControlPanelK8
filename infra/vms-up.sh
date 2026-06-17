#!/usr/bin/env bash
# infra/vms-up.sh: Spins up three Ubuntu containers simulating VMs on a custom bridge network.

set -euo pipefail

WORKSPACE_DIR="/home/devops-user/projects/interview10"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"

# Load variables
if [ -f "${ENV_FILE}" ]; then
    set -a
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
            eval "$line"
        fi
    done < "${ENV_FILE}"
    set +a
else
    echo "[ERROR] secrets/.env file not found! Run get-secrets.sh first."
    exit 1
fi

SUBNET="${DOCKER_SUBNET:-172.20.0.0/16}"
GATEWAY="${DOCKER_GATEWAY:-172.20.0.1}"
NETWORK_NAME="k8s-net"

# 1. Create docker network if it doesn't exist
if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    echo "[INFO] Creating docker bridge network '${NETWORK_NAME}' (${SUBNET})..."
    docker network create \
        --subnet="${SUBNET}" \
        --gateway="${GATEWAY}" \
        "${NETWORK_NAME}"
else
    echo "[INFO] Docker network '${NETWORK_NAME}' already exists."
fi

CONTROL_PLANE_COUNT="${CONTROL_PLANE_COUNT:-3}"

# 2. Define nodes and their IPs
declare -A NODES
NODES=( ["k8s-control-plane-1"]="172.20.0.10" )

if [ "$CONTROL_PLANE_COUNT" -eq 3 ]; then
    NODES+=([k8s-control-plane-2]="172.20.0.11" [k8s-control-plane-3]="172.20.0.12")
fi

NODES+=([k8s-worker-1]="172.20.0.13" [k8s-worker-2]="172.20.0.14")

# 3. Create host directories for persistent storage volumes
mkdir -p "${WORKSPACE_DIR}/data/control-plane-1"
mkdir -p "${WORKSPACE_DIR}/data/control-plane-2"
mkdir -p "${WORKSPACE_DIR}/data/control-plane-3"
mkdir -p "${WORKSPACE_DIR}/data/worker-1"
mkdir -p "${WORKSPACE_DIR}/data/worker-2"

# 4. Spin up the simulated VM nodes
for node in "${!NODES[@]}"; do
    ip="${NODES[$node]}"
    
    # Remove existing container if it exists
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${node}$"; then
        echo "[INFO] Stopping and removing existing node container '${node}'..."
        docker rm -f "${node}" >/dev/null
    fi
    
    echo "[INFO] Starting node container '${node}' on IP ${ip}..."
    
    # Run container using standard ubuntu:22.04 with tail -f /dev/null to keep it alive
    docker run -d \
        --name "${node}" \
        --hostname "${node}" \
        --network "${NETWORK_NAME}" \
        --ip "${ip}" \
        --privileged \
        --cgroupns=host \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        -v "${WORKSPACE_DIR}/data/${node#k8s-}":/var/lib/rancher/k3s/storage \
        --restart unless-stopped \
        ubuntu:22.04 \
        tail -f /dev/null
done

echo "[INFO] All 5 node containers started successfully."
docker ps -f "name=k8s-"
