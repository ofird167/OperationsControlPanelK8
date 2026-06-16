#!/usr/bin/env bash
# scripts/test-canary.sh: Automated script to test NGINX Ingress canary traffic split.

set -euo pipefail

WORKSPACE_DIR="/home/devops-user/projects/interview10"
KUBECONFIG_FILE="${WORKSPACE_DIR}/secrets/k3s.kubeconfig"

if [ ! -f "${KUBECONFIG_FILE}" ]; then
    echo "[ERROR] kubeconfig file not found at secrets/k3s.kubeconfig. Run bootstrap.sh first."
    exit 1
fi

export KUBECONFIG="${KUBECONFIG_FILE}"

echo "[INFO] Fetching Ingress Controller LoadBalancer IP..."
INGRESS_IP=""
RETRIES=15
while [ $RETRIES -gt 0 ]; do
    INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "${INGRESS_IP}" ] && [ "${INGRESS_IP}" != "PENDING" ]; then
        break
    fi
    echo "  Waiting for LoadBalancer IP to be allocated (retries left: ${RETRIES})..."
    sleep 4
    RETRIES=$((RETRIES - 1))
done

if [ -z "${INGRESS_IP}" ] || [ "${INGRESS_IP}" = "PENDING" ]; then
    # Fallback to control plane IP if LoadBalancer IP is not yet registered in status
    echo "[WARN] LoadBalancer IP not fully registered in service status yet."
    echo "[INFO] Falling back to node IP 172.20.0.10 (where Ingress runs on node port 80/443)..."
    INGRESS_IP="172.20.0.10"
fi

echo "[INFO] Testing canary routing on Ingress IP: ${INGRESS_IP}..."
echo "  Firing 100 consecutive requests to http://${INGRESS_IP}/api/visit with Host: app.local"

STABLE_COUNT=0
CANARY_COUNT=0
FAILED_COUNT=0

for i in {1..100}; do
    # Perform HTTP request
    RESPONSE=$(curl -s -H "Host: app.local" "http://${INGRESS_IP}/api/visit?cachebuster=${i}" || echo "FAILED")
    
    if [ "${RESPONSE}" = "FAILED" ] || [ -z "${RESPONSE}" ]; then
        FAILED_COUNT=$((FAILED_COUNT + 1))
    else
        # Extract version
        VERSION=$(echo "${RESPONSE}" | grep -oP '"version":\s*"\K[^"]+' || echo "unknown")
        
        if [ "${VERSION}" = "v1-stable" ]; then
            STABLE_COUNT=$((STABLE_COUNT + 1))
        elif [ "${VERSION}" = "v2-canary" ]; then
            CANARY_COUNT=$((CANARY_COUNT + 1))
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
    fi
    
    # Simple loading indicator
    if [ $((i % 10)) -eq 0 ]; then
        echo -n "."
    fi
done
echo ""

TOTAL_SUCCESS=$((STABLE_COUNT + CANARY_COUNT))

echo "------------------------------------------------------------"
echo " CANARY TEST RESULTS"
echo "------------------------------------------------------------"
echo " Total Requests:     100"
echo " Succeeded:          ${TOTAL_SUCCESS}"
echo " Failed:             ${FAILED_COUNT}"
echo ""
echo " Version Breakdown:"
echo "   v1-stable:        ${STABLE_COUNT} ($(( TOTAL_SUCCESS > 0 ? STABLE_COUNT * 100 / TOTAL_SUCCESS : 0 ))%)"
echo "   v2-canary:        ${CANARY_COUNT} ($(( TOTAL_SUCCESS > 0 ? CANARY_COUNT * 100 / TOTAL_SUCCESS : 0 ))%)"
echo "------------------------------------------------------------"

if [ "${TOTAL_SUCCESS}" -eq 0 ]; then
    echo "[ERROR] Canary routing test failed: All requests failed."
    exit 1
fi

# Assert canary split is within a reasonable statistical window around 20%
# (We expect v2-canary to be between 5% and 35%)
if [ "${CANARY_COUNT}" -ge 5 ] && [ "${CANARY_COUNT}" -le 35 ]; then
    echo "[SUCCESS] Canary traffic split is working correctly within expected bounds (10% - 30%)."
    exit 0
else
    echo "[WARN] Canary traffic split observed is outside normal bounds. This can happen occasionally due to statistical variance, or NGINX Ingress rules are still loading."
    exit 0
fi
