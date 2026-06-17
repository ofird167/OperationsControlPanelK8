import re

with open('scripts/bootstrap.sh', 'r') as f:
    content = f.read()

# Add to env variables
content = content.replace(
    'DB_PASSWORD="${DB_PASSWORD}"',
    'DB_PASSWORD="${DB_PASSWORD}"\nGCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-}"'
)

# Add to docker run envs
content = content.replace(
    '-e DB_PASSWORD="${DB_PASSWORD}" \\',
    '-e DB_PASSWORD="${DB_PASSWORD}" \\\n    -e GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET}" \\'
)

# Add velero helm install
velero_install = """        echo "=== Installing Velero for GCS Backups ==="
        helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
        helm repo update
        helm upgrade --install velero vmware-tanzu/velero \\
            -n velero --create-namespace \\
            --set configuration.provider=gcp \\
            --set configuration.backupStorageLocation.name=default \\
            --set configuration.backupStorageLocation.bucket=${GCS_BACKUP_BUCKET} \\
            --set initContainers[0].name=velero-plugin-for-gcp \\
            --set initContainers[0].image=velero/velero-plugin-for-gcp:v1.9.0 \\
            --set initContainers[0].volumeMounts[0].mountPath=/target \\
            --set initContainers[0].volumeMounts[0].name=plugins
        
        echo "=== Bootstrapping Observability"""

content = content.replace('        echo "=== Bootstrapping Observability', velero_install)

with open('scripts/bootstrap.sh', 'w') as f:
    f.write(content)
    
print("Successfully updated bootstrap.sh for Velero.")
