#!/usr/bin/env bash
# aio.sh: All-In-One automated orchestrator

set -e

echo "========================================================="
echo " Starting All-In-One (AIO) Kubernetes Datacenter Setup"
echo "========================================================="

if [ ! -f "secrets/.env" ]; then
    echo "[WARNING] secrets/.env not found."
    echo "Please configure your environment variables first."
    ./scripts/get-secrets.sh
fi

echo "[INFO] Executing master bootstrap sequence..."
./scripts/bootstrap.sh

# Extract IP from logs or bootstrap.sh output for the Windows hosts file
source secrets/.env
INGRESS_IP=$(docker exec k8s-control-plane-1 kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "PENDING")

echo "========================================================="
echo " AIO SETUP COMPLETE!"
echo "========================================================="
echo "To map the domain on your Windows machine automatically, "
echo "copy and paste this exact command into an Administrator PowerShell:"
echo ""
echo "Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value \"${INGRESS_IP} \`t ${INGRESS_DOMAIN:-app.local}\""
echo "========================================================="
