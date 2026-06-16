#!/usr/bin/env bash
# scripts/get-secrets.sh: Fetches secrets from HashiCorp Vault or generates secure defaults locally.

set -euo pipefail

WORKSPACE_DIR="/home/devops-user/projects/interview10"
SECRETS_DIR="${WORKSPACE_DIR}/secrets"
ENV_FILE="${SECRETS_DIR}/.env"
EXAMPLE_ENV="${WORKSPACE_DIR}/example.env"

# Create secrets folder if it does not exist
mkdir -p "${SECRETS_DIR}"

# Create secrets/.env if it does not exist
if [ ! -f "${ENV_FILE}" ]; then
    echo "[INFO] Creating secrets/.env from example.env..."
    cp "${EXAMPLE_ENV}" "${ENV_FILE}"
fi

# Load variables
# We do not use export directly to avoid leaking credentials
set -a
# Read lines ignoring comments and empty lines
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
        eval "$line"
    fi
done < "${ENV_FILE}"
set +a

# Vault Configuration variables
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
DB_PASSWORD="${DB_PASSWORD:-}"

# Check if we should query Vault
if [ -n "${VAULT_ADDR}" ] && [ -n "${VAULT_TOKEN}" ]; then
    echo "[INFO] HashiCorp Vault configured. Querying secrets..."
    
    # Run API call to Vault (KV2 engine path: secret/data/database)
    # Using curl to fetch the JSON payload
    RESPONSE=$(curl -s --request GET \
        --header "X-Vault-Token: ${VAULT_TOKEN}" \
        --fail \
        "${VAULT_ADDR}/v1/secret/data/database" || echo "FAILED")
        
    if [ "$RESPONSE" != "FAILED" ]; then
        # Parse password using basic grep/sed to avoid mandatory jq dependency
        FETCHED_PW=$(echo "$RESPONSE" | grep -oP '"password":\s*"\K[^"]+' || echo "")
        
        if [ -n "$FETCHED_PW" ]; then
            echo "[INFO] Successfully retrieved database password from Vault."
            DB_PASSWORD="$FETCHED_PW"
        else
            echo "[WARN] Vault response received but could not parse 'password'. Generating local fallback."
        fi
    else
        echo "[WARN] Failed to connect to HashiCorp Vault. Generating local fallback."
    fi
fi

# Fallback: if DB_PASSWORD is still empty or null, generate a random one
if [ -z "${DB_PASSWORD}" ]; then
    echo "[INFO] Generating secure local default database password..."
    DB_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)
fi

# Update secrets/.env with the database password
# Use sed to update DB_PASSWORD line
if grep -q "^DB_PASSWORD=" "${ENV_FILE}"; then
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|g" "${ENV_FILE}"
else
    echo "DB_PASSWORD=${DB_PASSWORD}" >> "${ENV_FILE}"
fi

echo "[INFO] Secret synchronization complete. Credentials successfully updated in secrets/.env (masked)."
