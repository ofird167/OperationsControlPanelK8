#!/usr/bin/env bash
# scripts/render-templates.sh: Renders all .yaml.tmpl manifests using values from secrets/.env.

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${WORKSPACE_DIR}/secrets/.env"
MANIFESTS_DIR="${WORKSPACE_DIR}/manifests"

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

echo "[INFO] Rendering manifest templates..."

# Find all template files and render them using a short inline Python script
find "${MANIFESTS_DIR}" -name "*.yaml.tmpl" | while read -r template; do
    output_file="${template%.tmpl}"
    echo "  Rendering ${template##*/} -> ${output_file##*/}"
    
    python3 -c '
import os, sys, re
env_file = sys.argv[1]
template_file = sys.argv[2]
output_file = sys.argv[3]

# Load variables from env file into environment
with open(env_file, "r") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            if "=" in line:
                k, v = line.split("=", 1)
                os.environ[k.strip()] = v.strip()

# Read template content
with open(template_file, "r") as f:
    content = f.read()

# Replace ${VAR} with environment variables
def replace_env(match):
    var_name = match.group(1)
    return os.environ.get(var_name, match.group(0))

rendered = re.sub(r"\$\{([^}]+)\}", replace_env, content)

# Write output file
with open(output_file, "w") as f:
    f.write(rendered)
' "${ENV_FILE}" "${template}" "${output_file}"

done

echo "[INFO] Rendering complete."
